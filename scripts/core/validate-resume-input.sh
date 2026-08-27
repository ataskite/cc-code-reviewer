#!/bin/bash
set -euo pipefail

# 恢复准入门禁（resume admission gate）：
#   validate-resume-input.sh <RUN_DIR> <PROJECT_DIR> [--rules]
#
# 分批审查恢复旧 RUN_DIR 之前，必须证明 plan.json 记录的冻结快照仍与现状对应。
# 本脚本只做「快照 vs 当前文件字节」的比对，假设运行期间没有第三方改写 RUN_DIR；
# 不重放冻结输入、不推导增量 diff、不做 HEAD 漂移检测——失败一律 fail-closed。
#
# 契约（stdout 恒为单行，供机器消费）：
#   exit 0  GATE_OK=<run_id>                     采纳 RUN_DIR，进入既有调度流程
#   exit 1  （无 stdout）                         用法错误 / 路径不存在（stderr 输出 ERROR_* 行）
#   exit 2  INPUT_CHANGED=<detail>               plan.review_input_sha256 != sha256(当前 review-input.json 字节)，
#                                                或冻结输入缺失而计划已声明，或 review_input_path 已不在 RUN_DIR 内
#   exit 3  RULES_CHANGED=<detail>               仅 --rules 时校验：规则快照哈希不一致；或 plan 缺
#                                                rules_snapshot_sha256 ⇒ legacy run lacks rules snapshot
#                                                未给 --rules 时完全跳过规则检查（向后兼容调用方）
#   exit 4  FROZEN_INPUT_MISSING=<detail>        plan.json 自身缺失 / 不可读 / 非 JSON 对象（无法门禁 ⇒ 拒绝采纳）
#
# stderr 面向人：ERROR_*=诊断键 + 建议：*处置提示。哈希算法与 prepare-review-input.sh /
# plan-file-batches.sh 一致：优先 shasum -a 256，回退 sha256sum，再回退 perl Digest::SHA；
# 计算对象恒为文件字节本身（不规范化 JSON）。

RUN_DIR=""
PROJECT_DIR=""
CHECK_RULES=0

for arg in "$@"; do
  case "$arg" in
    --rules) CHECK_RULES=1 ;;
    *) if [ -z "$RUN_DIR" ]; then RUN_DIR="$arg"
       elif [ -z "$PROJECT_DIR" ]; then PROJECT_DIR="$arg"
       else echo "ERROR_UNEXPECTED_ARGUMENT=$arg" >&2; exit 1; fi ;;
  esac
done

if [ -z "$RUN_DIR" ] || [ -z "$PROJECT_DIR" ]; then
  echo "ERROR_USAGE_MISSING_ARGS=<RUN_DIR> <PROJECT_DIR> [--rules] 均为必填参数" >&2
  exit 1
fi
if [ ! -d "$RUN_DIR" ]; then
  echo "ERROR_RUN_DIR_NOT_FOUND=${RUN_DIR}" >&2
  exit 1
fi
if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR_PROJECT_DIR_NOT_FOUND=${PROJECT_DIR}" >&2
  exit 1
fi

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else perl -MDigest::SHA -e 'my $f = shift; my $d = Digest::SHA->new(256); $d->addfile($f); print $d->hexdigest, "\n"' "$1"; fi
}

short12() { printf '%s' "${1:-empty}" | cut -c1-12; }

emit_and_exit() { # exit_code REASON detail hint
  local code="$1" reason="$2" detail="$3" hint="$4"
  printf '%s=%s\n' "$reason" "$detail"
  printf 'ERROR_%s=%s\n' "$reason" "$detail" >&2
  printf '建议：%s\n' "$hint" >&2
  exit "$code"
}

PLAN_JSON="$RUN_DIR/plan.json"

# 单次 perl 读取 plan.json 的标量字段：缺失/不可读/不可解析/非对象都走同一失败通道（exit 4）。
read_plan_fields() {
  perl -MJSON::PP -e '
    use strict; use warnings;
    my ($file) = @ARGV;
    open my $fh, "<", $file or die "UNREADABLE\n";
    local $/;
    my $data;
    eval { $data = decode_json(<$fh>) };
    die "UNPARSEABLE\n" if $@ || !defined $data || ref($data) ne "HASH";
    for my $k ("run_id","review_input_path","review_input_sha256","review_rules_resolved_path","rules_snapshot_sha256") {
      my $v = $data->{$k};
      $v = "" if !defined $v || ref($v);
      $v =~ s/\r?\n$//;
      print "${\uc($k)}=$v\n";
    }
  ' "$1"
}

PLAN_VALUES="$(read_plan_fields "$PLAN_JSON" 2>/dev/null)" || {
  emit_and_exit 4 FROZEN_INPUT_MISSING "plan.json missing or invalid: ${PLAN_JSON}" \
    "RUN_DIR 内 plan.json 缺失或不可解析，无法证明冻结输入可信——禁止沿用该计划，请新建审查计划。"
}
plan_field() {
  printf '%s\n' "$PLAN_VALUES" | sed -n "s/^$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')=//p"
}

