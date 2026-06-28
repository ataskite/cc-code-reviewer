#!/bin/bash
# Java 文件级分批（瘦身为 core/plan-file-batches.sh 的 Java 适配层）
#
# 保留 Java 专属逻辑：src/main/java 文件发现 + Java risk_priority（Controller/Service 优先）。
# 分批算法委托语言中立的 core/plan-file-batches.sh，传 LANGUAGE_ID=java + manifest。
# 输出层把 core 的 source_* 字段名重映射为 Java 习惯的 java_* 字段名 + 简要分批计划，
# 保持与历史调用方（SKILL.md、旧测试）的输出契约逐字节一致。
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

CONTEXT_SCALE="${CC_REVIEW_CONTEXT_SCALE:-1}"
[ "$CONTEXT_SCALE" -lt 1 ] 2>/dev/null && CONTEXT_SCALE=1
[ "$CONTEXT_SCALE" -gt 10 ] && CONTEXT_SCALE=10
BATCH_TOKEN_BUDGET="${CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET:-$((100000 * CONTEXT_SCALE))}"
LINE_TOKEN_ESTIMATE=3
FILE_TOKEN_OVERHEAD=500

# Java 专属风险优先级（Controller/Service/Security 优先）
java_risk_priority() {
  case "$1" in
    *Controller.java|*Service.java|*Security*.java|*Filter.java|*Interceptor.java) echo 0 ;;
    *Client.java|*Pool.java|*Scheduler.java|*Handler.java|*Consumer.java|*Producer.java) echo 1 ;;
    *) echo 2 ;;
  esac
}

json_escape() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'; }
format_number() {
  local value="${1:-0}"; [ -z "$value" ] && value=0
  perl -e 'my $n=shift; $n=0 if !defined($n)||$n eq ""; 1 while $n=~s/^(-?\d+)(\d{3})/$1,$2/; print $n' "$value"
}

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
RUN_TIMESTAMP="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"

# 1. Java 文件发现 + 排序（Java 专属 risk_priority）
WORK_DIR="$(mktemp -d)"
FILES_TSV="$WORK_DIR/java-files.tsv"; SORTED_TSV="$WORK_DIR/java-files.sorted.tsv"
: > "$FILES_TSV"
while IFS= read -r -d '' file; do
  rel_path="${file#$PROJECT_DIR/}"
  file_name="${file##*/}"
  loc="$(wc -l < "$file" | tr -d ' ')"
  cost=$((loc * LINE_TOKEN_ESTIMATE + FILE_TOKEN_OVERHEAD))
  priority="$(java_risk_priority "$file_name")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$priority" "$cost" "$loc" "$rel_path" "$file" >> "$FILES_TSV"
done < <(find "$PROJECT_DIR" -path '*/src/main/java/*' -name '*.java' -not -path '*/target/*' -not -path '*/build/*' -not -path '*/.git/*' -print0 2>/dev/null)

if [ ! -s "$FILES_TSV" ]; then
  echo "NO_JAVA_FILES=$PROJECT_DIR" >&2
  rm -rf "$WORK_DIR"
  exit 1
fi

sort -t "$(printf '\t')" -k1,1n -k2,2rn -k4,4 "$FILES_TSV" > "$SORTED_TSV"

# 2. 把已排序文件清单（绝对路径，逐行）交给 core/plan-file-batches.sh
#    core 版本会重新算 loc/cost（与本处一致），产出 source_* 字段 plan.json + batches。
MANIFEST="$WORK_DIR/source-manifest.txt"
awk -F '\t' '{print $5}' "$SORTED_TSV" > "$MANIFEST"

CORE_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP="$RUN_TIMESTAMP" \
  bash "$SCRIPT_DIR/core/plan-file-batches.sh" "$PROJECT_DIR" "$REVIEW_MODE" "$BRANCH_NAME" "java" "$MANIFEST")"
CORE_RC=$?
if [ "$CORE_RC" -ne 0 ]; then
  rm -rf "$WORK_DIR"
  exit "$CORE_RC"
