#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-plan.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src"
for i in 1 2 3 4 5; do
  { printf 'export const X%d: number = 0;\n' "$i"; seq 1 9000 | sed 's/.*/export const y& = 0;/'; } > "$D/src/m${i}.ts"
done
D="$(cd "$D" && pwd -P)"

MANIFEST="$(mktemp)"
find "$D/src" -name '*.ts' -print | sort > "$MANIFEST"

OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-010000 \
       bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "frontend" "$MANIFEST")"

RUN_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
grep -q "RUN_ID=" <<< "$OUT"
grep -q "BATCH_COUNT=" <<< "$OUT"
grep -q "TOTAL_SOURCE_FILE_COUNT=5" <<< "$OUT"
grep -q "TOTAL_SOURCE_LOC=" <<< "$OUT"
grep -q "BATCH_FILE_LIST_DIR=" <<< "$OUT"
grep -q '"language_id": "frontend"' "$RUN_DIR/plan.json"
grep -q '"strategy": "file-token-batching"' "$RUN_DIR/plan.json"
grep -q '"schema_version": 1' "$RUN_DIR/plan.json"
grep -q '"batch_token_budget": 500000' "$RUN_DIR/plan.json"
grep -q '"context_scale": 5' "$RUN_DIR/plan.json"
grep -q '"context_window_tokens": 1000000' "$RUN_DIR/plan.json"
test -f "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_loc"' "$RUN_DIR/batches/batch-001.json"
grep -q '"planned_source_file_count"' "$RUN_DIR/batches/batch-001.json"
grep -q '"batch_file_list"' "$RUN_DIR/batches/batch-001.json"

SCALE_D="$TMP_DIR/large-app"; mkdir -p "$SCALE_D/src"
for i in $(seq -w 1 88); do
  seq 1 10000 | sed 's/.*/export const x = 1;/' > "$SCALE_D/src/file${i}.ts"
done
SCALE_D="$(cd "$SCALE_D" && pwd -P)"
SCALE_MANIFEST="$(mktemp)"
find "$SCALE_D/src" -name '*.ts' -print | sort > "$SCALE_MANIFEST"

SCALE_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-020000 \
             CC_REVIEW_CONTEXT_SCALE=1 \
             bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$SCALE_D" "standard" "main" "frontend" "$SCALE_MANIFEST")"
