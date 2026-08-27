#!/bin/bash
# 语言中立的批次状态展示（show-batch-status.sh）
#
# 字段读取按 plan.json.language_id 切换 + 读时 fallback 兼容两套字段名：
#   - Java（含旧 plan.json 缺 language_id 的）：读 total_java_loc / planned_java_loc
#   - 前端：读 total_source_loc / planned_source_loc
# 耗时模型复用同目录的 estimate-review-minutes.sh（单一真相源）。
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
RUNS_ROOT="$PROJECT_DIR/.cc-code-reviewer/runs"

# 复用语言中立的耗时模型（ceil_div / target_review_minutes / TARGET_REVIEW_COST_BASE），
# 与单 agent 预估耗时保持单一真相源。本脚本位于 core/，同目录引用。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/estimate-review-minutes.sh"

json_get() {
  local file="$1"
  local key="$2"
  perl -CS -Mutf8 -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($file, $key) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = decode_json(<$fh>);
    my $value = $data->{$key};
    print defined($value) ? $value : "";
  ' "$file" "$key"
}

batch_modules() {
  local file="$1"
  perl -CS -Mutf8 -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($file) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = decode_json(<$fh>);
    my @modules;
    my %seen;
    sub add_module {
      my ($name, $path, $kind) = @_;
      return if !defined($name) && !defined($path);
      $name = defined($name) && $name ne "" ? $name : $path;
      $path = defined($path) ? $path : "";
      $kind = defined($kind) ? $kind : "";

      my $partial = 0;
      $partial = 1 if $kind =~ /package/;
      $partial = 1 if $path =~ m#/src/main/java(?:/|$)#;
      $partial = 1 if $name =~ /:/;

      my $module = $name;
      my $name_declares_parent = $module =~ s/:.*$//;
      if (!$name_declares_parent && $path =~ m#^(.+?)/src/main/java(?:/|$)#) {
        $module = $1;
      }
      $module =~ s#/$##;
      $module = $name if $module eq "";

      my $label = $partial ? "$module（部分）" : $module;
      return if $seen{$label}++;
      push @modules, $label;
    }
    if (ref($data->{units}) eq "ARRAY") {
      for my $unit (@{$data->{units}}) {
        if (ref($unit) eq "HASH") {
          add_module($unit->{name}, $unit->{path}, $unit->{kind});
        } elsif (defined $unit) {
          add_module($unit, "", "");
        }
      }
    }
    if (!@modules && ref($data->{modules}) eq "ARRAY") {
      for my $module (@{$data->{modules}}) {
        if (ref($module) eq "HASH") {
          add_module($module->{name}, $module->{path}, $module->{kind});
        } elsif (defined $module) {
          add_module($module, "", "");
        }
      }
    }
    if (!@modules && ref($data->{scan_roots}) eq "ARRAY") {
      for my $root (@{$data->{scan_roots}}) {
        add_module($root, $root, "");
      }
    }
    sub split_partial_suffix {
      my ($label) = @_;
      if ($label =~ /^(.*?)(（部分）)$/) {
        return ($1, $2);
      }
      return ($label, "");
    }
    sub shared_prefix {
      my (@values) = @_;
      return "" if @values < 2;
      my $prefix = shift @values;
      for my $value (@values) {
        my $limit = length($prefix) < length($value) ? length($prefix) : length($value);
        my $i = 0;
        $i++ while $i < $limit && substr($prefix, $i, 1) eq substr($value, $i, 1);
        $prefix = substr($prefix, 0, $i);
        last if $prefix eq "";
      }
      $prefix =~ s#[^-_/]*$##;
      return $prefix;
    }
    sub should_strip_prefix {
      my ($prefix) = @_;
      return 0 if !defined($prefix) || $prefix eq "";
      return 1 if $prefix =~ m#module[-_/]$#i;
      my @parts = grep { $_ ne "" } split m#[-_/]+#, $prefix;
      return @parts >= 2;
    }
    if (@modules >= 2) {
      my @bases;
      my @suffixes;
      for my $label (@modules) {
        my ($base, $suffix) = split_partial_suffix($label);
        push @bases, $base;
        push @suffixes, $suffix;
      }
      my $prefix = shared_prefix(@bases);
      if (should_strip_prefix($prefix)) {
        for my $i (0 .. $#modules) {
          my $base = $bases[$i];
          $base =~ s/^\Q$prefix\E//;
          $base = $bases[$i] if $base eq "";
          $modules[$i] = $base . $suffixes[$i];
        }
      }
    }
    print join(",", @modules);
  ' "$file"
}

