#!/bin/bash
set -euo pipefail

# 恢复准入门禁 scripts/core/validate-resume-input.sh 的契约测试：
# - stdout 恒为单行：GATE_OK=<run_id> | INPUT_CHANGED=… | RULES_CHANGED=… | FROZEN_INPUT_MISSING=…
# - 退出码：0=GATE_OK；1=用法错误（stderr 输出 ERROR_* 行，无 stdout）；
#   2=INPUT_CHANGED；3=RULES_CHANGED（仅 --rules 时校验；未带旗标整体跳过）；
#   4=FROZEN_INPUT_MISSING（plan.json 缺失/不可读/非对象）
# - 规划器联动：core 与 Java 适配器产出的 plan.json 必须记录与文件字节一致的 rules_snapshot_sha256，
#   且真实 RUN_DIR 带 --rules 必须通过门禁
# - 确定性：同输入两次运行 stdout 与 stderr 完全一致

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/core-validate-resume.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

GATE="$ROOT_DIR/scripts/core/validate-resume-input.sh"

sha_of() {
  perl -MDigest::SHA -e 'my $f = shift; my $s = Digest::SHA->new(256); $s->addfile($f); print $s->hexdigest, "\n"' "$1"
}

flip_last_byte() { # 原地改写最后一个字节（不改长度，破坏哈希）
  local f="$1" sz
  sz="$(wc -c < "$f" | tr -d ' ')"
  printf 'x' | dd of="$f" bs=1 seek=$((sz - 1)) conv=notrunc 2>/dev/null
}

# 生成一个最小可用 RUN_DIR：冻结的 review-input.json + review-rules.json。
make_run() {
  local run="$1"
  mkdir -p "$run"
  printf '{\n  "schema_version": 1,\n  "language_id": "frontend",\n  "total_source_loc": 100,\n  "total_source_file_count": 2\n}\n' > "$run/review-input.json"
  printf '{"schema_version":1,"rules_path":"","rule_count":0,"files":[]}\n' > "$run/review-rules.json"
}

# 生成 plan.json：绝对路径记录；可选 rules_snapshot_sha256；rel_paths=relative 时按 RUN_DIR 相对记录。
write_plan() {
  local run="$1" proj="$2" input_sha="$3" rules_sha="${4:-}" rel_paths="${5:-}" \
        input_override="${6:-}" rules_override="${7:-}"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "run_id": "%s",\n' "$(basename "$run")"
    printf '  "project_dir": "%s",\n' "$proj"
    printf '  "review_mode": "standard",\n'
    printf '  "branch": "main",\n'
    printf '  "strategy": "file-token-batching",\n'
    if [ -n "$input_override" ]; then
      printf '  "review_input_path": "%s",\n' "$input_override"
    elif [ "$rel_paths" = "relative" ]; then
      printf '  "review_input_path": "review-input.json",\n'
    else
      printf '  "review_input_path": "%s/review-input.json",\n' "$run"
    fi
    printf '  "review_input_sha256": "%s",\n' "$input_sha"
    if [ -n "$rules_sha" ]; then
      printf '  "rules_snapshot_sha256": "%s",\n' "$rules_sha"
    fi
    if [ -n "$rules_override" ]; then
      printf '  "review_rules_resolved_path": "%s",\n' "$rules_override"
    elif [ "$rel_paths" = "relative" ]; then
      printf '  "review_rules_resolved_path": "review-rules.json",\n'
    else
      printf '  "review_rules_resolved_path": "%s/review-rules.json",\n' "$run"
    fi
    printf '  "total_source_loc": 100,\n'
    printf '  "total_source_file_count": 2,\n'
    printf '  "batch_count": 1,\n'
    printf '  "created_at": "2026-08-27T00:00:00Z"\n'
    printf '}\n'
  } > "$run/plan.json"
}

GATE_STATUS=0; GATE_OUT=""; GATE_ERR=""
run_gate() { # 其余参数透传给门禁（如 --rules）
  GATE_STATUS=0; GATE_OUT=""; GATE_ERR=""
  set +e
  GATE_OUT="$(bash "$GATE" "$@" 2>"$TMP/gate.err")"
  GATE_STATUS=$?
  set -e
  GATE_ERR="$(cat "$TMP/gate.err")"
}