fi

RUN_DIR="$(printf '%s\n' "$CORE_OUT" | sed -n 's/^RUN_DIR=//p')"
BATCH_COUNT="$(printf '%s\n' "$CORE_OUT" | sed -n 's/^BATCH_COUNT=//p')"

# 3. 把 core 输出的 source_* 字段重映射为 java_*（保持历史契约）
#    并补写「简要分批计划」摘要块。
sum_field() { awk -F '\t' -v f="$2" '{s+=$f} END{print s+0}' "$1"; }
TOTAL_JAVA_LOC="$(sum_field "$FILES_TSV" 3)"
TOTAL_JAVA_FILE_COUNT="$(awk 'END{print NR+0}' "$FILES_TSV")"

# 用正则就近插入 java_* 别名字段（保持 core 原多行缩进格式，不重排字段、不改空格），
# 兼容旧 phase12 调用方与 java_* 字段断言。source_* 字段保留不动。
perl -i -pe '
  if (/"total_source_loc":\s*(\d+)/) {
    my $v = $1;
    s/("total_source_loc":\s*$v,)/$1\n  "total_java_loc": $v,/;
  }
  if (/"total_source_file_count":\s*(\d+)/) {
    my $v = $1;
    s/("total_source_file_count":\s*$v,)/$1\n  "total_java_file_count": $v,/;
  }
' "$RUN_DIR/plan.json" 2>/dev/null || true
for bj in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$bj" ] || continue
  perl -i -pe '
    if (/"planned_source_loc":\s*(\d+)/) {
      my $v = $1;
      s/("planned_source_loc":\s*$v,)/$1\n  "planned_java_loc": $v,/;
    }
    if (/"planned_source_file_count":\s*(\d+)/) {
      my $v = $1;
      s/("planned_source_file_count":\s*$v,)/$1\n  "planned_java_file_count": $v,/;
    }
  ' "$bj" 2>/dev/null || true
done

# 4. 产出 Java 习惯的 stdout（与历史契约一致）
branch_slug() {
  local slug
  slug="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40)"
  [ -n "$slug" ] || slug="no-branch"
  printf '%s' "$slug"
}
RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"
echo "RUN_ID=$RUN_ID"
echo "RUN_DIR=$RUN_DIR"
echo "BATCH_COUNT=$BATCH_COUNT"
echo "TOTAL_JAVA_LOC=$TOTAL_JAVA_LOC"
echo "TOTAL_JAVA_FILE_COUNT=$TOTAL_JAVA_FILE_COUNT"
echo "BATCH_FILE_LIST_DIR=$RUN_DIR/batches"
echo
echo "简要分批计划"
echo "批次 行数 文件 重点范围"
for bj in "$RUN_DIR"/batches/batch-*.json; do
  [ -f "$bj" ] || continue
  b_id="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{batch_id}//""' "$bj")"
  b_loc="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{planned_java_loc}//$d->{planned_source_loc}//0' "$bj")"
  b_files="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{planned_java_file_count}//$d->{planned_source_file_count}//0' "$bj")"
  # 摘要：取该批次前 2 个文件名，>2 个时追加「，等 N 个文件」
  bfl="$RUN_DIR/batches/$b_id.files"
  if [ -f "$bfl" ]; then
    summary="$(perl -CS -Mutf8 -e '
      binmode STDOUT, ":utf8";
      my ($file) = @ARGV;
      open my $fh, "<", $file or die;
      my @names; my $total = 0;
      while (my $line = <$fh>) { chomp $line; next if $line eq ""; $total++; push @names, (split m{/}, $line)[-1] if @names < 2; }
      close $fh;
      my $s = join(",", @names);
      $s .= "，等 $total 个文件" if $total > 2;
      print $s;
    ' "$bfl")"
  else
    summary=""
  fi
  printf '%s %s %s %s\n' "$b_id" "$(format_number "$b_loc")" "$(format_number "$b_files")" "$summary"
done

rm -rf "$WORK_DIR"