format_number() {
  local value="${1:-0}"
  if [ -z "$value" ]; then
    value=0
  fi
  perl -e '
    my $n = shift;
    $n = 0 if !defined($n) || $n eq "";
    1 while $n =~ s/^(-?\d+)(\d{3})/$1,$2/;
    print $n;
  ' "$value"
}

markdown_cell() {
  printf '%s' "${1:-}" | perl -CS -Mutf8 -pe 's/\r?\n/ /g; s/\|/\\|/g'
}

status_label() {
  case "${1:-pending}" in
    pending) echo "待执行" ;;
    running) echo "执行中" ;;
    completed) echo "已完成" ;;
    failed) echo "失败待重试" ;;
    partial) echo "部分完成待重跑" ;;
    *) echo "待执行" ;;
  esac
}

# ceil_div 已由 estimate-review-minutes.sh 提供（source 引入），此处不再重复定义

TARGET_REVIEW_COST_BASE=260000
TARGET_REVIEW_COST="$TARGET_REVIEW_COST_BASE"

target_batch_minutes() {
  # 委托给共享实现（单一真相源），保留函数名以兼容既有调用点与 plan.json 语义
  target_review_minutes "$@"
}

batch_estimate_minutes() {
  local planned_cost="${1:-0}"
  local planned_loc="${2:-0}"
  local planned_files="${3:-0}"
  local review_mode="${4:-standard}"
  local target_minutes

  planned_loc="${planned_loc:-0}"
  planned_files="${planned_files:-0}"
  # 始终用 review_cost_of(loc, files) = loc + files×25 重算成本，统一为时间估算口径。
  # 不使用 plan.json 的 planned_review_cost：对 Maven 它恰好是 loc+files×25（重算结果一致，零影响），
  # 但对前端文件级分批它是 token 口径（loc×3+files×500），量级大 3-6 倍，会严重虚高时间估算。
  planned_cost="$(review_cost_of "$planned_loc" "$planned_files")"
  target_minutes="$(target_review_minutes "$review_mode")"
  local minutes
  # 注意：批次模式使用从 plan.json budget 读取的 TARGET_REVIEW_COST，
  # 因此不复用 estimate_review_minutes（它用固定基准），而是就地保留历史算式，保证输出逐字节不变。
  minutes="$(ceil_div $((planned_cost * target_minutes)) "$TARGET_REVIEW_COST")"
  if [ "$minutes" -lt 1 ]; then
    minutes=1
  fi
  echo "$minutes"
}