assert_hard_usage_error() { # 无 stdout、exit 1、stderr 含 ERROR_ 行
  test "$GATE_STATUS" -eq 1 || { echo "FAIL: expected usage exit 1, got $GATE_STATUS" >&2; exit 1; }
  [ -z "$GATE_OUT" ] || { echo "FAIL: usage error must not print stdout: $GATE_OUT" >&2; exit 1; }
  grep -q '^ERROR_' <<<"$GATE_ERR" || { echo "FAIL: stderr missing ERROR_* label: $GATE_ERR" >&2; exit 1; }
}

assert_single_line_result() { # expected_reason expected_exit [expected_exit_is_zero]
  test "$GATE_STATUS" -eq "$2" || { echo "FAIL: exit code $GATE_STATUS != $2" >&2; exit 1; }
  [ "$(printf '%s\n' "$GATE_OUT" | awk 'END{print NR}')" -eq 1 ] || {
    echo "FAIL: stdout must be exactly one line, got: $GATE_OUT" >&2; exit 1; }
  grep -q "^$1=" <<<"$GATE_OUT" || {
    echo "FAIL: stdout not prefixed $1=: $GATE_OUT" >&2; exit 1; }
  if [ -n "${3:-}" ]; then
    grep -q '^建议：' <<<"$GATE_ERR" || { echo "FAIL: stderr missing 建议 hint: $GATE_ERR" >&2; exit 1; }
  fi
}

PROJ="$TMP/plain-proj"; mkdir -p "$PROJ/src"

# --- 用例 6：用法错误 —— 缺参 / 目录不存在 → exit 1 + ERROR_* 标签，无 stdout ---
run_gate ""; assert_hard_usage_error
run_gate "$TMP/run-only-one-arg"; assert_hard_usage_error
run_gate "$TMP/no-such-run" "$PROJ"; assert_hard_usage_error

mkdir -p "$TMP/run-ok"; make_run "$TMP/run-ok"
IN_SHA_OK="$(sha_of "$TMP/run-ok/review-input.json")"
RULES_SHA_OK="$(sha_of "$TMP/run-ok/review-rules.json")"
write_plan "$TMP/run-ok" "$PROJ" "$IN_SHA_OK" "$RULES_SHA_OK"
run_gate "$TMP/run-ok" "$TMP/no-such-project"; assert_hard_usage_error

# --- 用例 1：GATE_OK —— 双哈希匹配、--rules 下放行，stdout 单行且带 run_id ---
run_gate "$TMP/run-ok" "$PROJ" --rules
assert_single_line_result GATE_OK 0
test "$GATE_OUT" = "GATE_OK=$(basename "$TMP/run-ok")"

# --- 用例 8：确定性 —— 同输入两次运行（含 stderr）完全一致 ---
OUT_A="$GATE_OUT"; ERR_A="$GATE_ERR"
run_gate "$TMP/run-ok" "$PROJ" --rules
[ "$GATE_OUT" = "$OUT_A" ] && [ "$GATE_ERR" = "$ERR_A" ] || {
  echo "FAIL: nondeterministic gate output" >&2; exit 1; }

# --- 用例 1b：相对路径记录同样放行 ---
mkdir -p "$TMP/run-rel"; make_run "$TMP/run-rel"
REL_IN_SHA="$(sha_of "$TMP/run-rel/review-input.json")"
REL_RULES_SHA="$(sha_of "$TMP/run-rel/review-rules.json")"
write_plan "$TMP/run-rel" "$PROJ" "$REL_IN_SHA" "$REL_RULES_SHA" relative
run_gate "$TMP/run-rel" "$PROJ" --rules
assert_single_line_result GATE_OK 0

# --- 用例 2a：INPUT_CHANGED —— 追加一字节篡改 review-input.json ---
mkdir -p "$TMP/run-input-changed"; make_run "$TMP/run-input-changed"
IC_IN_SHA="$(sha_of "$TMP/run-input-changed/review-input.json")"
IC_RULES_SHA="$(sha_of "$TMP/run-input-changed/review-rules.json")"
write_plan "$TMP/run-input-changed" "$PROJ" "$IC_IN_SHA" "$IC_RULES_SHA"
printf 'x' >> "$TMP/run-input-changed/review-input.json"
run_gate "$TMP/run-input-changed" "$PROJ" --rules
assert_single_line_result INPUT_CHANGED 2 human-hint-check
grep -q 'mismatch' <<<"$GATE_OUT"
grep -q "${IC_IN_SHA:0:12}" <<<"$GATE_ERR"

