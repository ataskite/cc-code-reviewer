#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-full.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/react"; mkdir -p "$D/src/components" "$D/src/api"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"},
 "devDependencies":{"vite":"^5.0.0","typescript":"^5.0.0"}}
JSON
echo 'export function App(){return <div/>}' > "$D/src/App.tsx"
echo 'export function C(){return <span/>}' > "$D/src/components/C.tsx"
seq 1 9000 | sed 's/.*/export const x& = () => null;/' > "$D/src/api/client.ts"  # 大文件触发分批
cat > "$D/tsconfig.json" <<'JSON'
{"compilerOptions":{"strict":true}}
JSON
cat > "$D/vite.config.ts" <<'TS'
import { defineConfig } from 'vite'; export default defineConfig({})
TS
D="$(cd "$D" && pwd -P)"

# 1. detect + scan
bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D" | grep -q "frontend-react"
SOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D")"
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$SOUT"
FCNT="$(printf '%s\n' "$SOUT" | sed -n 's/^SOURCE_FILE_COUNT=//p')"
test "$FCNT" -ge 3

# 2. manifest + plan
MANIFEST="$(mktemp)"
bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$D" > "$MANIFEST"
test "$(grep -c . "$MANIFEST")" -ge 3
POUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260623-020000 CC_REVIEW_CONTEXT_SCALE=1 \
        bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "frontend" "$MANIFEST")"
RUN_DIR="$(printf '%s\n' "$POUT" | sed -n 's/^RUN_DIR=//p')"
test -f "$RUN_DIR/plan.json"
grep -q '"language_id": "frontend"' "$RUN_DIR/plan.json"

# 3. 模拟所有批次 completed（写 status + 结果），status 复用 batch JSON 的真实计数
for bj in "$RUN_DIR"/batches/batch-*.json; do
  bid="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{batch_id}' "$bj")"
  bloc="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{planned_source_loc}' "$bj")"
  bfiles="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{planned_source_file_count}' "$bj")"
  cat > "$RUN_DIR/results/$bid.md" <<MD
# Batch ${bid}
## 发现列表
### P2 | [维度3-React规范] 示例
- 文件：src/components/C.tsx:1
- 证据：示例
- 建议：示例
MD
  cat > "$RUN_DIR/results/$bid.status.json" <<JSON
{"batch_id":"$bid","status":"completed",
 "planned_source_loc":${bloc},"planned_source_file_count":${bfiles},
 "result_path":"$RUN_DIR/results/$bid.md","finding_count":1}
JSON
done

# 4. merge → 完整报告（无 [阶段性]，覆盖率 = 100%）
MOUT="$(RUN_BATCH_IDS="" bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR")"
SUMM="$(printf '%s\n' "$MOUT" | sed -n 's/^SUMMARY_PATH=//p')"
REPORT="$(printf '%s\n' "$MOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"finding_count": 1' "$SUMM"
grep -q '"source_file_coverage_percent": 100' "$SUMM"
head -n1 "$REPORT" | grep -qv '\[阶段性\]'      # 全部批次纳入 → 完整报告
head -n1 "$REPORT" | grep -qv '\[合并阻塞\]'

echo "PASS: frontend full scan smoke"
