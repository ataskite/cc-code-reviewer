#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"
LANGUAGE_ID="${4:?请输入语言 ID}"
SOURCE_MANIFEST="${5:?请输入 source manifest 路径}"

# 所有受支持模型统一按 1M 上下文规划。500k 用于源码输入，余量留给系统提示、工具调用和报告输出。
CONTEXT_WINDOW_TOKENS=1000000
CONTEXT_SCALE=5
BATCH_TOKEN_BUDGET="${CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET:-500000}"
LINE_TOKEN_ESTIMATE=3
FILE_TOKEN_OVERHEAD=500

json_escape() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'; }
sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}
branch_slug() {
  local s; s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)"
  [ -n "$s" ] || s="no-branch"; printf '%s' "$s"
}
sum_field() { awk -F '\t' -v f="$2" '{s+=$f} END{print s+0}' "$1"; }

# 语言中性的风险优先级：路由/页面/组件入口优先
risk_priority() {
  case "$1" in
    *route*|*Router*|*Page*|*App.tsx|*App.jsx|*index.tsx|*main.tsx) echo 0 ;;
    *Service*|*api*|*hook*|*Hook*|*store*|*Store*) echo 1 ;;
    *) echo 2 ;;
  esac
}

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
RUN_ID="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"
RUNS_ROOT="${CC_CODE_REVIEWER_RUNS_ROOT:-$PROJECT_DIR/.cc-code-reviewer/runs}"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
FILES_TSV="$RUN_DIR/review-units.tsv"; SORTED="$RUN_DIR/review-units.sorted.tsv"
PLAN_ROWS="$RUN_DIR/batch-plan.tsv"; BIN_ROWS="$RUN_DIR/batch-bins.tsv"
UNITS_JSON="$RUN_DIR/review-units.json"; UNIT_MEMBERS="$RUN_DIR/review-unit-members.tsv"; UNIT_FILES_DIR="$RUN_DIR/.review-units"; RULES_RESOLVED="$RUN_DIR/review-rules.json"
# 语义亲和分组（可选输入）：unit -> group_key 的中间映射；未启用时保持空文件。
UNIT_GROUPS="$RUN_DIR/.unit-groups.tsv"
# 同批次已含的组键登记表（每行一个组键；组键不含 TAB/换行，可整行精确匹配）。
BIN_GROUP_DIR="$RUN_DIR/.bin-groups"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results" "$UNIT_FILES_DIR" "$BIN_GROUP_DIR"
: > "$FILES_TSV"; : > "$PLAN_ROWS"; : > "$BIN_ROWS"; : > "$UNIT_GROUPS"

# Full/scoped file-batch runs always have a frozen input. Incremental callers
# may pass their already-created input through the environment instead.
if [ -z "${CC_CODE_REVIEWER_REVIEW_INPUT_PATH:-}" ]; then
  bash "$(cd "$(dirname "$0")" && pwd)/prepare-review-input.sh" \
    "$PROJECT_DIR" "$LANGUAGE_ID" full 0 "$SOURCE_MANIFEST" "$RUN_DIR/review-input.json" >/dev/null
  CC_CODE_REVIEWER_REVIEW_INPUT_PATH="$RUN_DIR/review-input.json"
fi

# P1: keep only high-confidence direct import relationships together.  The
# unit planner never invents framework semantics and preserves singleton files.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/plan-review-units.sh" "$PROJECT_DIR" "$LANGUAGE_ID" "$SOURCE_MANIFEST" "$UNITS_JSON" >/dev/null
bash "$SCRIPT_DIR/resolve-review-rules.sh" "$PROJECT_DIR" "$SOURCE_MANIFEST" "$RULES_RESOLVED" "${CC_CODE_REVIEWER_REVIEW_RULES_PATH:-$PROJECT_DIR/.cc-code-reviewer/review-rules.yml}" >/dev/null
# 恢复准入门禁快照（resume admission gate）：规则解析产物一落盘立即记录其 sha256，
# 供 scripts/core/validate-resume-input.sh 在恢复旧 RUN_DIR 前复核冻结文件未被改动。
RULES_SNAPSHOT_SHA256="$(sha256_file "$RULES_RESOLVED")"
perl -MJSON::PP -e '
  local $/; my $d=decode_json(<>); for my $u (@{$d->{units}}) { for my $f (@{$u->{files}}) { print "$u->{unit_id}\t$f\n"; } }
' "$UNITS_JSON" > "$UNIT_MEMBERS"