SCALE_RUN_DIR="$(printf '%s\n' "$SCALE_OUT" | sed -n 's/^RUN_DIR=//p')"
SCALE_BATCH_COUNT="$(printf '%s\n' "$SCALE_OUT" | sed -n 's/^BATCH_COUNT=//p')"
test "$SCALE_BATCH_COUNT" -eq 6
perl -MJSON::PP -e '
  open my $fh, "<", $ARGV[0] or die $!;
  local $/;
  my $d = decode_json(<$fh>);
  my $b = $d->{budget} || {};
  die "bad batch_token_budget\n" unless ($b->{batch_token_budget} // 0) == 500000;
  die "missing context_scale\n" unless ($b->{context_scale} // 0) == 5;
  die "missing context_window_tokens\n" unless ($b->{context_window_tokens} // 0) == 1000000;
' "$SCALE_RUN_DIR/plan.json"
STATUS_OUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$SCALE_D")"
grep -q "上下文窗口: 1000000 tokens" <<< "$STATUS_OUT"

# 大小不均文件应使用 First-Fit Decreasing 回填已有批次：旧 Next-Fit 会产生 3 批，新算法应为 2 批。
FFD_D="$TMP_DIR/ffd-app"; mkdir -p "$FFD_D/src"
for spec in "large-a:1833" "large-b:1833" "small-a:1167" "small-b:1167"; do
  name="${spec%%:*}"; lines="${spec##*:}"
  seq 1 "$lines" | sed 's/.*/export const value = 1;/' > "$FFD_D/src/$name.ts"
done
FFD_D="$(cd "$FFD_D" && pwd -P)"
FFD_MANIFEST="$(mktemp)"
find "$FFD_D/src" -name '*.ts' -print | sort > "$FFD_MANIFEST"
FFD_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-030000 \
           CC_REVIEW_CONTEXT_SCALE=1 \
           CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=10000 \
           bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$FFD_D" "standard" "main" "frontend" "$FFD_MANIFEST")"
FFD_RUN_DIR="$(printf '%s\n' "$FFD_OUT" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$FFD_OUT" | sed -n 's/^BATCH_COUNT=//p')" -eq 2
test "$(cat "$FFD_RUN_DIR"/batches/*.files | sort | uniq | wc -l | tr -d ' ')" -eq 4
test "$(cat "$FFD_RUN_DIR"/batches/*.files | wc -l | tr -d ' ')" -eq 4
grep -q '"batch_token_budget": 10000' "$FFD_RUN_DIR/plan.json"
grep -q '"context_scale": 5' "$FFD_RUN_DIR/plan.json"

# 语义亲和分组的公共断言辅助：打印同时包含两个文件的批次清单路径（0..N 行，恒返回 0）。
aff_batches_with_both() {
  local run_dir="$1" file_a="$2" file_b="$3" f
  for f in "$run_dir"/batches/*.files; do
    [ -f "$f" ] || continue
    if grep -Fxq "$file_a" "$f" && grep -Fxq "$file_b" "$f"; then printf '%s\n' "$f"; fi
  done
}

# 负向断言：set -e 会忽略 `! cmd` 的失败返回值（返回值被 ! 反转时 errexit 不生效），
# 因此“不得出现某内容”必须显式判失败并 exit。
assert_absent() { # pattern file...
  if grep -Rq -- "$1" "${@:2}"; then
    echo "FAIL: unexpected content \"$1\" in: ${*:2}" >&2
    exit 1
  fi
}

# 用例 S1（向后兼容 / 零命中 fail-open）：同一 fixture 跑两次 —— 一次不设
# CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE，一次设一个只引用清单外路径（零命中）的 groups 文件。
# 两次运行都不得出现 semantic_* 字段、批次成员逐批一致；归一化（替换 run 时间戳、
# 去掉 created_at / review_input_sha256）后 plan.json 与 batch json 逐字节一致，
# 证明空组键排序与旧两键排序等价、零命中时输出与旧格式可比。
BC_D="$TMP_DIR/bytecompat-app"; mkdir -p "$BC_D/src" "$BC_D/notes"
for spec in "p1:1000" "p2:900" "p3:800" "p4:700"; do
  name="${spec%%:*}"; lines="${spec##*:}"
  seq 1 "$lines" | sed 's/.*/export const v = 1;/' > "$BC_D/src/$name.ts"
done
echo "outside review scope" > "$BC_D/notes/external.txt"
BC_D="$(cd "$BC_D" && pwd -P)"
BC_MANIFEST="$(mktemp)"
find "$BC_D/src" -name '*.ts' -print | sort > "$BC_MANIFEST"
BC_GROUPS="$TMP_DIR/bytecompat-groups.tsv"
printf 'other\t%s\n' "$BC_D/notes/external.txt" > "$BC_GROUPS"
BC_OUT_A="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-040000 \
            CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=6000 \
            bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$BC_D" "standard" "main" "frontend" "$BC_MANIFEST" \
            2>"$TMP_DIR/bytecompat-a.err")"
BC_OUT_B="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-040001 \
            CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=6000 \
            CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE="$BC_GROUPS" \
            bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$BC_D" "standard" "main" "frontend" "$BC_MANIFEST" \
            2>"$TMP_DIR/bytecompat-b.err")"
BC_RUN_A="$(printf '%s\n' "$BC_OUT_A" | sed -n 's/^RUN_DIR=//p')"
BC_RUN_B="$(printf '%s\n' "$BC_OUT_B" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$BC_OUT_A" | sed -n 's/^BATCH_COUNT=//p')" -eq 3
test "$(printf '%s\n' "$BC_OUT_B" | sed -n 's/^BATCH_COUNT=//p')" -eq 3
assert_absent 'semantic_grouping_enabled' "$BC_RUN_A/plan.json"
assert_absent 'semantic_groups_path' "$BC_RUN_A/plan.json"
assert_absent 'semantic_grouping_enabled' "$BC_RUN_B/plan.json"
assert_absent 'semantic_groups_path' "$BC_RUN_B/plan.json"
assert_absent 'semantic_group_ids' "$BC_RUN_A/batches"
assert_absent 'semantic_group_ids' "$BC_RUN_B/batches"
# 零命中但无畸形行：不得出现 skipped-lines 告警。
assert_absent 'SEMANTIC_GROUPS_SKIPPED_LINES' "$TMP_DIR/bytecompat-b.err"
for i in 001 002 003; do
  diff "$BC_RUN_A/batches/batch-$i.files" "$BC_RUN_B/batches/batch-$i.files" >/dev/null
