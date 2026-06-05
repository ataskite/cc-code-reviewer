#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
RUNS_ROOT="$PROJECT_DIR/.cc-code-reviewer/runs"

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
    *) echo "待执行" ;;
  esac
}

ceil_div() {
  local numerator="${1:-0}"
  local denominator="${2:-1}"
  if [ "$denominator" -le 0 ]; then
    denominator=1
  fi
  echo $(((numerator + denominator - 1) / denominator))
}

TARGET_REVIEW_COST=52000

target_batch_minutes() {
  case "${1:-standard}" in
    fast) echo 4 ;;
    deep) echo 15 ;;
    security) echo 10 ;;
    *) echo 8 ;;
  esac
}

batch_estimate_minutes() {
  local planned_cost="${1:-0}"
  local planned_loc="${2:-0}"
  local planned_files="${3:-0}"
  local review_mode="${4:-standard}"
  local target_minutes

  planned_cost="${planned_cost:-0}"
  planned_loc="${planned_loc:-0}"
  planned_files="${planned_files:-0}"
  if [ "$planned_cost" -le 0 ]; then
    planned_cost=$((planned_loc + planned_files * 25))
  fi
  target_minutes="$(target_batch_minutes "$review_mode")"
  local minutes
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
  local estimate_text
  estimate_text="串行约 $(estimate_minutes "$effective_limit" 1) 分钟"
  if [ "$effective_limit" -ge 2 ]; then
    estimate_text="$estimate_text / 2 路约 $(estimate_minutes "$effective_limit" 2) 分钟"
  fi
  if [ "$effective_limit" -ge 3 ]; then
    estimate_text="$estimate_text / 3 路约 $(estimate_minutes "$effective_limit" 3) 分钟"
  fi
  printf '%s 最多 %s 批 预估耗时: %s\n' \
    "$label" \
    "$effective_limit" \
    "$estimate_text"
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
  candidate_strategy="$(json_get "$plan_candidate" strategy)"
  if [ "$candidate_strategy" != "file-token-batching" ]; then
    RUN_DIR="$(dirname "$plan_candidate")"
    break
  fi
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
TOTAL_JAVA_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
TOTAL_JAVA_FILE_COUNT="$(json_get "$PLAN_PATH" total_java_file_count)"
BATCH_COUNT="$(json_get "$PLAN_PATH" batch_count)"

echo "大仓库审查任务"
echo "项目: ${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
echo "模式: ${REVIEW_MODE:-unknown}  范围: ${REVIEW_SCOPE:-全量代码}  语义: ${SEMANTIC_LEVEL:-maven-static}"
echo "批次数: ${BATCH_COUNT:-0}  Java 行数: $(format_number "$TOTAL_JAVA_LOC")  Java 文件: $(format_number "$TOTAL_JAVA_FILE_COUNT")"
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
  planned_loc="$(json_get "$batch_path" planned_java_loc)"
  planned_files="$(json_get "$batch_path" planned_java_file_count)"
  planned_cost="$(json_get "$batch_path" planned_review_cost)"
  if [ -f "$status_path" ]; then
    status="$(json_get "$status_path" status)"
    status_loc="$(json_get "$status_path" planned_java_loc)"
    status_files="$(json_get "$status_path" planned_java_file_count)"
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
  if [ "$status" = "pending" ] || [ "$status" = "failed" ]; then
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
echo "Java 行覆盖: $(format_number "$COMPLETED_LOC") / $(format_number "$TOTAL_JAVA_LOC")"
echo
echo "本轮可执行批次: ${RUNNABLE_BATCHES[*]:-无}"
echo "说明: 已完成批次会自动跳过；待执行和失败待重试批次可以在本轮调度。"
echo "也可以自行输入批次号，例如 batch-002,batch-004 或 2,4,7。"

RUNNABLE_COUNT="${#RUNNABLE_BATCHES[@]}"
TARGET_MINUTES_PER_BATCH="$(target_batch_minutes "$REVIEW_MODE")"
echo
echo "推荐执行计划"
echo "预估耗时基于 ${REVIEW_MODE:-standard} 模式、各批 planned_review_cost 和 ${TARGET_REVIEW_COST} 目标批次成本；目标批次约 ${TARGET_MINUTES_PER_BATCH} 分钟，最终耗时会随机器性能和代码复杂度波动。"
display_dynamic_plan_rows "$RUNNABLE_COUNT"