# 语义亲和分组输入：CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE 指向 TSV（<group_key>\t<file_path>）。
# 相对路径一律先按 PROJECT_DIR 解析，再与 review units 的 abs_path 归一化结果对齐。
# 缺失/不可读/零命中时整体退化为未启用（fail-open）；畸形行仅计数并在 stderr 提示一次。
SEMANTIC_GROUPING_ENABLED=0
SEMANTIC_GROUPS_PATH=""
SEMANTIC_GROUPS_SKIPPED=0
if [ -n "${CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE:-}" ]; then
  GROUPS_STATS="$(perl -MFile::Spec -MCwd=abs_path -e '
    use strict; use warnings;
    my ($src,$project,$members,$out)=@ARGV;
    my $gp = File::Spec->file_name_is_absolute($src) ? $src : File::Spec->rel2abs($src,$project);
    my $open_ok = open my $gf,"<",$gp;
    my %map; my $skipped=0;
    if ($open_ok) {
      $gp = abs_path($gp) || $gp;
      while (my $line=<$gf>) {
        chomp $line; $line =~ s/\r$//;
        next if $line eq "" || $line =~ /^#/;
        my @f=split /\t/,$line,-1;
        if (@f != 2 || $f[0] eq "" || $f[1] eq "") { $skipped++; next; }
        my ($key,$path)=@f;
        my $abs = File::Spec->file_name_is_absolute($path) ? $path : File::Spec->rel2abs($path,$project);
        my $resolved = abs_path($abs);
        if (!defined $resolved || !-e $resolved) { $skipped++; next; }
        $map{$resolved} = $key unless exists $map{$resolved};
      }
      close $gf;
    }
    my (%unit_group,%matched);
    if (open my $mf,"<",$members) {
      while (my $line=<$mf>) {
        chomp $line; next if $line eq "";
        my ($unit,$file)=split /\t/,$line,2;
        next unless defined $file && $file ne "";
        my $g=$map{$file};
        next unless defined $g;
        $matched{$file}=1;
        $unit_group{$unit}=$g if !defined $unit_group{$unit} || $g lt $unit_group{$unit};
      }
      close $mf;
    }
    if (open my $of,">",$out) {
      print $of "$_\t$unit_group{$_}\n" for sort keys %unit_group;
      close $of;
    }
    printf "ENABLED=%d\nSKIPPED=%d\nPATH=%s\n", ((scalar keys %matched)>=1?1:0), $skipped, $gp;
  ' "${CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE}" "$PROJECT_DIR" "$UNIT_MEMBERS" "$UNIT_GROUPS")"
  SEMANTIC_GROUPS_SKIPPED="$(printf '%s\n' "$GROUPS_STATS" | sed -n 's/^SKIPPED=//p')"
  if [ "$(printf '%s\n' "$GROUPS_STATS" | sed -n 's/^ENABLED=//p')" = "1" ]; then
    SEMANTIC_GROUPING_ENABLED=1
    SEMANTIC_GROUPS_PATH="$(printf '%s\n' "$GROUPS_STATS" | sed -n 's/^PATH=//p')"
  fi
  if [ "${SEMANTIC_GROUPS_SKIPPED:-0}" -gt 0 ] 2>/dev/null; then
    echo "SEMANTIC_GROUPS_SKIPPED_LINES=$SEMANTIC_GROUPS_SKIPPED" >&2
  fi
fi

while IFS="$(printf '\t')" read -r unit file; do
  [ -n "$unit" ] && [ -n "$file" ] || continue
  loc="$(wc -l < "$file" | tr -d ' ')"
  cost=$((loc * LINE_TOKEN_ESTIMATE + FILE_TOKEN_OVERHEAD))
  printf '%s\t%s\t%s\t%s\n' "$unit" "$cost" "$loc" "$file" >> "$UNIT_FILES_DIR/$unit"
done < "$UNIT_MEMBERS"