RUN_ID_RECORDED="$(plan_field run_id)"
REVIEW_INPUT_DECLARED="$(plan_field review_input_path)"
REVIEW_INPUT_SHA_RECORDED="$(plan_field review_input_sha256 | tr 'A-Z' 'a-z')"
RULES_PATH_DECLARED="$(plan_field review_rules_resolved_path)"
RULES_SNAPSHOT_SHA_RECORDED="$(plan_field rules_snapshot_sha256 | tr 'A-Z' 'a-z')"

[ -n "$RUN_ID_RECORDED" ] || RUN_ID_RECORDED="$(basename "$RUN_DIR")"

# 相对路径按 RUN_DIR 解释（与 relocate/merge 对 RUN_DIR 产物的解析口径一致）。
resolve_against_run_dir() {
  case "$1" in
    "") printf '%s\n' "$2" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$RUN_DIR/$1" ;;
  esac
}

# 冻结输入定位 + 归属检查：必须仍在 RUN_DIR 内（绝对路径被搬去别的仓库 → 视同 INPUT_CHANGED）。
RUN_DIR_CANON="$(cd "$RUN_DIR" >/dev/null 2>&1 && pwd -P)" || RUN_DIR_CANON=""
REVIEW_INPUT_PATH_RESOLVED="$(resolve_against_run_dir "$REVIEW_INPUT_DECLARED" "$RUN_DIR/review-input.json")"
INPUT_INSIDE=0
if [ "${REVIEW_INPUT_PATH_RESOLVED#"$RUN_DIR"/}" != "$REVIEW_INPUT_PATH_RESOLVED" ]; then
  INPUT_INSIDE=1
elif [ -n "$RUN_DIR_CANON" ] && [ "${REVIEW_INPUT_PATH_RESOLVED#"$RUN_DIR_CANON"/}" != "$REVIEW_INPUT_PATH_RESOLVED" ]; then
  INPUT_INSIDE=1
fi
if [ "$INPUT_INSIDE" -ne 1 ]; then
    emit_and_exit 2 INPUT_CHANGED "review_input_path outside RUN_DIR: ${REVIEW_INPUT_PATH_RESOLVED}" \
      "输入已变化，旧批次结论不可混用——请新建审查计划或明确接受覆盖。"
fi
if [ ! -f "$REVIEW_INPUT_PATH_RESOLVED" ] || [ ! -r "$REVIEW_INPUT_PATH_RESOLVED" ]; then
  emit_and_exit 2 INPUT_CHANGED "frozen review-input.json missing: ${REVIEW_INPUT_PATH_RESOLVED}" \
    "输入已变化，旧批次结论不可混用——请新建审查计划或明确接受覆盖。"
fi
if [ -z "$REVIEW_INPUT_SHA_RECORDED" ]; then
  emit_and_exit 2 INPUT_CHANGED "plan.json lacks review_input_sha256 (cannot prove frozen input intact)" \
    "输入已变化，旧批次结论不可混用——请新建审查计划或明确接受覆盖。"
fi
REVIEW_INPUT_SHA_ACTUAL="$(sha256_file "$REVIEW_INPUT_PATH_RESOLVED")"
if [ "$(short12 "$REVIEW_INPUT_SHA_ACTUAL")" != "$(short12 "$REVIEW_INPUT_SHA_RECORDED")" ]; then
  emit_and_exit 2 INPUT_CHANGED "review-input.json sha256 mismatch recorded=$(short12 "$REVIEW_INPUT_SHA_RECORDED") actual=$(short12 "$REVIEW_INPUT_SHA_ACTUAL")" \
    "输入已变化，旧批次结论不可混用——请新建审查计划或明确接受覆盖。"
fi

# 规则快照检查仅在显式 --rules 时执行；未带旗标的调用方整体跳过（向后兼容）。
if [ "$CHECK_RULES" -eq 1 ]; then
  if [ -z "$RULES_SNAPSHOT_SHA_RECORDED" ]; then
    emit_and_exit 3 RULES_CHANGED "legacy run lacks rules snapshot" \
      "旧运行缺少规则快照哈希（legacy run），无法证明审查规则未被改动——请新建审查计划重新规划。"
  fi
  RULES_PATH_RESOLVED="$(resolve_against_run_dir "$RULES_PATH_DECLARED" "$RUN_DIR/review-rules.json")"
  if [ ! -f "$RULES_PATH_RESOLVED" ] || [ ! -r "$RULES_PATH_RESOLVED" ]; then
    emit_and_exit 3 RULES_CHANGED "review-rules.json missing: ${RULES_PATH_RESOLVED}" \
      "规则快照文件已丢失，旧批次结论不可混用——请新建审查计划重新规划。"
  fi
  RULES_SNAPSHOT_SHA_ACTUAL="$(sha256_file "$RULES_PATH_RESOLVED")"
  if [ "$(short12 "$RULES_SNAPSHOT_SHA_ACTUAL")" != "$(short12 "$RULES_SNAPSHOT_SHA_RECORDED")" ]; then
    emit_and_exit 3 RULES_CHANGED "review-rules.json sha256 mismatch recorded=$(short12 "$RULES_SNAPSHOT_SHA_RECORDED") actual=$(short12 "$RULES_SNAPSHOT_SHA_ACTUAL")" \
      "规则快照已变化，旧批次结论不可混用——请新建审查计划重新规划。"
  fi
fi

printf 'GATE_OK=%s\n' "$RUN_ID_RECORDED"
exit 0