done
bc_norm() { sed -e 's/20260826-04000[01]/BCRUNTS/g' -e '/"created_at"/d' -e '/"review_input_sha256"/d' "$1"; }
bc_norm "$BC_RUN_A/plan.json" > "$TMP_DIR/bytecompat-plan-a.json"
bc_norm "$BC_RUN_B/plan.json" > "$TMP_DIR/bytecompat-plan-b.json"
diff "$TMP_DIR/bytecompat-plan-a.json" "$TMP_DIR/bytecompat-plan-b.json" >/dev/null
for i in 001 002 003; do
  bc_norm "$BC_RUN_A/batches/batch-$i.json" > "$TMP_DIR/bytecompat-batch-a.json"
  bc_norm "$BC_RUN_B/batches/batch-$i.json" > "$TMP_DIR/bytecompat-batch-b.json"
  diff "$TMP_DIR/bytecompat-batch-a.json" "$TMP_DIR/bytecompat-batch-b.json" >/dev/null
done

# 用例 S2（亲和改变装箱结果）：loc=2100/2000/1900/1800 → cost(loc*3+500)=6800/6500/6200/5900，
# 预算 14000，aff-a+aff-b=grp-1、aff-c+aff-d=grp-2。
#   无分组：成本降序 aff-a(6800)→aff-c(6500)→aff-b(6200)→aff-d(5900)；aff-a+aff-c=13300 ≤ 14000
#     同进 batch-001，aff-b/aff-d 只能组成 batch-002(12100) → 两个配对都被拆散。
#   有分组：排序先按组键（grp-1 < grp-2），aff-a/aff-b 相邻；group-aware first-fit 令
#     aff-a+aff-b=13000 ≤ 14000 同批、aff-c+aff-d=12400 ≤ 14000 同批，
#     而 13000+6500=19500 与 13300+5900=19200 均超预算不会互串。
AFF_D="$TMP_DIR/affinity-app"; mkdir -p "$AFF_D/src"
for spec in "aff-a:2100" "aff-b:1900" "aff-c:2000" "aff-d:1800"; do
  name="${spec%%:*}"; lines="${spec##*:}"
  seq 1 "$lines" | sed 's/.*/export const v = 1;/' > "$AFF_D/src/$name.ts"
done
AFF_D="$(cd "$AFF_D" && pwd -P)"
AFF_MANIFEST="$(mktemp)"
find "$AFF_D/src" -name '*.ts' -print | sort > "$AFF_MANIFEST"
AFF_GROUPS="$TMP_DIR/affinity-groups.tsv"
{
  printf 'grp-1\t%s\n' "$AFF_D/src/aff-a.ts"
  printf 'grp-1\t%s\n' "$AFF_D/src/aff-b.ts"
  printf 'grp-2\t%s\n' "$AFF_D/src/aff-c.ts"
  printf 'grp-2\t%s\n' "$AFF_D/src/aff-d.ts"
} > "$AFF_GROUPS"
AFF_OUT_NG="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-040100 \
              CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=14000 \
              bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$AFF_D" "standard" "main" "frontend" "$AFF_MANIFEST")"
AFF_RUN_NG="$(printf '%s\n' "$AFF_OUT_NG" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$AFF_OUT_NG" | sed -n 's/^BATCH_COUNT=//p')" -eq 2
# 无分组基线：两个配对都必须至少拆散（否则亲和用例没有对照意义）。
test "$(aff_batches_with_both "$AFF_RUN_NG" "$AFF_D/src/aff-a.ts" "$AFF_D/src/aff-b.ts" | wc -l | tr -d ' ')" -eq 0
test "$(aff_batches_with_both "$AFF_RUN_NG" "$AFF_D/src/aff-c.ts" "$AFF_D/src/aff-d.ts" | wc -l | tr -d ' ')" -eq 0
AFF_OUT_G="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-040101 \
             CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=14000 \
             CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE="$AFF_GROUPS" \
             bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$AFF_D" "standard" "main" "frontend" "$AFF_MANIFEST")"