for unit_file in "$UNIT_FILES_DIR"/*; do
  [ -f "$unit_file" ] || continue
  unit="$(basename "$unit_file")"
  unit_cost="$(awk -F '\t' '{s+=$2} END{print s+0}' "$unit_file")"
  unit_loc="$(awk -F '\t' '{s+=$3} END{print s+0}' "$unit_file")"
  unit_priority="$(awk -F '\t' '
    function p(path) { n=split(path,a,"/"); f=a[n]; return (f ~ /route|Router|Page|App\\.(tsx|jsx)|index\\.(tsx|jsx)|main\\.(tsx|jsx)/ ? 0 : (f ~ /Service|api|hook|Hook|store|Store/ ? 1 : 2)); }
    { x=p($4); if (NR==1 || x<m) m=x } END { print m+0 }
  ' "$unit_file")"
  printf '%s\t%s\t%s\t%s\n' "$unit_priority" "$unit_cost" "$unit_loc" "$unit" >> "$FILES_TSV"
done

if [ ! -s "$FILES_TSV" ]; then
  echo "NO_SOURCE_FILES=$PROJECT_DIR" >&2
  exit 1
fi

# 追加第 5 列 group_key（未启用时恒为空串）。空常量键不改变任何两行之间的相对顺序，
# 因此 -k5,5 在未启用时与旧的两键排序（-k1,1n -k2,2rn）逐字节等价。
awk -F '\t' -v OFS='\t' '
  FILENAME==ARGV[1] { if ($1 != "") g[$1]=$2; next }
  { print $1,$2,$3,$4,($4 in g?g[$4]:"") }
' "$UNIT_GROUPS" "$FILES_TSV" > "$FILES_TSV.tmp"
mv "$FILES_TSV.tmp" "$FILES_TSV"

sort -t "$(printf '\t')" -k1,1n -k5,5 -k2,2rn "$FILES_TSV" > "$SORTED"
TOTAL_LOC="$(sum_field "$FILES_TSV" 3)"
TOTAL_FILES="$(awk 'END{print NR+0}' "$UNIT_MEMBERS")"

BATCH_COUNT=0

# First-Fit Decreasing：输入已按风险优先级、组键、成本降序排列；小文件会回填到首个可容纳的已有批次。
# 组感知规则：同组单元优先进入“已含同组键且预算仍放得下”的最早批次；找不到才回退普通 first-fit，
# 预算硬限制永远优先于亲和（放不下就开新批次），未分组单元与旧行为完全一致。
while IFS="$(printf '\t')" read -r pri cost loc unit group; do
  [ -n "$unit" ] || continue
  assigned_id=""
  assigned_draft=""
  assigned_cost=0
  if [ -n "$group" ]; then
    while IFS="$(printf '\t')" read -r bin_id bin_cost bin_draft; do
      [ -n "$bin_id" ] || continue
      [ $((bin_cost + cost)) -le "$BATCH_TOKEN_BUDGET" ] || continue
      if [ -f "$BIN_GROUP_DIR/$bin_id" ] && grep -Fxq -- "$group" "$BIN_GROUP_DIR/$bin_id"; then
        assigned_id="$bin_id"
        assigned_draft="$bin_draft"
        assigned_cost=$((bin_cost + cost))
        break
      fi
    done < "$BIN_ROWS"
  fi

  if [ -z "$assigned_id" ]; then
    while IFS="$(printf '\t')" read -r bin_id bin_cost bin_draft; do
      [ -n "$bin_id" ] || continue
      if [ $((bin_cost + cost)) -le "$BATCH_TOKEN_BUDGET" ]; then
        assigned_id="$bin_id"
        assigned_draft="$bin_draft"
        assigned_cost=$((bin_cost + cost))
        break
      fi
    done < "$BIN_ROWS"
  fi

  if [ -z "$assigned_id" ]; then
    BATCH_COUNT=$((BATCH_COUNT + 1))
    assigned_id="$(printf 'batch-%03d' "$BATCH_COUNT")"
    assigned_draft="$RUN_DIR/$assigned_id.tsv"
    assigned_cost="$cost"
    : > "$assigned_draft"
    printf '%s\t%s\t%s\n' "$assigned_id" "$assigned_cost" "$assigned_draft" >> "$BIN_ROWS"
  else
    awk -F '\t' -v OFS='\t' -v target="$assigned_id" -v new_cost="$assigned_cost" '
      $1 == target { $2 = new_cost }
      { print }
    ' "$BIN_ROWS" > "$BIN_ROWS.tmp"
    mv "$BIN_ROWS.tmp" "$BIN_ROWS"
  fi
  if [ -n "$group" ]; then
    bg="$BIN_GROUP_DIR/$assigned_id"
    if [ ! -f "$bg" ] || ! grep -Fxq -- "$group" "$bg"; then
      printf '%s\n' "$group" >> "$bg"
    fi
  fi
  while IFS="$(printf '\t')" read -r _ member_cost member_loc member_file; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$pri" "$member_cost" "$member_loc" "$member_file" "$unit" >> "$assigned_draft"
  done < "$UNIT_FILES_DIR/$unit"
done < "$SORTED"

while IFS="$(printf '\t')" read -r id _ draft; do
  [ -n "$id" ] || continue
  bf="$RUN_DIR/batches/$id.files"; bj="$RUN_DIR/batches/$id.json"
  loc="$(sum_field "$draft" 3)"; files="$(awk 'END{print NR+0}' "$draft")"; cost="$(sum_field "$draft" 2)"
  awk -F '\t' '{print $4}' "$draft" > "$bf"
  # 仅在语义分组启用时披露批次内的组键（去重排序）；保持旧输出可逐字节比较。
  batch_group_field=""
  if [ "$SEMANTIC_GROUPING_ENABLED" = "1" ] && [ -s "$BIN_GROUP_DIR/$id" ]; then
    batch_group_field="$(printf '  "semantic_group_ids": %s,\n' \
      "$(perl -MJSON::PP -e 'my %s; while (<>) { chomp; $s{$_}=1 if $_ ne ""; } print JSON::PP->new->canonical->encode([sort keys %s])' "$BIN_GROUP_DIR/$id")")"
  fi
  cat > "$bj.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "batch_id": "$id",
  "strategy": "file-token-batching",
  "language_id": "$(json_escape "$LANGUAGE_ID")",
  "planned_source_loc": $loc,
  "planned_source_file_count": $files,
  "planned_review_cost": $cost,
  "review_units": $(perl -MJSON::PP -e 'my %s; while (<>) { chomp; my @f=split /\t/; $s{$f[4]}=1 if $f[4]; } print JSON::PP->new->canonical->encode([sort keys %s])' "$draft"),
${batch_group_field}  "batch_file_list": "$(json_escape "$bf")"
}
JSON
  mv "$bj.tmp" "$bj"
  printf '%s\t%s\t%s\t%s\n' "$id" "$loc" "$files" "$cost" >> "$PLAN_ROWS"
done < "$BIN_ROWS"

REVIEW_INPUT_SHA256=""
if [ -n "${CC_CODE_REVIEWER_REVIEW_INPUT_PATH:-}" ]; then
  [ -r "$CC_CODE_REVIEWER_REVIEW_INPUT_PATH" ] || { echo "REVIEW_INPUT_NOT_READABLE=$CC_CODE_REVIEWER_REVIEW_INPUT_PATH" >&2; exit 1; }
  if [ "$CC_CODE_REVIEWER_REVIEW_INPUT_PATH" != "$RUN_DIR/review-input.json" ]; then
    cp "$CC_CODE_REVIEWER_REVIEW_INPUT_PATH" "$RUN_DIR/review-input.json"
  fi
  REVIEW_INPUT_SHA256="$(sha256_file "$RUN_DIR/review-input.json")"
fi

CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# plan.json 仅在语义分组实际启用时披露新字段；省略时保持旧 plan.json 逐字节可比。
plan_semantic_fields=""
if [ "$SEMANTIC_GROUPING_ENABLED" = "1" ]; then
  plan_semantic_fields="$(printf '\n  "semantic_grouping_enabled": true,\n  "semantic_groups_path": "%s",' "$(json_escape "$SEMANTIC_GROUPS_PATH")")"
fi
cat > "$RUN_DIR/plan.json.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "project_name": "$(json_escape "$PROJECT_NAME")",
  "project_dir": "$(json_escape "$PROJECT_DIR")",
  "review_mode": "$(json_escape "$REVIEW_MODE")",
  "branch": "$(json_escape "$BRANCH_NAME")",
  "language_id": "$(json_escape "$LANGUAGE_ID")",
  "strategy": "file-token-batching",
  "association_enabled": true,${plan_semantic_fields}
  "review_units_path": "$(json_escape "$UNITS_JSON")",
  "review_rules_resolved_path": "$(json_escape "$RULES_RESOLVED")",
  "review_input_path": "$(json_escape "$RUN_DIR/review-input.json")",
  "review_input_sha256": "$(json_escape "$REVIEW_INPUT_SHA256")",
  "rules_snapshot_sha256": "$(json_escape "$RULES_SNAPSHOT_SHA256")",
  "total_source_loc": $TOTAL_LOC,
  "total_source_file_count": $TOTAL_FILES,
  "batch_count": $BATCH_COUNT,
  "budget": { "batch_token_budget": $BATCH_TOKEN_BUDGET, "target_batch_cost": $BATCH_TOKEN_BUDGET, "line_token_estimate": $LINE_TOKEN_ESTIMATE, "file_token_overhead": $FILE_TOKEN_OVERHEAD, "context_scale": $CONTEXT_SCALE, "context_window_tokens": $CONTEXT_WINDOW_TOKENS },
  "created_at": "$CREATED"
}
JSON
mv "$RUN_DIR/plan.json.tmp" "$RUN_DIR/plan.json"
perl -MJSON::PP -0777 -e 'local $/; decode_json(<>);' "$RUN_DIR/plan.json" >/dev/null

rm -f "$FILES_TSV" "$SORTED" "$BIN_ROWS" "$UNIT_MEMBERS" "$UNIT_GROUPS" "$RUN_DIR"/batch-*.tsv
rm -rf "$UNIT_FILES_DIR" "$BIN_GROUP_DIR"

echo "RUN_ID=$RUN_ID"
echo "RUN_DIR=$RUN_DIR"
echo "BATCH_COUNT=$BATCH_COUNT"
echo "TOTAL_SOURCE_LOC=$TOTAL_LOC"
echo "TOTAL_SOURCE_FILE_COUNT=$TOTAL_FILES"
echo "BATCH_FILE_LIST_DIR=$RUN_DIR/batches"
exit 0