# --- 用例 2b：INPUT_CHANGED 变体 —— 冻结输入缺失而计划已声明 ---
mkdir -p "$TMP/run-input-missing"; make_run "$TMP/run-input-missing"
IM_IN_SHA="$(sha_of "$TMP/run-input-missing/review-input.json")"
rm -f "$TMP/run-input-missing/review-input.json"
write_plan "$TMP/run-input-missing" "$PROJ" "$IM_IN_SHA" ""
run_gate "$TMP/run-input-missing" "$PROJ" --rules
assert_single_line_result INPUT_CHANGED 2 human-hint-check
grep -q 'missing' <<<"$GATE_OUT"

# --- 用例 2c：INPUT_CHANGED 变体 —— review_input_path 指向 RUN_DIR 之外 ---
mkdir -p "$TMP/outside-repo"
printf '{"moved":true}\n' > "$TMP/outside-repo/review-input.json"
OS_IN_SHA="$(sha_of "$TMP/outside-repo/review-input.json")"
mkdir -p "$TMP/run-outside"; make_run "$TMP/run-outside"
write_plan "$TMP/run-outside" "$PROJ" "$OS_IN_SHA" "" "" "$TMP/outside-repo/review-input.json"
run_gate "$TMP/run-outside" "$PROJ" --rules
assert_single_line_result INPUT_CHANGED 2 human-hint-check
grep -q 'outside RUN_DIR' <<<"$GATE_OUT"

# --- 用例 3：规则漂移 —— review-rules.json 翻转一字节：--rules → exit 3；无旗标 → exit 0（向后兼容钉死）---
mkdir -p "$TMP/run-rules-drift"; make_run "$TMP/run-rules-drift"
RD_IN_SHA="$(sha_of "$TMP/run-rules-drift/review-input.json")"
RD_RULES_SHA="$(sha_of "$TMP/run-rules-drift/review-rules.json")"
write_plan "$TMP/run-rules-drift" "$PROJ" "$RD_IN_SHA" "$RD_RULES_SHA"
flip_last_byte "$TMP/run-rules-drift/review-rules.json"
run_gate "$TMP/run-rules-drift" "$PROJ" --rules
assert_single_line_result RULES_CHANGED 3 human-hint-check
grep -q 'mismatch' <<<"$GATE_OUT"
run_gate "$TMP/run-rules-drift" "$PROJ"
assert_single_line_result GATE_OK 0

# --- 用例 4：legacy —— plan 缺 rules_snapshot_sha256 且带 --rules → exit 3 固定原因串；
#     同一计划不带 --rules 时仍放行 ---
mkdir -p "$TMP/run-legacy"; make_run "$TMP/run-legacy"
LG_IN_SHA="$(sha_of "$TMP/run-legacy/review-input.json")"
write_plan "$TMP/run-legacy" "$PROJ" "$LG_IN_SHA"
run_gate "$TMP/run-legacy" "$PROJ" --rules
assert_single_line_result RULES_CHANGED 3 human-hint-check
test "$GATE_OUT" = "RULES_CHANGED=legacy run lacks rules snapshot"
run_gate "$TMP/run-legacy" "$PROJ"
assert_single_line_result GATE_OK 0

# --- 用例 5：FROZEN_INPUT_MISSING —— plan.json 缺失 / 非法 JSON / 非 JSON 对象 ---
mkdir -p "$TMP/run-no-plan"; make_run "$TMP/run-no-plan"
rm -f "$TMP/run-no-plan/plan.json"
run_gate "$TMP/run-no-plan" "$PROJ" --rules
assert_single_line_result FROZEN_INPUT_MISSING 4 human-hint-check