estimate_minutes() {
  local batch_limit="$1"
  local concurrency="$2"
  local lane_loads=()
  local i lane min_lane max_load

  if [ "$concurrency" -le 0 ]; then
    concurrency=1
  fi
  for ((lane = 0; lane < concurrency; lane++)); do
    lane_loads[$lane]=0
  done

  for ((i = 0; i < batch_limit && i < ${#RUNNABLE_MINUTES[@]}; i++)); do
    min_lane=0
    for ((lane = 1; lane < concurrency; lane++)); do
      if [ "${lane_loads[$lane]}" -lt "${lane_loads[$min_lane]}" ]; then
        min_lane="$lane"
      fi
    done
    lane_loads[$min_lane]=$((lane_loads[$min_lane] + RUNNABLE_MINUTES[$i]))
  done

  max_load=0
  for ((lane = 0; lane < concurrency; lane++)); do
    if [ "${lane_loads[$lane]}" -gt "$max_load" ]; then
      max_load="${lane_loads[$lane]}"
    fi
  done
  echo "$max_load"
}

display_plan_row() {
  local label="$1"
  local batch_limit="$2"
  local runnable_count="$3"
  local effective_limit="$batch_limit"
  if [ "$effective_limit" -gt "$runnable_count" ]; then
    effective_limit="$runnable_count"
  fi
  if [ "$effective_limit" -lt 1 ]; then
    effective_limit=0
  fi
  # 不再展示预估耗时（系数未经充分校准，实际偏差大，反而误导）。
  # 保留批次选择信息，帮助用户选并发数。
  printf '%s（最多 %s 批）\n' "$label" "$effective_limit"
}

display_dynamic_plan_rows() {
  local runnable_count="$1"

  if [ "$runnable_count" -eq 0 ]; then
    echo "没有可执行批次；可先合并已完成批次或重新规划。"
    return
  fi

  if [ "$runnable_count" -eq 1 ]; then
    echo "仅 1 个可执行批次，将自动选择 ${RUNNABLE_BATCHES[0]}，并自动设置并发数为 1。"
    return
  fi

  if [ "$runnable_count" -eq 2 ]; then
    display_plan_row "执行 1 批" 1 "$runnable_count"
    display_plan_row "执行全部 2 批（推荐）" 2 "$runnable_count"
    return
  fi

  if [ "$runnable_count" -eq 3 ]; then
    display_plan_row "执行 1 批" 1 "$runnable_count"
    display_plan_row "执行 2 批" 2 "$runnable_count"
    display_plan_row "执行全部 3 批（推荐）" 3 "$runnable_count"
    return
  fi

  if [ "$runnable_count" -le 5 ]; then
    display_plan_row "执行 2 批" 2 "$runnable_count"
    display_plan_row "执行 3 批（推荐）" 3 "$runnable_count"
    display_plan_row "执行全部 ${runnable_count} 批" "$runnable_count" "$runnable_count"
    return
  fi

  display_plan_row "执行 3 批" 3 "$runnable_count"
  display_plan_row "执行 5 批（推荐）" 5 "$runnable_count"
  if [ "$runnable_count" -gt 10 ]; then
    display_plan_row "执行 10 批" 10 "$runnable_count"
  fi
  display_plan_row "执行全部 ${runnable_count} 批" "$runnable_count" "$runnable_count"
}

if [ ! -d "$RUNS_ROOT" ]; then
  echo "未找到大仓库审查任务：$PROJECT_DIR"
  exit 1
fi

RUN_DIR=""
while IFS= read -r plan_candidate; do
  RUN_DIR="$(dirname "$plan_candidate")"
  break
done < <(find "$RUNS_ROOT" -maxdepth 2 -type f -name 'plan.json' -print 2>/dev/null | sort -r)
if [ -z "$RUN_DIR" ] || [ ! -f "$RUN_DIR/plan.json" ]; then
  echo "未找到大仓库审查任务：$PROJECT_DIR"
  exit 1
fi

PLAN_PATH="$RUN_DIR/plan.json"
PROJECT_NAME="$(json_get "$PLAN_PATH" project_name)"
REVIEW_MODE="$(json_get "$PLAN_PATH" review_mode)"
REVIEW_SCOPE="$(json_get "$PLAN_PATH" review_scope)"
SEMANTIC_LEVEL="$(json_get "$PLAN_PATH" semantic_level)"
BATCH_COUNT="$(json_get "$PLAN_PATH" batch_count)"

# 按 language_id 切换展示文案；旧 Java plan.json 无此字段，默认 java
LANGUAGE_ID="$(json_get "$PLAN_PATH" language_id)"
[ -n "$LANGUAGE_ID" ] || LANGUAGE_ID="java"
case "$LANGUAGE_ID" in
  frontend) LOC_LABEL="前端源码行数"; FILE_LABEL="前端源码文件"; COVERAGE_LABEL="前端源码行覆盖" ;;
  python)   LOC_LABEL="Python 行数";   FILE_LABEL="Python 文件";   COVERAGE_LABEL="Python 行覆盖" ;;
  *)        LOC_LABEL="Java 行数";    FILE_LABEL="Java 文件";    COVERAGE_LABEL="Java 行覆盖" ;;
esac
# 读时 fallback：先 source_*（前端），空则 java_*（Java）
TOTAL_LOC="$(json_get "$PLAN_PATH" total_source_loc)"
[ -n "$TOTAL_LOC" ] || TOTAL_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
TOTAL_FILE_COUNT="$(json_get "$PLAN_PATH" total_source_file_count)"
[ -n "$TOTAL_FILE_COUNT" ] || TOTAL_FILE_COUNT="$(json_get "$PLAN_PATH" total_java_file_count)"

# 读取计划中的批次成本，缺失时回退固定 1M 目标值 260000。
# Maven semantic planner 写 target_batch_cost；文件级 planner 写 batch_token_budget。
# budget 是嵌套对象，用 perl 从 plan.json 显式读取
TARGET_BATCH_COST="$(perl -MJSON::PP -e '
  my ($file) = @ARGV;
  open my $fh, "<", $file or exit 0;
  local $/;
  my $d = eval { decode_json(<$fh>) } or exit 0;
  my $b = $d->{budget} || {};
  print $b->{target_batch_cost} // $b->{batch_token_budget} // "";
' "$PLAN_PATH" 2>/dev/null || true)"
if [ -n "$TARGET_BATCH_COST" ] && [ "$TARGET_BATCH_COST" -gt 0 ] 2>/dev/null; then
  TARGET_REVIEW_COST="$TARGET_BATCH_COST"