AFF_RUN_G="$(printf '%s\n' "$AFF_OUT_G" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$AFF_OUT_G" | sed -n 's/^BATCH_COUNT=//p')" -eq 2
test "$(aff_batches_with_both "$AFF_RUN_G" "$AFF_D/src/aff-a.ts" "$AFF_D/src/aff-b.ts" | wc -l | tr -d ' ')" -eq 1
test "$(aff_batches_with_both "$AFF_RUN_G" "$AFF_D/src/aff-c.ts" "$AFF_D/src/aff-d.ts" | wc -l | tr -d ' ')" -eq 1
grep -q '"semantic_grouping_enabled": true' "$AFF_RUN_G/plan.json"
perl -MJSON::PP -0777 -e 'decode_json(<>);' "$AFF_RUN_G/plan.json" >/dev/null
grep -q "\"semantic_groups_path\": \".*$(basename "$AFF_GROUPS")\"" "$AFF_RUN_G/plan.json"
assert_absent 'semantic_grouping_enabled' "$AFF_RUN_NG/plan.json"
grep -Fq '"semantic_group_ids": ["grp-1"]' "$AFF_RUN_G/batches/batch-001.json"
grep -Fq '"semantic_group_ids": ["grp-2"]' "$AFF_RUN_G/batches/batch-002.json"

# 用例 S3（unit 组键继承）：widget-a.ts 通过相对 import './widget-b' 与 widget-b.ts 合并为
# 一个 review unit；groups 文件只登记 widget-b.ts（相对路径 + env 值也用相对路径）。
# 整个 unit 继承 unit-grp：两个成员必须同批（unit 原子性），且该批 json 披露组键；
# 未分组成员所在批（fill-1/fill-2，cost 11900 > 预算 12000 的一半）不得出现组键字段。
UNIT_D="$TMP_DIR/unit-app"; mkdir -p "$UNIT_D/src"
{ printf "import helper from './widget-b';\n"; seq 1 100 | sed 's/.*/export const wa = 1;/'; } > "$UNIT_D/src/widget-a.ts"
seq 1 100 | sed 's/.*/export const wb = 1;/' > "$UNIT_D/src/widget-b.ts"
seq 1 3800 | sed 's/.*/export const fill1 = 1;/' > "$UNIT_D/src/fill-1.ts"
seq 1 3800 | sed 's/.*/export const fill2 = 1;/' > "$UNIT_D/src/fill-2.ts"
UNIT_D="$(cd "$UNIT_D" && pwd -P)"
UNIT_MANIFEST="$(mktemp)"
find "$UNIT_D/src" -name '*.ts' -print | sort > "$UNIT_MANIFEST"
printf 'unit-grp\tsrc/widget-b.ts\n' > "$UNIT_D/semantic-groups.tsv"
UNIT_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-040200 \
            CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=12000 \
            CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE=semantic-groups.tsv \
            bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$UNIT_D" "standard" "main" "frontend" "$UNIT_MANIFEST")"
UNIT_RUN_DIR="$(printf '%s\n' "$UNIT_OUT" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$UNIT_OUT" | sed -n 's/^BATCH_COUNT=//p')" -eq 3
test "$(aff_batches_with_both "$UNIT_RUN_DIR" "$UNIT_D/src/widget-a.ts" "$UNIT_D/src/widget-b.ts" | wc -l | tr -d ' ')" -eq 1
grep -Fxq "$UNIT_D/src/widget-a.ts" "$UNIT_RUN_DIR/batches/batch-003.files"
grep -Fxq "$UNIT_D/src/widget-b.ts" "$UNIT_RUN_DIR/batches/batch-003.files"
grep -Fq '"semantic_group_ids": ["unit-grp"]' "$UNIT_RUN_DIR/batches/batch-003.json"
assert_absent 'semantic_group_ids' "$UNIT_RUN_DIR/batches/batch-001.json"
assert_absent 'semantic_group_ids' "$UNIT_RUN_DIR/batches/batch-002.json"
grep -q '"semantic_grouping_enabled": true' "$UNIT_RUN_DIR/plan.json"
perl -MJSON::PP -0777 -e 'decode_json(<>);' "$UNIT_RUN_DIR/plan.json" >/dev/null
grep -q "\"semantic_groups_path\": \".*semantic-groups.tsv\"" "$UNIT_RUN_DIR/plan.json"

