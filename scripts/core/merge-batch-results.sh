#!/bin/bash
set -euo pipefail

# 语言中立的批次结果合并：状态门禁、确定性去重、覆盖率、阶段性/完整报告判断。
# 字段名采用语言中立（source_* 而非 java_*），覆盖率展示名按 plan.json.language_id 切换。

RUN_DIR="${1:?请输入运行目录 RUN_DIR}"

[ -d "$RUN_DIR" ] || { echo "RUN_DIR_NOT_FOUND=$RUN_DIR" >&2; exit 1; }
PLAN_PATH="$RUN_DIR/plan.json"
[ -f "$PLAN_PATH" ] || { echo "PLAN_JSON_NOT_FOUND=$PLAN_PATH" >&2; exit 1; }

json_escape() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'; }
json_get() {
  perl -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($file, $key) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = decode_json(<$fh>);
    my $value = $data->{$key};
    print defined($value) ? $value : "";
  ' "$1" "$2"
}
resolve_result_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$RUN_DIR/$1" ;;
  esac
}
percent() { if [ "${2:-0}" -gt 0 ]; then echo $(( ${1:-0} * 100 / ${2:-0} )); else echo 0; fi; }
status_label() {
  case "${1:-pending}" in
    completed) echo "已完成" ;; failed) echo "失败" ;;
    running) echo "执行中" ;; partial) echo "部分完成待重跑" ;;
    *) echo "待执行" ;;
  esac
}
# ---- 批次失败归因（failure_class）----
# 封闭枚举（与 agents/*「中断归因枚举」表一致）：context_exhausted | tool_budget_exhausted |
# output_truncated | cancelled | unknown，共 5 个，禁止发明其他值。每批只解析一次，
# 错误列前缀、summary.json 的 failed_by_class 与 run-manifest 台账共用同一结果。
# 解析顺序：状态文件显式 failure_class（枚举内，含 unknown）→ error 文本确定性关键词
# 分类（大小写不敏感、按下述顺序首个命中生效）→ unknown（error 为空同样落到 unknown）。
# 中文短标签固定五选一：上下文耗尽 / 工具预算耗尽 / 输出中断 / 已取消 / 未知。
# 注意：枚举清单必须与下方 run-manifest perl 程序内的 %FC_ENUM 保持一致。
failure_class_label() {
  case "${1:-}" in
    context_exhausted) echo "上下文耗尽" ;; tool_budget_exhausted) echo "工具预算耗尽" ;;
    output_truncated) echo "输出中断" ;; cancelled) echo "已取消" ;;
    unknown) echo "未知" ;;
    *) echo "" ;;
  esac
}
resolve_failure_class() {
  # $1 = status.json 路径；$2 = 该批状态。仅 failed/partial 参与归因；其他状态输出空。
  # 枚举外值视为未填写（回落到关键词回退）。回退关键词族：
  #   上下文/context → context_exhausted；工具/轮次/tool → tool_budget_exhausted；
  #   中断/截断/truncat → output_truncated；取消/cancel/interrupt(ctrl) → cancelled；
  #   其余一律 unknown。注意：decode_json 返回字符序列，模式字面量必须以 `use utf8`
  #   声明为字符语义，中文关键词才能与 UTF-8 error 文本正确匹配。
  perl -MJSON::PP -e '
    use utf8;
    my ($file, $st) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $d = eval { decode_json(<$fh>) };
    exit 0 unless ref $d eq "HASH";
    my %enum = map { $_ => 1 } qw(context_exhausted tool_budget_exhausted output_truncated cancelled unknown);
    if (defined $d->{failure_class} && $enum{$d->{failure_class}}) { print "$d->{failure_class}\n"; exit 0; }
    exit 0 unless $st eq "failed" || $st eq "partial";
    my $e = lc($d->{error} // "");
    print "context_exhausted\n"     and exit 0 if $e =~ /上下文|context/;
    print "tool_budget_exhausted\n" and exit 0 if $e =~ /工具|轮次|tool/;
    print "output_truncated\n"      and exit 0 if $e =~ /中断|截断|truncat/;
    print "cancelled\n"             and exit 0 if $e =~ /取消|cancel|interrupt|ctrl/;
    print "unknown\n";
  ' "$1" "$2"
}
markdown_cell() { printf '%s' "$1" | tr '\n\r' '  ' | sed 's/|/\\|/g'; }
batch_modules() {
  perl -MJSON::PP -e '
    binmode STDOUT, ":utf8";
    my ($file) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = decode_json(<$fh>);
    my @modules;
    if (ref($data->{modules}) eq "ARRAY") {
      for my $m (@{$data->{modules}}) {
        if (ref($m) eq "HASH") { push @modules, $m->{name} // $m->{path}; }
        elsif (defined $m) { push @modules, $m; }
      }
    }
    if (!@modules && ref($data->{scan_roots}) eq "ARRAY") { @modules = @{$data->{scan_roots}}; }
    print join(",", @modules);
  ' "$1"
}
# 批次发现去重（内容指纹版，确定性、零 LLM）：同一缺陷跨批次常常只是措辞漂移
# （标题改写、标点差异、建议句序交换），因此身份不再锚定整块散文文本，而是锚定
# 稳定事实——借鉴 SARIF partialFingerprint 的 Path|Category|ExistingCode 组合：
#   指纹 = sha256_hex(文件路径 \0 维度标签 \0 归一化证据代码行)
#   - 文件路径：块内第一条 "- 文件：" 行取出的路径。保留原字节（同仓库范围写入，
#     不做相对化/大小写归一，避免误并），仅 trim 并统一 "\\" 为 "/"，再剥掉结尾一个
#     半角/全角 ":数字" 行号（行号跨批次漂移且已由上游重归档钩子修正）；无该行则 ""
#   - 维度标签：表头第一个 [...] 内层文本（内部连续空白折叠为单空格）；缺失为 ""
#   - 证据代码：块内第一个闭合围栏代码块的内容（围栏行允许缩进/带语言标记）；每行
#     按 relocate-findings.sh 的 norm_line 同口径归一（去 CR → trim → 剥一个 +/- 前缀
#     → 再 trim → 去尾空白），完全丢弃空行后按原顺序以 "\n" 连接；无闭合围栏或内容
#     全空时为 ""
# 兜底（防误吞）：块既无 "- 文件：" 行又无围栏证据时无法构成稳定身份，退回旧的
# 整块空白折叠键。两类键命名空间独立，绝不互相命中；相同键位置序首个命中者胜出。
# 存续块逐字节原样输出；`### batch-XXX - 模块` 分隔行不含 P0-P3/待确认前缀，
# 始终作为分隔符而非发现表头解析。计数：进入去重的发现总数与被合并的重复数写入
# 统计文件（第 3 参，可选；两行十进制），供 summary.json 的 dedup 对象与报告
# “跨批次去重”行披露；写文件失败即中断（调用方先 rm 保证干净起点）。
dedupe_issue_blocks() {
  CC_MERGE_DEDUP_STATS_FILE="${3:-}" perl -CS -Mutf8 -MEncode=encode_utf8 -MDigest::SHA=sha256_hex -e '
    use strict; use warnings;
    binmode STDIN, ":utf8"; binmode STDOUT, ":utf8";
    my $stats_file = $ENV{CC_MERGE_DEDUP_STATS_FILE} // "";
    my (%seen, @block, $in_issue);
    my ($input_blocks, $merged_dups) = (0, 0);
    sub collapse_ws {
      my $s = shift // "";
      $s =~ s/\s+/ /g;
      $s =~ s/^\s+//;
      $s =~ s/\s+$//;
      return $s;
    }
    # 证据行归一化：与 scripts/core/relocate-findings.sh 的 norm_line 完全一致口径
    # （步骤顺序不得调整，保证两处对同一行的归一结果逐字节相同）。
    sub norm_evidence_line {
      my $l = shift // "";
      $l =~ s/\r$//;
      $l =~ s/^\s+//;
      $l =~ s/^[-+]?//;
      $l =~ s/^\s+//;
      $l =~ s/\s+$//;
      return $l;
    }
    sub parse_dim_tag {
      my ($hdr) = @_;
      return "" unless $hdr =~ /\[([^\]]*)\]/;
      my $tag = collapse_ws($1);
      return $tag // "";
    }
    sub first_location_path {
      for (@_) {
        next unless /^-\s*文件：\s*(.*)$/;
        my $p = $1;
        $p =~ s/^\s+//;
        $p =~ s/\s+$//;
        return "" unless length $p;
        $p =~ s!\\!/!g;
        ($p =~ s/:([0-9]+)$//) || ($p =~ s/：([0-9]+)$//);
        return $p;
      }
      return "";
    }
    sub evidence_block {
      my ($open, $close);
      for my $i (0 .. $#_) {
        my $t = $_[$i];
        $t =~ s/^\s+//;
        $t =~ s/\s+$//;
        next unless $t =~ /^```/;
        if (!defined $open) { $open = $i; }
        else { $close = $i; last; }
      }
      return () unless defined $open && defined $close && $close > $open;
      my @ev;
      for my $i (($open + 1) .. ($close - 1)) {
        my $n = norm_evidence_line($_[$i]);
        push @ev, $n if length $n;
      }
      return @ev;
    }
    sub identity_key {
      my @all = @_;
      my @rest = @all; shift @rest;
      my @locs = grep { /^-\s*文件：/ } @rest;
      my @ev = evidence_block(@rest);
      if (!@locs && !@ev) {
        return ("legacy", collapse_ws(join("", @all)));
      }
      my $dim  = parse_dim_tag($all[0]);
      my $path = first_location_path(@rest);
      my $evid = @ev ? join("\n", @ev) : "";
      return ("fp", sha256_hex(encode_utf8(join("\x00", $path, $dim, $evid))));
    }
    sub flush_block {
      return unless @block;
      $input_blocks++;
      my ($namespace, $key) = identity_key(@block);
      my $full_key = "$namespace\0$key";
      if (!$seen{$full_key}++) { print @block; }
      else { $merged_dups++; }
      @block = ();
      $in_issue = 0;
    }
    while (my $line = <STDIN>) {
      if ($line =~ /^###\s+(?:P[0-3]|待确认)(?:\b|\s|\|)/) {
        flush_block();
        @block = ($line); $in_issue = 1; next;
      }
      if ($in_issue) {
        if ($line =~ /^##\s+/ || $line =~ /^###\s+/) { flush_block(); print $line; }
        else { push @block, $line; }
        next;
      }
      print $line;
    }
    flush_block();
    if (length $stats_file) {
      open my $sf, ">", $stats_file or die "DEDUP_STATS_WRITE_ERROR=$stats_file: $!\n";
      print {$sf} "$input_blocks\n$merged_dups\n";
      close $sf or die "DEDUP_STATS_CLOSE_ERROR=$stats_file: $!\n";
    }
  ' < "$1" > "$2"
}
count_issue_blocks() {
  { grep -E '^###[[:space:]]+(P[0-3]|待确认)([[:space:]]|[|]|$)' "$1" 2>/dev/null || true; } | wc -l | tr -d ' '
}
normalize_batch_id() {
  local raw="$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$raw" ] || return 0
  case "$raw" in
    batch-[0-9][0-9][0-9]) printf '%s\n' "$raw" ;;
    batch-[0-9]|[0-9]) printf 'batch-%03d\n' "${raw#batch-}" ;;
    batch-[0-9][0-9]) printf 'batch-%03d\n' "${raw#batch-}" ;;
    [0-9]*) printf 'batch-%03d\n' "$raw" ;;
    *) printf '%s\n' "$raw" ;;
  esac
}
json_string_array() {
  local first=1 item
  printf '['
  for item in "$@"; do
    [ -n "$item" ] || continue
    [ "$first" -eq 0 ] && printf ', '
    printf '"%s"' "$(json_escape "$item")"
    first=0
  done
  printf ']'
}

PROJECT_NAME="$(json_get "$PLAN_PATH" project_name)"
RUN_ID="$(json_get "$PLAN_PATH" run_id)"
REVIEW_MODE="$(json_get "$PLAN_PATH" review_mode)"
REVIEW_SCOPE="$(json_get "$PLAN_PATH" review_scope)"
LANGUAGE_ID="$(json_get "$PLAN_PATH" language_id)"
TOTAL_LOC="$(json_get "$PLAN_PATH" total_source_loc)"
[ -n "$TOTAL_LOC" ] || TOTAL_LOC="$(json_get "$PLAN_PATH" total_java_loc)"
TOTAL_FILE_COUNT="$(json_get "$PLAN_PATH" total_source_file_count)"
[ -n "$TOTAL_FILE_COUNT" ] || TOTAL_FILE_COUNT="$(json_get "$PLAN_PATH" total_java_file_count)"
BATCH_COUNT="$(json_get "$PLAN_PATH" batch_count)"

[ -n "$PROJECT_NAME" ] || PROJECT_NAME="project"
[ -n "$RUN_ID" ] || RUN_ID="$(basename "$RUN_DIR")"
[ -n "$REVIEW_MODE" ] || REVIEW_MODE="unknown"
[ -n "$REVIEW_SCOPE" ] || REVIEW_SCOPE="全量代码"
[ -n "$LANGUAGE_ID" ] || LANGUAGE_ID="java"
[ -n "$TOTAL_LOC" ] || TOTAL_LOC=0
[ -n "$TOTAL_FILE_COUNT" ] || TOTAL_FILE_COUNT=0
[ -n "$BATCH_COUNT" ] || BATCH_COUNT=0

case "$LANGUAGE_ID" in
  frontend) COVERAGE_LABEL="前端源码文件覆盖率" ;;
  python)   COVERAGE_LABEL="Python 文件覆盖率" ;;
  *)        COVERAGE_LABEL="Java 文件覆盖率" ;;
esac

ALL_BATCH_IDS=()
for bp in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$bp" ] || continue
  bid="$(json_get "$bp" batch_id)"; [ -n "$bid" ] || bid="$(basename "$bp" .json)"
  ALL_BATCH_IDS+=("$bid")
done

TARGET_BATCH_IDS=()
if [ -n "${RUN_BATCH_IDS:-}" ]; then
  normalized="$(printf '%s' "$RUN_BATCH_IDS" | perl -CS -Mutf8 -pe 's/[，、,\s]+/ /g')"
  for raw in $normalized; do
    bid="$(normalize_batch_id "$raw")"; [ -n "$bid" ] || continue
    TARGET_BATCH_IDS+=("$bid")
  done
else
  TARGET_BATCH_IDS=("${ALL_BATCH_IDS[@]}")
fi
TARGET_BATCH_COUNT="${#TARGET_BATCH_IDS[@]}"

batch_id_exists() { local e; for e in "${ALL_BATCH_IDS[@]}"; do [ "$e" = "$1" ] && return 0; done; return 1; }
for t in "${TARGET_BATCH_IDS[@]}"; do
  batch_id_exists "$t" || { echo "TARGET_BATCH_NOT_FOUND=$t" >&2; exit 1; }
done
is_target_batch() { local x; for x in "${TARGET_BATCH_IDS[@]}"; do [ "$x" = "$1" ] && return 0; done; return 1; }

target_has_nonterminal_batches() {
  local t sp st
  for t in "${TARGET_BATCH_IDS[@]}"; do
    sp="$RUN_DIR/results/$t.status.json"; st="pending"
    if [ -f "$sp" ]; then st="$(json_get "$sp" status)"; [ -n "$st" ] || st="pending"; fi
    case "$st" in completed|failed|partial) ;; *) return 0 ;; esac
  done
  return 1
}

MERGE_WAIT_TIMEOUT_SECONDS="${MERGE_WAIT_TIMEOUT_SECONDS:-300}"
MERGE_POLL_INTERVAL_SECONDS="${MERGE_POLL_INTERVAL_SECONDS:-5}"
WAIT_TIMED_OUT=false
if target_has_nonterminal_batches; then
  ws="$(date +%s)"
  while target_has_nonterminal_batches; do
    wn="$(date +%s)"
    [ $((wn - ws)) -ge "$MERGE_WAIT_TIMEOUT_SECONDS" ] && { WAIT_TIMED_OUT=true; break; }
    sleep "$MERGE_POLL_INTERVAL_SECONDS"
  done
fi

mkdir -p "$RUN_DIR/final"
COMPLETED_RESULTS="$RUN_DIR/final/.completed-results.md"
DEDUPED_RESULTS="$RUN_DIR/final/.deduped-results.md"
DEDUP_STATS_FILE="$RUN_DIR/final/.dedup-stats"
CROSS_BATCH_LEADS="$RUN_DIR/final/.cross-batch-leads.md"
BATCH_STATUS_TABLE="$RUN_DIR/final/.batch-status-table.md"
: > "$COMPLETED_RESULTS"; : > "$DEDUPED_RESULTS"; : > "$CROSS_BATCH_LEADS"; : > "$BATCH_STATUS_TABLE"
rm -f "$DEDUP_STATS_FILE"

COMPLETED_BATCHES=0; FAILED_BATCHES=0; PENDING_BATCHES=0; RUNNING_BATCHES=0; PARTIAL_BATCHES=0
COVERED_LOC=0; COVERED_FILES=0; TOTAL_FINDINGS=0
# failed_by_class 计数（仅统计 FAILED 批次；partial 不计入该对象）。
FC_FAILED_CTX=0; FC_FAILED_TOOL=0; FC_FAILED_TRUNC=0; FC_FAILED_CANCEL=0; FC_FAILED_UNKNOWN=0
INCLUDED_BATCHES=0; LEFTOVER_BATCHES=0; MERGE_BLOCKED=false
INCLUDED_BATCH_IDS=(); MERGED_BATCH_IDS=(); LEFTOVER_BATCH_IDS=(); PARTIAL_BATCH_IDS=()

{ echo "| 批次 | 状态 | 本轮主任务 | 合并处理 | 文件数 | 行数 | 模块 | 错误 |"; echo "|---|---|---|---|---:|---:|---|---|"; } > "$BATCH_STATUS_TABLE"

for bp in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$bp" ] || continue
  bid="$(json_get "$bp" batch_id)"; [ -n "$bid" ] || bid="$(basename "$bp" .json)"
  planned_loc="$(json_get "$bp" planned_source_loc)"
  [ -n "$planned_loc" ] || planned_loc="$(json_get "$bp" planned_java_loc)"
  planned_files="$(json_get "$bp" planned_source_file_count)"
  [ -n "$planned_files" ] || planned_files="$(json_get "$bp" planned_java_file_count)"
  [ -n "$planned_loc" ] || planned_loc=0
  [ -n "$planned_files" ] || planned_files=0

  sp="$RUN_DIR/results/$bid.status.json"; status="pending"; result_path=""; finding_count=0; error=""
  if [ -f "$sp" ]; then
    status="$(json_get "$sp" status)"
    sl="$(json_get "$sp" planned_source_loc)"; [ -n "$sl" ] || sl="$(json_get "$sp" planned_java_loc)"
    sf="$(json_get "$sp" planned_source_file_count)"; [ -n "$sf" ] || sf="$(json_get "$sp" planned_java_file_count)"
    result_path="$(json_get "$sp" result_path)"; finding_count="$(json_get "$sp" finding_count)"; error="$(json_get "$sp" error)"
    [ -n "$sl" ] && planned_loc="$sl"
    [ -n "$sf" ] && planned_files="$sf"
    [ -n "$finding_count" ] || finding_count=0
  fi
  [ -n "$status" ] || status="pending"

  resolved="$(resolve_result_path "$result_path")"
  target_label="否"; merge_action="未纳入本轮，遗留"; result_available=false
  [ -n "$resolved" ] && [ -f "$resolved" ] && result_available=true

  case "$status" in
    completed)
      COMPLETED_BATCHES=$((COMPLETED_BATCHES+1))
      if is_target_batch "$bid" && [ "$result_available" = true ]; then
        target_label="是"; merge_action="已纳入本次合并"
        INCLUDED_BATCHES=$((INCLUDED_BATCHES+1)); INCLUDED_BATCH_IDS+=("$bid"); MERGED_BATCH_IDS+=("$bid")
        COVERED_LOC=$((COVERED_LOC+planned_loc)); COVERED_FILES=$((COVERED_FILES+planned_files))
        { echo ""; echo "### $bid - $(batch_modules "$bp")"; echo ""; cat "$resolved"; echo ""; } >> "$COMPLETED_RESULTS"
        awk '/^##[[:space:]]*跨批依赖待复核/{c=1;next} /^##[[:space:]]/{c=0} c&&NF>0{print}' "$resolved" >> "$CROSS_BATCH_LEADS"
      elif is_target_batch "$bid"; then
        target_label="是"; merge_action="结果缺失遗留"; MERGE_BLOCKED=true
        LEFTOVER_BATCHES=$((LEFTOVER_BATCHES+1)); LEFTOVER_BATCH_IDS+=("$bid")
      else
        LEFTOVER_BATCHES=$((LEFTOVER_BATCHES+1)); LEFTOVER_BATCH_IDS+=("$bid")
      fi ;;
    failed)
      FAILED_BATCHES=$((FAILED_BATCHES+1))
      if is_target_batch "$bid"; then target_label="是"; merge_action="失败遗留"; MERGE_BLOCKED=true; fi
      LEFTOVER_BATCHES=$((LEFTOVER_BATCHES+1)); LEFTOVER_BATCH_IDS+=("$bid") ;;
    partial)
      # 部分完成：已产出 ≥1 正式发现并写入结果文件。目标批次纳入合并（发现计入
      # finding_count），但覆盖统计按保守口径不计入已覆盖；非目标批次保持遗留。
      PARTIAL_BATCHES=$((PARTIAL_BATCHES+1)); PARTIAL_BATCH_IDS+=("$bid")
      formal_finding_count=0
      if [ "$result_available" = true ]; then
        formal_finding_count="$(count_issue_blocks "$resolved")"
      fi
      case "$finding_count" in
        ''|*[!0-9]*) finding_count=0 ;;
      esac
      if is_target_batch "$bid" && [ "$result_available" = true ] \
        && [ "$finding_count" -gt 0 ] && [ "$formal_finding_count" -gt 0 ]; then
        target_label="是"; merge_action="部分完成已纳入"
        MERGED_BATCH_IDS+=("$bid")
        { echo ""; echo "### $bid - $(batch_modules "$bp")"; echo ""; cat "$resolved"; echo ""; } >> "$COMPLETED_RESULTS"
        awk '/^##[[:space:]]*跨批依赖待复核/{c=1;next} /^##[[:space:]]/{c=0} c&&NF>0{print}' "$resolved" >> "$CROSS_BATCH_LEADS"
      elif is_target_batch "$bid"; then
        # partial 必须同时提供 finding_count>0 和至少一个正式发现块；否则视为
        # 契约违规，与结果缺失的目标批次同等阻塞，避免把零产出当作成功。
        target_label="是"; MERGE_BLOCKED=true
        if [ "$result_available" = true ]; then
          merge_action="部分完成结果无正式发现遗留"
        else
          merge_action="部分完成结果缺失遗留"
        fi
        LEFTOVER_BATCHES=$((LEFTOVER_BATCHES+1)); LEFTOVER_BATCH_IDS+=("$bid")
      else
        merge_action="部分完成未纳入本轮，遗留"
        LEFTOVER_BATCHES=$((LEFTOVER_BATCHES+1)); LEFTOVER_BATCH_IDS+=("$bid")
      fi ;;
    running)
      RUNNING_BATCHES=$((RUNNING_BATCHES+1))
      if is_target_batch "$bid"; then target_label="是"; merge_action="未完成遗留"; MERGE_BLOCKED=true; fi
      LEFTOVER_BATCHES=$((LEFTOVER_BATCHES+1)); LEFTOVER_BATCH_IDS+=("$bid") ;;
    *)
      PENDING_BATCHES=$((PENDING_BATCHES+1))
      if is_target_batch "$bid"; then target_label="是"; merge_action="未完成遗留"; MERGE_BLOCKED=true; fi
      LEFTOVER_BATCHES=$((LEFTOVER_BATCHES+1)); LEFTOVER_BATCH_IDS+=("$bid") ;;
  esac

  if [ "$WAIT_TIMED_OUT" = true ] && is_target_batch "$bid"; then
    case "$status" in completed|failed|partial) ;; *) MERGE_BLOCKED=true; error="${error:-等待本轮批次完成超时}";; esac
  fi

  # 每批只解析一次失败归因（仅 failed/partial）：显式枚举 → error 关键词回退 → unknown。
  resolved_fc=""
  case "$status" in failed|partial) resolved_fc="$(resolve_failure_class "$sp" "$status")" ;; esac

  # 错误列展示：解析出的归因必有中文短标签（failed/partial 的封闭枚举五选一，含
  # unknown→未知），有非空错误文本时统一加「[标签] 」前缀；其余状态/空错误保持原文。
  display_error="$error"
  if [ -n "$display_error" ]; then
    fc_label="$(failure_class_label "$resolved_fc")"
    [ -n "$fc_label" ] && display_error="[$fc_label] $display_error"
  fi

  # summary.json 的 failed_by_class：只统计 FAILED 批次按解析后枚举归类；partial 不计入。
  if [ "$status" = "failed" ]; then
    case "$resolved_fc" in
      context_exhausted)     FC_FAILED_CTX=$((FC_FAILED_CTX + 1)) ;;
      tool_budget_exhausted) FC_FAILED_TOOL=$((FC_FAILED_TOOL + 1)) ;;
      output_truncated)      FC_FAILED_TRUNC=$((FC_FAILED_TRUNC + 1)) ;;
      cancelled)             FC_FAILED_CANCEL=$((FC_FAILED_CANCEL + 1)) ;;
      *)                     FC_FAILED_UNKNOWN=$((FC_FAILED_UNKNOWN + 1)) ;;
    esac
  fi

  printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$(markdown_cell "$bid")" "$(markdown_cell "$(status_label "$status")")" \
    "$target_label" "$(markdown_cell "$merge_action")" "$planned_files" "$planned_loc" \
    "$(markdown_cell "$(batch_modules "$bp")")" "$(markdown_cell "$display_error")" >> "$BATCH_STATUS_TABLE"
done

# 证据重归档钩子（fail-open）：以冻结审查输入（plan.json.review_input_path，缺省回退
# RUN_DIR/review-input.json）中 selected=true 的相对路径为范围清单，对已纳入批次结果
# 就地修正行号漂移并做跨文件唯一命中重归档。plan.json 字段缺失、清单不可解析、脚本
# 缺失或执行失败时只记录跳过原因，绝不阻断合并。必须在去重与计数之前运行。
RELOCATION_ENABLED=false
RELOC_SAME=0; RELOC_REFILED=0; RELOC_UNRESOLVED=0
RELOCATION_SKIP_REASON=""
RELOCATION_HAD_RESULTS=false
if [ -s "$COMPLETED_RESULTS" ]; then RELOCATION_HAD_RESULTS=true; fi
if [ "$RELOCATION_HAD_RESULTS" = true ]; then
  REVIEW_INPUT_FOR_RELOC="$(json_get "$PLAN_PATH" review_input_path)"
  if [ -n "$REVIEW_INPUT_FOR_RELOC" ]; then
    case "$REVIEW_INPUT_FOR_RELOC" in /*) ;; *) REVIEW_INPUT_FOR_RELOC="$RUN_DIR/$REVIEW_INPUT_FOR_RELOC" ;; esac
  elif [ -r "$RUN_DIR/review-input.json" ]; then
    REVIEW_INPUT_FOR_RELOC="$RUN_DIR/review-input.json"
  fi
  RELOCATION_MANIFEST=""
  if [ -r "$REVIEW_INPUT_FOR_RELOC" ]; then
    RELOCATION_MANIFEST="$(mktemp "${TMPDIR:-/tmp}/cc-merge-relocate.XXXXXX")"
    if ! perl -MJSON::PP -e '
      my ($file) = @ARGV;
      open my $fh, "<", $file or exit 1;
      local $/;
      my $data = eval { decode_json(<$fh>) };
      exit 1 unless defined $data && ref($data->{items}) eq "ARRAY";
      for my $item (@{$data->{items}}) {
        next unless ref($item) eq "HASH" && $item->{selected};
        my $path = $item->{path} // "";
        $path =~ s/\r?\n\z//;
        $path =~ s/^\s+//;
        $path =~ s/\s+$//;
        next unless length $path;
        print "$path\n";
      }
    ' "$REVIEW_INPUT_FOR_RELOC" > "$RELOCATION_MANIFEST" 2>/dev/null; then
      rm -f "$RELOCATION_MANIFEST"; RELOCATION_MANIFEST=""
      RELOCATION_SKIP_REASON="审查输入清单不可解析"
    elif [ ! -s "$RELOCATION_MANIFEST" ]; then
      rm -f "$RELOCATION_MANIFEST"; RELOCATION_MANIFEST=""
      RELOCATION_SKIP_REASON="审查输入清单无已选文件"
    fi
  else
    RELOCATION_SKIP_REASON="缺少冻结审查输入"
  fi
  if [ -n "$RELOCATION_MANIFEST" ]; then
    RELOCATE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/relocate-findings.sh"
    RELOCATION_PROJECT_DIR="$(json_get "$PLAN_PATH" project_dir)"
    if [ ! -f "$RELOCATE_SCRIPT" ]; then
      RELOCATION_SKIP_REASON="重归档脚本缺失"
    elif [ -z "$RELOCATION_PROJECT_DIR" ] || [ ! -d "$RELOCATION_PROJECT_DIR" ]; then
      RELOCATION_SKIP_REASON="plan.json 缺少可用 project_dir"
    elif RELOCATE_OUT="$(bash "$RELOCATE_SCRIPT" "$COMPLETED_RESULTS" "$RELOCATION_PROJECT_DIR" "$RELOCATION_MANIFEST" 2>/dev/null)"; then
      RELOCATION_ENABLED=true
      RELOC_SAME="$(printf '%s\n' "$RELOCATE_OUT" | sed -n 's/^RELOCATE_SAME_FILE_FIXED=//p')"
      RELOC_REFILED="$(printf '%s\n' "$RELOCATE_OUT" | sed -n 's/^RELOCATE_REFILED=//p')"
      RELOC_UNRESOLVED="$(printf '%s\n' "$RELOCATE_OUT" | sed -n 's/^RELOCATE_UNRESOLVED=//p')"
      [ -n "$RELOC_SAME" ] || RELOC_SAME=0
      [ -n "$RELOC_REFILED" ] || RELOC_REFILED=0
      [ -n "$RELOC_UNRESOLVED" ] || RELOC_UNRESOLVED=0
    else
      RELOCATION_SKIP_REASON="重归档脚本执行失败"
    fi
    rm -f "$RELOCATION_MANIFEST"
  fi
fi

dedupe_issue_blocks "$COMPLETED_RESULTS" "$DEDUPED_RESULTS" "$DEDUP_STATS_FILE"
TOTAL_FINDINGS="$(count_issue_blocks "$DEDUPED_RESULTS")"
# 去重披露（增量、schema_version 仍为 1）：N = 进入去重的发现总数（含各 included
# 批次全部正式块），K = 去重后计数（即 count_issue_blocks 结果），M = N - K
# （指纹键与旧折叠键合并的重复数；K 超过 N 的异常输入按 0 兜底）。
# N == 0 时不输出 dedup 键与“跨批次去重”行，保持旧输出的字节兼容。
DEDUP_INPUT_FINDINGS="0"
if [ -f "$DEDUP_STATS_FILE" ]; then
  dedup_raw_input="$(sed -n '1p' "$DEDUP_STATS_FILE")"
  case "$dedup_raw_input" in ''|*[!0-9]*) dedup_raw_input="0" ;; esac
  DEDUP_INPUT_FINDINGS="$dedup_raw_input"
fi
rm -f "$DEDUP_STATS_FILE"
DEDUP_MERGED_DUPLICATES=0
if [ "$DEDUP_INPUT_FINDINGS" -gt "$TOTAL_FINDINGS" ]; then
  DEDUP_MERGED_DUPLICATES=$((DEDUP_INPUT_FINDINGS - TOTAL_FINDINGS))
fi
FILE_COVERAGE="$(percent "$COVERED_FILES" "$TOTAL_FILE_COUNT")"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_PROJECT_NAME="$(printf '%s' "$PROJECT_NAME" | sed 's/[^A-Za-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')"
[ -n "$SAFE_PROJECT_NAME" ] || SAFE_PROJECT_NAME="project"
FINAL_REPORT="$RUN_DIR/final/code-review-report-$SAFE_PROJECT_NAME-$TIMESTAMP.md"

if [ "$MERGE_BLOCKED" = true ]; then
  REPORT_TITLE="[合并阻塞] 代码审查报告 - $PROJECT_NAME"
elif [ $((INCLUDED_BATCHES + PARTIAL_BATCHES)) -lt "$BATCH_COUNT" ] || [ "$PARTIAL_BATCHES" -gt 0 ]; then
  # 任何 partial 批次都意味着本轮未完整覆盖（其覆盖按保守口径不计入）→ 阶段性。
  REPORT_TITLE="[阶段性] 代码审查报告 - $PROJECT_NAME"
else
  REPORT_TITLE="代码审查报告 - $PROJECT_NAME"
fi

RELOCATION_SUMMARY_LINE=""
if [ "$RELOCATION_ENABLED" = true ]; then
  RELOCATION_SUMMARY_LINE="  \"relocation\": {\"enabled\": true, \"same_file_fixed\": $RELOC_SAME, \"refiled\": $RELOC_REFILED, \"unresolved\": $RELOC_UNRESOLVED},"
fi

DEDUP_SUMMARY_LINE=""
if [ "$DEDUP_INPUT_FINDINGS" -gt 0 ]; then
  DEDUP_SUMMARY_LINE="  \"dedup\": {\"input_findings\": $DEDUP_INPUT_FINDINGS, \"merged_duplicates\": $DEDUP_MERGED_DUPLICATES, \"output_findings\": $TOTAL_FINDINGS},"
fi

# failed_by_class（增量、schema_version 仍为 1）：按解析后枚举统计 FAILED 批次数，
# 五个键固定出现（含 0）保证形状稳定；计数值之和恒等于 failed_batches。
# 没有任何 failed 批次时整个对象省略，与全绿运行的旧输出逐字节兼容。
FAILED_BY_CLASS_LINE=""
if [ "$FAILED_BATCHES" -gt 0 ]; then
  FAILED_BY_CLASS_LINE="  \"failed_by_class\": {\"context_exhausted\": $FC_FAILED_CTX, \"tool_budget_exhausted\": $FC_FAILED_TOOL, \"output_truncated\": $FC_FAILED_TRUNC, \"cancelled\": $FC_FAILED_CANCEL, \"unknown\": $FC_FAILED_UNKNOWN},"
fi

cat > "$RUN_DIR/summary.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "language_id": "$(json_escape "$LANGUAGE_ID")",
  "completed_batches": $COMPLETED_BATCHES,
  "failed_batches": $FAILED_BATCHES,
${FAILED_BY_CLASS_LINE}
  "partial_batches": $PARTIAL_BATCHES,
  "partial_batch_ids": $(json_string_array ${PARTIAL_BATCH_IDS[@]+"${PARTIAL_BATCH_IDS[@]}"}),
  "pending_batches": $PENDING_BATCHES,
  "running_batches": $RUNNING_BATCHES,
  "batch_count": $BATCH_COUNT,
  "target_batch_count": $TARGET_BATCH_COUNT,
  "included_batches": $INCLUDED_BATCHES,
  "leftover_batches": $LEFTOVER_BATCHES,
  "merge_blocked": $MERGE_BLOCKED,
  "wait_timed_out": $WAIT_TIMED_OUT,
  "target_batch_ids": $(json_string_array ${TARGET_BATCH_IDS[@]+"${TARGET_BATCH_IDS[@]}"}),
  "included_batch_ids": $(json_string_array ${INCLUDED_BATCH_IDS[@]+"${INCLUDED_BATCH_IDS[@]}"}),
  "merged_batch_ids": $(json_string_array ${MERGED_BATCH_IDS[@]+"${MERGED_BATCH_IDS[@]}"}),
  "leftover_batch_ids": $(json_string_array ${LEFTOVER_BATCH_IDS[@]+"${LEFTOVER_BATCH_IDS[@]}"}),
  "covered_source_loc": $COVERED_LOC,
  "total_source_loc": $TOTAL_LOC,
  "covered_source_file_count": $COVERED_FILES,
  "total_source_file_count": $TOTAL_FILE_COUNT,
  "source_file_coverage_percent": $FILE_COVERAGE,
  "finding_count": $TOTAL_FINDINGS,
${RELOCATION_SUMMARY_LINE}
${DEDUP_SUMMARY_LINE}
  "report_title": "$(json_escape "$REPORT_TITLE")",
  "run_manifest_path": "$(json_escape "$RUN_DIR/run-manifest.json")",
  "final_report_path": "$(json_escape "$FINAL_REPORT")"
}
JSON
mv "$RUN_DIR/summary.json.tmp" "$RUN_DIR/summary.json"

# Java 兼容：补写 java_* 别名字段，保持调用方契约（java_loc_coverage_percent 等）。
# source_* 字段保留不动（前端/Python 契约 + merge 内部用）。
# 用正则就近插入，保持原 heredoc 的多行缩进格式（不重排字段、不改空格），避免破坏现有 grep 断言。
if [ "$LANGUAGE_ID" = "java" ]; then
  perl -i -pe '
    if (/"covered_source_loc":\s*(\d+)/) {
      my $v = $1;
      s/("covered_source_loc":\s*$v,)/$1\n  "covered_java_loc": $v,/;
    }
    if (/"total_source_loc":\s*(\d+)/) {
      my $v = $1;
      s/("total_source_loc":\s*$v,)/$1\n  "total_java_loc": $v,/;
    }
    if (/"covered_source_file_count":\s*(\d+)/) {
      my $v = $1;
      s/("covered_source_file_count":\s*$v,)/$1\n  "covered_java_file_count": $v,/;
    }
    if (/"total_source_file_count":\s*(\d+)/) {
      my $v = $1;
      s/("total_source_file_count":\s*$v,)/$1\n  "total_java_file_count": $v,/;
    }
    if (/"source_file_coverage_percent":\s*(\d+)/) {
      my $v = $1;
      s/("source_file_coverage_percent":\s*$v,)/$1\n  "java_file_coverage_percent": $v,\n  "java_loc_coverage_percent": $v,/;
    }
  ' "$RUN_DIR/summary.json" 2>/dev/null || true
fi

# P0: emit a machine-readable coverage ledger. It is intentionally derived
# from batch files and status files, never from Markdown findings. The legacy
# flat coverage array is kept for compatibility; coverage_sets/terminal_state/
# stable item_id fields provide the stronger OCR-inspired audit contract.
RUN_MANIFEST="$RUN_DIR/run-manifest.json"
perl -MJSON::PP -MFile::Spec -MCwd=abs_path -e '
  use strict; use warnings; use Digest::SHA qw(sha256_hex);
  my ($run,$plan,$summary,$out)=@ARGV;
  sub loadj { my $p=shift; open my $f,"<",$p or die "read $p: $!"; local $/; return decode_json(<$f>); }
  my $p=loadj($plan); my $s=loadj($summary);
  my %included=map { $_=>1 } @{$s->{included_batch_ids}||[]};
  my %target=map { $_=>1 } @{$s->{target_batch_ids}||[]};
  my @items;
  my %batch_errors;
  # 状态文件显式声明的失败归因（枚举校验后收录；枚举外视为未填写）。
  my %batch_failure_classes;
  my %FC_ENUM = map { $_ => 1 } qw(context_exhausted tool_budget_exhausted output_truncated cancelled unknown);
  my %root_coverage;
  my $project=$p->{project_dir}||"";
  $project=(abs_path($project)||File::Spec->canonpath($project)) if length $project;
  $project =~ s![/\\]+$!!;
  sub normalized_item_path {
    my $path=shift//"";
    $path=(abs_path($path)||File::Spec->canonpath($path)) if File::Spec->file_name_is_absolute($path);
    $path =~ s!\\!/!g;
    my $root=$project; $root =~ s!\\!/!g;
    if (length($root) && ($path eq $root || index($path,"$root/")==0)) {
      $path=substr($path,length($root)); $path =~ s!^/!!;
    }
    $path =~ s!^\./!!;
    return $path;
  }
  sub git_output {
    my @cmd=@_; return () unless length($project) && -d $project && -e "$project/.git";
    open my $fh,"-|",@cmd or return ();
    my @lines=<$fh>; close $fh;
    chomp @lines; return grep { defined $_ && length $_ } @lines;
  }
  sub repository_identity {
    my ($remote)=git_output("git","-C",$project,"config","--get","remote.origin.url");
    if (defined $remote && length $remote) {
      $remote =~ s/^\s+|\s+$//g;
      my ($host,$path);
      if ($remote =~ m!^[^/@]+@([^:]+):(.+)$!) { ($host,$path)=($1,$2); }
      elsif ($remote =~ m!^[a-z][a-z0-9+.-]*://(?:[^/@]+@)?([^/]+)/(.+)$!i) { ($host,$path)=($1,$2); }
      if (defined $host && defined $path) {
        $host=lc($host); $path =~ s![/\\]+$!!; $path =~ s!\.git$!!i;
        return "remote\0$host/$path";
      }
    }
    my @roots=sort(git_output("git","-C",$project,"rev-list","--max-parents=0","HEAD"));
    return "roots\0".join("\0",@roots) if @roots;
    return "project-name\0".($p->{project_name}||"");
  }
  my $repository_identity_sha256=sha256_hex(repository_identity());
  opendir my $bd, "$run/batches" or die "read $run/batches: $!";
  my @batch_files=sort map { "$run/batches/$_" } grep { /^batch-.*\.json$/ && -f "$run/batches/$_" } readdir $bd;
  closedir $bd;
  for my $bp (@batch_files) {
    my $b=loadj($bp); my $id=$b->{batch_id}; my $status_path="$run/results/$id.status.json";
    my $status="pending"; if (-f $status_path) { my $sr=loadj($status_path); $status=$sr->{status}||"pending"; $batch_errors{$id}=$sr->{error}||""; $batch_failure_classes{$id}=$sr->{failure_class} if defined $sr->{failure_class} && $FC_ENUM{$sr->{failure_class}}; }
    my $coverage = $included{$id} ? "completed" : (!$target{$id} ? "leftover" : ($status eq "failed" ? "failed" : ($status eq "partial" ? "partial" : "leftover")));
    for my $root (@{$b->{scan_roots}||[]}) {
      next unless defined $root && length $root;
      $root_coverage{$root}={batch_id=>$id,status=>$coverage};
    }
    my $list=$b->{batch_file_list}||""; next unless $list && -f $list;
    open my $lf,"<",$list or die "read $list: $!";
    while (my $path=<$lf>) { chomp $path; next unless length $path; push @items,{path=>normalized_item_path($path),batch_id=>$id,status=>$coverage}; }
    close $lf;
  }
  my $input_path="$run/review-input.json";
  my $input = -f $input_path ? loadj($input_path) : undef;
  # Maven 大仓批次没有 batch_file_list。此时以冻结输入中的相对文件路径匹配
  # scan_roots（最长前缀优先），仍产出逐文件 completed/failed/leftover 台账。
  if (!@items && $input && ref($input->{items}) eq "ARRAY") {
    for my $item (@{$input->{items}}) {
      next unless ref($item) eq "HASH" && $item->{selected};
      my $path=normalized_item_path($item->{path} // next);
      my ($root)=sort { length($b) <=> length($a) || $a cmp $b }
        grep { $path eq $_ || index($path, "$_/") == 0 } keys %root_coverage;
      my $mapped=$root ? $root_coverage{$root} : undef;
      push @items,{path=>$path,batch_id=>($mapped ? $mapped->{batch_id} : ""),status=>($mapped ? $mapped->{status} : "leftover")};
    }
  }
  @items=sort { ($a->{path}//"") cmp ($b->{path}//"") || ($a->{batch_id}//"") cmp ($b->{batch_id}//"") } @items;
  sub item_id { sha256_hex(join("\0", "review", $repository_identity_sha256, $p->{language_id}||"", $_[0]||"")); }
  # error 文本确定性关键词分类器（大小写不敏感、顺序首个命中生效；与上方
  # resolve_failure_class 的回退族完全一致）：空文本/无命中一律 unknown。
  # `use utf8` 使模式字面量为字符语义，与 decode_json 解出的字符序列同构可比。
  use utf8;
  sub classify_error_text {
    my $e=lc($_[0]//"");
    return "context_exhausted"     if $e =~ /上下文|context/;
    return "tool_budget_exhausted" if $e =~ /工具|轮次|tool/;
    return "output_truncated"      if $e =~ /中断|截断|truncat/;
    return "cancelled"             if $e =~ /取消|cancel|interrupt|ctrl/;
    return "unknown";
  }
  # 每批只解析一次：显式 failure_class（枚举内）→ 关键词回退 → unknown。
  sub resolved_failure_class {
    my ($id)=@_;
    return $batch_failure_classes{$id} if $batch_failure_classes{$id};
    return classify_error_text($batch_errors{$id} // "");
  }
  for my $i (@items) {
    $i->{item_id}=item_id($i->{path});
    # failed/partial 台账统一携带解析后的失败归因枚举；included-partial 与 failed 的
    # 区分由 status 字段本身承担（partial 不再硬编码字面量 "partial" 作为归因）。
    if (($i->{status}||"") eq "failed") {
      $i->{failure_class}=resolved_failure_class($i->{batch_id});
      $i->{reason}=$batch_errors{$i->{batch_id}} if $batch_errors{$i->{batch_id}};
    } elsif (($i->{status}||"") eq "partial") {
      # partial 批次的 item_id 与 completed 完全一致（只由 path+仓库身份+语言派生）；
      # 覆盖计数保持保守。
      $i->{failure_class}=resolved_failure_class($i->{batch_id});
      $i->{reason}=$batch_errors{$i->{batch_id}} if $batch_errors{$i->{batch_id}};
    } elsif (($i->{status}||"") eq "leftover") {
      $i->{reason}="not included in current merge";
    }
  }
  sub coverage_item {
    my $i=shift; my %v=(item_id=>$i->{item_id},path=>$i->{path});
    $v{batch_id}=$i->{batch_id} if defined $i->{batch_id} && length $i->{batch_id};
    $v{old_path}=$i->{old_path} if defined $i->{old_path} && length $i->{old_path};
    $v{fingerprint}=$i->{fingerprint} if defined $i->{fingerprint} && length $i->{fingerprint};
    $v{failure_class}=$i->{failure_class} if defined $i->{failure_class};
    $v{reason}=$i->{reason} if defined $i->{reason} && length $i->{reason};
    return \%v;
  }
  my @completed=grep { ($_->{status}||"") eq "completed" } @items;
  my @failed=grep { ($_->{status}||"") eq "failed" } @items;
  my @partialcov=grep { ($_->{status}||"") eq "partial" } @items;
  my @leftover=grep { ($_->{status}||"") eq "leftover" } @items;
  my $terminal = $s->{merge_blocked} ? "failed" : (!@items ? "skipped" : (@completed == @items ? "complete" : ((@completed || @partialcov) ? "partial" : "failed")));
  my $input_mode = "workspace";
  if ($input && ($input->{selection_mode}||"") eq "incremental") { $input_mode="commit"; }
  my $coverage_percent = @items ? int(@completed * 100 / @items) : 0;
  my $coverage_sets={
    selected=>[map { coverage_item($_) } @items],
    completed=>[map { coverage_item($_) } @completed],
    reused=>[],
    failed=>[map { coverage_item($_) } @failed],
    waived=>[],
    leftover=>[map { coverage_item($_) } @leftover]
  };
  my $legacy_coverage=[];
  for my $i (@items) { push @$legacy_coverage, { %$i }; }
  my $d={schema_version=>1,contract_version=>"cc-code-reviewer.run-manifest/v1",run_id=>$p->{run_id},language_id=>$p->{language_id},terminal_state=>$terminal,repository_identity_sha256=>$repository_identity_sha256,input=>{mode=>$input_mode,requested_scope=>$p->{review_scope}||"",resolved_base=>($input ? $input->{base_ref}||"" : ""),resolved_head=>($input ? $input->{head_ref}||"" : ""),source_artifact_sha256=>($p->{review_input_sha256}||"")},execution=>{review_mode=>$p->{review_mode}||"",batch_count=>0+($p->{batch_count}||0),included_batch_count=>0+($s->{included_batches}||0)},review_input_path=>($input_path && -f $input_path ? $input_path : ""),review_input_sha256=>$p->{review_input_sha256}||"",coverage=>\@$legacy_coverage,coverage_sets=>$coverage_sets,selected_item_count=>0+@items,completed_item_count=>0+@completed,failed_item_count=>0+@failed,leftover_item_count=>0+@leftover,coverage_percent=>$coverage_percent,summary_path=>"$run/summary.json",final_report_path=>$s->{final_report_path}};
  if ($s->{merge_blocked}) { $d->{run_failure}={classification=>"unknown",reason=>"batch merge blocked"}; }
  $d->{review_input}= $input if $input;
  open my $of,">:encoding(UTF-8)",$out or die "write $out: $!"; print $of JSON::PP->new->canonical->pretty->encode($d);
' "$RUN_DIR" "$PLAN_PATH" "$RUN_DIR/summary.json" "$RUN_MANIFEST"

cat > "$FINAL_REPORT.tmp" <<MD
# $REPORT_TITLE

## 审查配置快照

- 生成时间：${TIMESTAMP}
- 审查类型：存量审查
- 审查范围：${REVIEW_SCOPE}
- 审查模式：${REVIEW_MODE}
- 语言：${LANGUAGE_ID}
- Run ID：${RUN_ID}
- 本轮主任务批次：${TARGET_BATCH_COUNT} / ${BATCH_COUNT}
- 已纳入合并批次：${INCLUDED_BATCHES}
- 遗留批次：${LEFTOVER_BATCHES}
- ${COVERAGE_LABEL}：${COVERED_FILES} / ${TOTAL_FILE_COUNT}（${FILE_COVERAGE}%）
MD

# Java 兼容：补发「审查范围说明」+「大仓库审查执行摘要」两个 Java 习惯的摘要段（前端/Python 报告保持精简）。
if [ "$LANGUAGE_ID" = "java" ]; then
  SEMANTIC_LEVEL="$(json_get "$PLAN_PATH" semantic_level)"
  cat >> "$FINAL_REPORT.tmp" <<MD

## 审查范围说明

- 项目名称：${PROJECT_NAME}
- 覆盖方式：合并本轮主任务中状态为“已完成”且结果文件存在的批次；partial 结果仅纳入已产出发现
- 覆盖口径：${COVERAGE_LABEL}只统计已纳入合并的批次文件数
- 未纳入范围：失败、待执行、执行中、结果缺失或未纳入本轮的批次，详见“批次状态总览”

## 大仓库审查执行摘要

- Run ID：${RUN_ID}
- 审查模式：${REVIEW_MODE}
- 审查范围：${REVIEW_SCOPE}
- 语义增强：${SEMANTIC_LEVEL:-maven-static}
- 本轮主任务批次：${TARGET_BATCH_COUNT} / ${BATCH_COUNT}
- 批次完成：${COMPLETED_BATCHES} / ${BATCH_COUNT}
- 失败待重试批次：${FAILED_BATCHES}
- 部分完成待重跑批次：${PARTIAL_BATCHES}
- 待执行批次：${PENDING_BATCHES}
- 执行中批次：${RUNNING_BATCHES}
- 已纳入本次合并批次：${INCLUDED_BATCHES}
- 遗留批次：${LEFTOVER_BATCHES}
- ${COVERAGE_LABEL}：${COVERED_FILES} / ${TOTAL_FILE_COUNT}（${FILE_COVERAGE}%）
- 已完成批次代码行规模：${COVERED_LOC} / ${TOTAL_LOC}（规划规模参考，不作为覆盖率口径）
- 已合并问题数：${TOTAL_FINDINGS}
MD
fi

cat >> "$FINAL_REPORT.tmp" <<'MD'

## 批次状态总览

MD

cat "$BATCH_STATUS_TABLE" >> "$FINAL_REPORT.tmp"
cat >> "$FINAL_REPORT.tmp" <<'MD'

## 已纳入批次发现

MD
if [ -s "$DEDUPED_RESULTS" ]; then cat "$DEDUPED_RESULTS" >> "$FINAL_REPORT.tmp"; else echo "暂无已纳入批次发现。" >> "$FINAL_REPORT.tmp"; fi

cat >> "$FINAL_REPORT.tmp" <<'MD'

## 跨批依赖线索

MD
if [ -s "$CROSS_BATCH_LEADS" ]; then sort -u "$CROSS_BATCH_LEADS" >> "$FINAL_REPORT.tmp"; else echo "暂无跨批依赖线索。" >> "$FINAL_REPORT.tmp"; fi

# Java 兼容：补发「覆盖限制与未审查范围」段（前端/Python 报告保持精简）
if [ "$LANGUAGE_ID" = "java" ]; then
  cat >> "$FINAL_REPORT.tmp" <<'MD'

## 覆盖限制与未审查范围

本报告的正式问题结论只来自已纳入本次合并的批次。未纳入本轮、失败、待执行、执行中或结果缺失的批次不会进入正式问题结论；这些批次需要在后续轮次继续执行或重试后再合并。
MD
fi

cat >> "$FINAL_REPORT.tmp" <<MD

## 覆盖说明

本报告合并本轮主任务中状态为"已完成"且结果文件存在的批次；状态为"部分完成"（partial）且结果文件存在的批次，其已产出发现同样纳入合并，但覆盖统计按保守口径不计入已覆盖。失败、待执行、执行中、结果缺失或未纳入本轮的批次不会进入正式问题结论，详见"批次状态总览"。
${COVERAGE_LABEL}是唯一覆盖指标；LOC 与 review cost 仅作为分批规划和进度参考。
MD
if [ "$RELOCATION_ENABLED" = true ] && [ "$RELOC_REFILED" -gt 0 ]; then
  echo "跨文件重归档：修正行号 ${RELOC_SAME} 处、迁移发现 ${RELOC_REFILED} 条（证据代码位于其他文件）。" >> "$FINAL_REPORT.tmp"
fi
if [ -n "$RELOCATION_SKIP_REASON" ] && [ "$RELOCATION_HAD_RESULTS" = true ]; then
  echo "# 跨文件重归档：跳过（${RELOCATION_SKIP_REASON}）" >> "$FINAL_REPORT.tmp"
fi
# 与 summary.json 的 dedup 对象同口径：仅当确实合并了重复（M > 0）时披露。
if [ "$DEDUP_MERGED_DUPLICATES" -gt 0 ]; then
  echo "跨批次去重：${DEDUP_INPUT_FINDINGS} 条发现中合并重复 ${DEDUP_MERGED_DUPLICATES} 条（按文件 × 维度 × 证据代码指纹），保留 ${TOTAL_FINDINGS} 条。" >> "$FINAL_REPORT.tmp"
fi

mv "$FINAL_REPORT.tmp" "$FINAL_REPORT"
rm -f "$COMPLETED_RESULTS" "$DEDUPED_RESULTS" "$CROSS_BATCH_LEADS" "$BATCH_STATUS_TABLE"

echo "SUMMARY_PATH=$RUN_DIR/summary.json"
echo "RUN_MANIFEST_PATH=$RUN_MANIFEST"
echo "FINAL_REPORT_PATH=$FINAL_REPORT"
if [ "$MERGE_BLOCKED" = true ]; then
  echo "MERGE_BLOCKED=true"
  exit 2
fi
exit 0