fi
CONTEXT_SCALE="$(perl -MJSON::PP -e '
  my ($file) = @ARGV;
  open my $fh, "<", $file or exit 0;
  local $/;
  my $d = eval { decode_json(<$fh>) } or exit 0;
  my $b = $d->{budget} || {};
  print $b->{context_scale} // "";
' "$PLAN_PATH" 2>/dev/null || true)"
CONTEXT_SCALE="${CONTEXT_SCALE:-5}"

echo "大仓库审查任务"
echo "项目: ${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
echo "模式: ${REVIEW_MODE:-unknown}  范围: ${REVIEW_SCOPE:-全量代码}  语义: ${SEMANTIC_LEVEL:-maven-static}"
echo "上下文窗口: 1000000 tokens（固定 1M 分批）"
echo "批次数: ${BATCH_COUNT:-0}  ${LOC_LABEL}: $(format_number "$TOTAL_LOC")  ${FILE_LABEL}: $(format_number "$TOTAL_FILE_COUNT")"
echo
echo "| 批次 | 状态 | 行数 | 文件数 | 模块 |"
echo "|------|------|------:|------:|------|"

COMPLETED_LOC=0
RUNNABLE_BATCHES=()
RUNNABLE_MINUTES=()
for batch_path in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$batch_path" ] || continue
  batch_id="$(json_get "$batch_path" batch_id)"
  if [ -z "$batch_id" ]; then
    batch_id="$(basename "$batch_path" .json)"
  fi

  status_path="$RUN_DIR/results/$batch_id.status.json"
  status="pending"
  planned_loc="$(json_get "$batch_path" planned_source_loc)"
  [ -n "$planned_loc" ] || planned_loc="$(json_get "$batch_path" planned_java_loc)"
  planned_files="$(json_get "$batch_path" planned_source_file_count)"
  [ -n "$planned_files" ] || planned_files="$(json_get "$batch_path" planned_java_file_count)"
  planned_cost="$(json_get "$batch_path" planned_review_cost)"
  if [ -f "$status_path" ]; then
    status="$(json_get "$status_path" status)"
    status_loc="$(json_get "$status_path" planned_source_loc)"
    [ -n "$status_loc" ] || status_loc="$(json_get "$status_path" planned_java_loc)"
    status_files="$(json_get "$status_path" planned_source_file_count)"
    [ -n "$status_files" ] || status_files="$(json_get "$status_path" planned_java_file_count)"
    status_cost="$(json_get "$status_path" planned_review_cost)"
    if [ -n "$status_loc" ]; then
      planned_loc="$status_loc"
    fi
    if [ -n "$status_files" ]; then
      planned_files="$status_files"
    fi
    if [ -n "$status_cost" ]; then
      planned_cost="$status_cost"
    fi
  fi
  planned_loc="${planned_loc:-0}"
  planned_files="${planned_files:-0}"
  planned_cost="${planned_cost:-0}"
  modules="$(batch_modules "$batch_path")"

  if [ "$status" = "completed" ]; then
    COMPLETED_LOC=$((COMPLETED_LOC + planned_loc))
  fi
  if [ "$status" = "pending" ] || [ "$status" = "failed" ] || [ "$status" = "partial" ]; then
    RUNNABLE_BATCHES+=("$batch_id")
    RUNNABLE_MINUTES+=("$(batch_estimate_minutes "$planned_cost" "$planned_loc" "$planned_files" "$REVIEW_MODE")")
  fi

  printf '| %s | %s | %s | %s | %s |\n' \
    "$(markdown_cell "$batch_id")" \
    "$(markdown_cell "$(status_label "$status")")" \
    "$(format_number "$planned_loc")" \
    "$(format_number "$planned_files")" \
    "$(markdown_cell "$modules")"
done

echo
echo "${COVERAGE_LABEL}: $(format_number "$COMPLETED_LOC") / $(format_number "$TOTAL_LOC")"
echo
echo "本轮可执行批次: ${RUNNABLE_BATCHES[*]:-无}"
echo "说明: 已完成批次会自动跳过；待执行、失败待重试和部分完成待重跑批次可以在本轮调度（partial 整批重跑）。"
echo "也可以自行输入批次号，例如 batch-002,batch-004 或 2,4,7。"

RUNNABLE_COUNT="${#RUNNABLE_BATCHES[@]}"
echo
echo "推荐执行计划"
display_dynamic_plan_rows "$RUNNABLE_COUNT"