# 用例 S4（预算硬限制优先于亲和）：pair-x/pair-y 各 loc 3800 → cost 11900，同组 grp-big，
# 合计 23800 > 预算 12000 → 必须拆到 ≥2 批且正常退出；两批 json 仍各自披露 grp-big。
BUD_D="$TMP_DIR/budget-app"; mkdir -p "$BUD_D/src"
seq 1 3800 | sed 's/.*/export const x = 1;/' > "$BUD_D/src/pair-x.ts"
seq 1 3800 | sed 's/.*/export const y = 1;/' > "$BUD_D/src/pair-y.ts"
BUD_D="$(cd "$BUD_D" && pwd -P)"
BUD_MANIFEST="$(mktemp)"
find "$BUD_D/src" -name '*.ts' -print | sort > "$BUD_MANIFEST"
BUD_GROUPS="$TMP_DIR/budget-groups.tsv"
{
  printf 'grp-big\t%s\n' "$BUD_D/src/pair-x.ts"
  printf 'grp-big\t%s\n' "$BUD_D/src/pair-y.ts"
} > "$BUD_GROUPS"
BUD_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-040300 \
           CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=12000 \
           CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE="$BUD_GROUPS" \
           bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$BUD_D" "standard" "main" "frontend" "$BUD_MANIFEST" \
           2>"$TMP_DIR/budget.err")"
BUD_RUN_DIR="$(printf '%s\n' "$BUD_OUT" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$BUD_OUT" | sed -n 's/^BATCH_COUNT=//p')" -eq 2
test "$(aff_batches_with_both "$BUD_RUN_DIR" "$BUD_D/src/pair-x.ts" "$BUD_D/src/pair-y.ts" | wc -l | tr -d ' ')" -eq 0
grep -Fq '"semantic_group_ids": ["grp-big"]' "$BUD_RUN_DIR/batches/batch-001.json"
grep -Fq '"semantic_group_ids": ["grp-big"]' "$BUD_RUN_DIR/batches/batch-002.json"
grep -q '"semantic_grouping_enabled": true' "$BUD_RUN_DIR/plan.json"
perl -MJSON::PP -0777 -e 'decode_json(<>);' "$BUD_RUN_DIR/plan.json" >/dev/null

# 用例 S5（畸形 groups 行只计数不致命）：1 列行、3 列行、不存在路径各贡献 1 条 skipped；
# `#` 注释行不计数；有效行（相对路径）仍启用分组。stderr 恰好输出 SEMANTIC_GROUPS_SKIPPED_LINES=3。
MAL_D="$TMP_DIR/malformed-app"; mkdir -p "$MAL_D/src"
seq 1 120 | sed 's/.*/export const a = 1;/' > "$MAL_D/src/m-a.ts"
seq 1 100 | sed 's/.*/export const b = 1;/' > "$MAL_D/src/m-b.ts"
MAL_D="$(cd "$MAL_D" && pwd -P)"
MAL_MANIFEST="$(mktemp)"
find "$MAL_D/src" -name '*.ts' -print | sort > "$MAL_MANIFEST"
MAL_GROUPS="$TMP_DIR/malformed-groups.tsv"
{
  printf '# 注释行不计数\n'
  printf 'malformed-no-tab\n'
  printf 'bad-cols\t%s\textra-col\n' "$MAL_D/src/m-a.ts"
  printf 'ghost\t%s\n' "$MAL_D/src/missing.ts"
  printf 'good-grp\tsrc/m-a.ts\n'
} > "$MAL_GROUPS"
MAL_OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260826-040400 \
           CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE="$MAL_GROUPS" \
           bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$MAL_D" "standard" "main" "frontend" "$MAL_MANIFEST" \
           2>"$TMP_DIR/malformed.err")"
MAL_RUN_DIR="$(printf '%s\n' "$MAL_OUT" | sed -n 's/^RUN_DIR=//p')"
test "$(printf '%s\n' "$MAL_OUT" | sed -n 's/^BATCH_COUNT=//p')" -eq 1
grep -q 'SEMANTIC_GROUPS_SKIPPED_LINES=3$' "$TMP_DIR/malformed.err"
grep -q '"semantic_grouping_enabled": true' "$MAL_RUN_DIR/plan.json"
grep -Fq '"semantic_group_ids": ["good-grp"]' "$MAL_RUN_DIR/batches/batch-001.json"

echo "PASS: core plan-file-batches"
