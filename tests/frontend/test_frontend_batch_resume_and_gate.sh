#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-gate.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/app"; mkdir -p "$D/src"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.0.0"}}
JSON
for i in 1 2 3; do seq 1 9000 | sed "s/.*/export const m&_$i = 0;/" > "$D/src/m$i.ts"; done
D="$(cd "$D" && pwd -P)"

MANIFEST="$(mktemp)"; bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D" > "$MANIFEST"
# 小预算强制多批，以便验证部分完成 → 阶段性报告（3 文件 × 1000 行 ≈ 10500 token，budget=3500 → 3 批）
POUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-030000 CC_CODE_REVIEWER_BATCH_TOKEN_BUDGET=3500 \
        bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "frontend" "$MANIFEST")"
RUN_DIR="$(printf '%s\n' "$POUT" | sed -n 's/^RUN_DIR=//p')"
BATCH_COUNT="$(printf '%s\n' "$POUT" | sed -n 's/^BATCH_COUNT=//p')"
test "$BATCH_COUNT" -ge 2

# 仅完成 batch-001，其余未完成 → 阶段性 + 覆盖率 < 100
B1="$RUN_DIR/batches/batch-001.json"
BID1="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; print decode_json(<$fh>)->{batch_id}' "$B1")"
cat > "$RUN_DIR/results/$BID1.md" <<MD
# Batch $BID1
## 发现列表
### P2 | [维度3-React规范] 重复发现
- 文件：src/m1.ts:1
- 证据：示例
- 建议：示例
MD
cat > "$RUN_DIR/results/$BID1.status.json" <<JSON
{"batch_id":"$BID1","status":"completed","planned_source_loc":9000,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/$BID1.md","finding_count":1}
JSON

MOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS="$BID1" \
        bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" || true)"
SUMM="$(printf '%s\n' "$MOUT" | sed -n 's/^SUMMARY_PATH=//p')"
REPORT="$(printf '%s\n' "$MOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"finding_count": 1' "$SUMM"
# 覆盖率必须 < 100（只纳入 1/3 批次）
COV="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; print decode_json(<$fh>)->{source_file_coverage_percent}' "$SUMM")"
test "$COV" -lt 100
head -n1 "$REPORT" | grep -q '\[阶段性\]'

# partial 批次：门禁按终态处理（等待循环不等待 partial），发现纳入合并且保持阶段性
B2="$RUN_DIR/batches/batch-002.json"
BID2="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; print decode_json(<$fh>)->{batch_id}' "$B2")"
cat > "$RUN_DIR/results/$BID2.md" <<MD
# Batch $BID2
## 发现列表
### P2 | [维度3-React规范] 部分完成发现
- 文件：src/m2.ts:2
- 证据：示例
- 建议：示例

## 覆盖情况
- 中断前已覆盖部分文件
MD
cat > "$RUN_DIR/results/$BID2.status.json" <<JSON
{"batch_id":"$BID2","status":"partial","planned_source_loc":9000,
 "planned_source_file_count":1,"result_path":"$RUN_DIR/results/$BID2.md","finding_count":1,"error":"中断"}
JSON
# MERGE_WAIT_TIMEOUT_SECONDS=0：若 partial 不算终态会立刻等待超时并阻塞 → 这里必须成功合并
PMOUT="$(MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS="$BID2" \
         bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" || true)"
PSUMM="$(printf '%s\n' "$PMOUT" | sed -n 's/^SUMMARY_PATH=//p')"
PREPORT="$(printf '%s\n' "$PMOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"merge_blocked": false' "$PSUMM"
grep -qF '"partial_batches": 1' "$PSUMM"
grep -q '"finding_count": 1' "$PSUMM"
grep -q '"covered_source_file_count": 0' "$PSUMM"
head -n1 "$PREPORT" | grep -q '\[阶段性\]'
grep -q "$BID2.*部分完成已纳入" "$PREPORT"
grep -q "中断前已覆盖部分文件" "$PREPORT"

# 调度侧：partial 批次仍可整批重跑（出现在本轮可执行批次中）
SOUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$D")"
printf '%s\n' "$SOUT" | grep -q "| $BID2 | 部分完成待重跑 |"
printf '%s\n' "$SOUT" | grep -q "本轮可执行批次: $BID2"
printf '%s\n' "$SOUT" | grep -q "部分完成待重跑批次可以在本轮调度"

echo "PASS: frontend batch resume and gate"