mkdir -p "$TMP/run-corrupt-plan"; make_run "$TMP/run-corrupt-plan"
printf '{ oops not json\n' > "$TMP/run-corrupt-plan/plan.json"
run_gate "$TMP/run-corrupt-plan" "$PROJ" --rules
assert_single_line_result FROZEN_INPUT_MISSING 4 human-hint-check

mkdir -p "$TMP/run-array-plan"; make_run "$TMP/run-array-plan"
printf '[1,2,3]\n' > "$TMP/run-array-plan/plan.json"
run_gate "$TMP/run-array-plan" "$PROJ" --rules
assert_single_line_result FROZEN_INPUT_MISSING 4 human-hint-check

# --- 用例 7a：规划器联动 —— core plan-file-batches 的 plan.json 记录规则快照哈希且真实 RUN_DIR 过门禁 ---
CORE_D="$TMP/app"; mkdir -p "$CORE_D/src"
for i in 1 2 3; do
  seq 1 300 | sed 's/.*/export const value = 1;/' > "$CORE_D/src/m${i}.ts"
done
CORE_D="$(cd "$CORE_D" && pwd -P)"
CORE_MANIFEST="$(mktemp)"
find "$CORE_D/src" -name '*.ts' -print | sort > "$CORE_MANIFEST"
CORE_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260827-010000 \
            bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$CORE_D" "standard" "main" "frontend" "$CORE_MANIFEST")"
CORE_RUN_DIR="$(printf '%s\n' "$CORE_OUT" | sed -n 's/^RUN_DIR=//p')"
CORE_EXPECTED="$(sha_of "$CORE_RUN_DIR/review-rules.json")"
grep -Fq "\"rules_snapshot_sha256\": \"$CORE_EXPECTED\"" "$CORE_RUN_DIR/plan.json" || {
  echo "FAIL: core planner plan.json must record rules_snapshot_sha256 equal to review-rules.json bytes hash" >&2
  exit 1
}
if grep -q 'head_commit_sha256' "$CORE_RUN_DIR/plan.json"; then
  echo "FAIL: non-git core fixture must not record head_commit_sha256" >&2
  exit 1
fi
run_gate "$CORE_RUN_DIR" "$CORE_D" --rules
assert_single_line_result GATE_OK 0
test "$GATE_OUT" = "GATE_OK=20260827-010000-main-standard"

# --- 用例 7b：规划器联动 —— Java 适配器 plan-file-batches 同样记录快照哈希并过门禁 ---
JAVA_PROJ="$TMP/maven-single"
JAVA_SRC="$JAVA_PROJ/src/main/java/com/example/order"
JAVA_TEST_SRC="$JAVA_PROJ/src/test/java/com/example/order"
mkdir -p "$JAVA_SRC" "$JAVA_TEST_SRC"
cat > "$JAVA_PROJ/pom.xml" <<'XML'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>maven-single</artifactId>
  <version>1.0</version>
</project>
XML
for index in 1 2 3 4; do
  {
    echo "package com.example.order;"
    echo "public class OrderService${index} {"
    seq 1 200 | sed 's/.*/  public void m&() {}/'
    echo "}"
  } > "$JAVA_SRC/OrderService${index}.java"
done
{
  echo "package com.example.order;"
  echo "public class OrderServiceTest {"
  seq 1 50 | sed 's/.*/  public void t&() {}/'
  echo "}"
} > "$JAVA_TEST_SRC/OrderServiceTest.java"
JAVA_PROJ="$(cd "$JAVA_PROJ" && pwd -P)"
JAVA_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260827-020000 \
            bash "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh" "$JAVA_PROJ" "standard" "main")"
JAVA_RUN_DIR="$(printf '%s\n' "$JAVA_OUT" | sed -n 's/^RUN_DIR=//p')"
JAVA_EXPECTED="$(sha_of "$JAVA_RUN_DIR/review-rules.json")"
grep -Fq "\"rules_snapshot_sha256\": \"$JAVA_EXPECTED\"" "$JAVA_RUN_DIR/plan.json" || {
  echo "FAIL: java adapter plan.json must record rules_snapshot_sha256 equal to review-rules.json bytes hash" >&2
  exit 1
}
run_gate "$JAVA_RUN_DIR" "$JAVA_PROJ" --rules
assert_single_line_result GATE_OK 0

echo "PASS: core validate-resume-input"
