#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/py-full.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/build/fastapi-app"
mkdir -p "$D/src/app/routes" "$D/tests"
cat > "$D/pyproject.toml" <<'TOML'
[project]
name = "fastapi-app"
dependencies = ["fastapi>=0.100"]
TOML
cat > "$D/src/app/main.py" <<'PY'
from fastapi import FastAPI

app = FastAPI()
PY
cat > "$D/src/app/routes/users.py" <<'PY'
from fastapi import APIRouter

router = APIRouter()
PY
echo 'def test_example(): pass' > "$D/tests/test_example.py"
D="$(cd "$D" && pwd -P)"

# 1. detect + scan
grep -q 'PROJECT_TYPE=python-fastapi' < <(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$D")
SOUT="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D")"
grep -q 'PROFILE_SCHEMA_VERSION=1' <<< "$SOUT"
grep -q 'LANGUAGE_ID=python' <<< "$SOUT"
FCNT="$(printf '%s\n' "$SOUT" | sed -n 's/^SOURCE_FILE_COUNT=//p')"
test "$FCNT" -ge 2

# 2. manifest + common planner
MANIFEST="$TMP_DIR/manifest.txt"
bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D" > "$MANIFEST"
test "$(grep -c . "$MANIFEST")" -ge 2
POUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260722-020000 \
        bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$D" "standard" "main" "python" "$MANIFEST")"
RUN_DIR="$(printf '%s\n' "$POUT" | sed -n 's/^RUN_DIR=//p')"
test -f "$RUN_DIR/plan.json"
grep -q '"language_id": "python"' "$RUN_DIR/plan.json"

# 3. 模拟所有批次完成，验证 Python 能进入公共状态/合并链路
for bj in "$RUN_DIR"/batches/batch-*.json; do
  bid="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{batch_id}' "$bj")"
  bloc="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{planned_source_loc}' "$bj")"
  bfiles="$(perl -MJSON::PP -e 'open my $fh,"<",$ARGV[0]; local $/; my $d=decode_json(<$fh>); print $d->{planned_source_file_count}' "$bj")"
  cat > "$RUN_DIR/results/$bid.md" <<MD
# Batch ${bid}
## 发现列表
### P2 | [维度1-正确性] 示例
- 文件：src/app/main.py:1
- 证据：示例
- 建议：示例
MD
  cat > "$RUN_DIR/results/$bid.status.json" <<JSON
{"batch_id":"$bid","status":"completed",
 "planned_source_loc":${bloc},"planned_source_file_count":${bfiles},
 "result_path":"$RUN_DIR/results/$bid.md","finding_count":1}
JSON
done

STATUS_OUT="$(bash "$ROOT_DIR/scripts/core/show-batch-status.sh" "$D")"
grep -q 'Python 行数' <<< "$STATUS_OUT"
grep -q 'Python 文件' <<< "$STATUS_OUT"

MOUT="$(RUN_BATCH_IDS="" bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR")"
SUMM="$(printf '%s\n' "$MOUT" | sed -n 's/^SUMMARY_PATH=//p')"
REPORT="$(printf '%s\n' "$MOUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"
grep -q '"language_id": "python"' "$SUMM"
grep -q '"finding_count": 1' "$SUMM"
grep -q '"source_file_coverage_percent": 100' "$SUMM"
head -n1 "$REPORT" | grep -qv '\[阶段性\]'
head -n1 "$REPORT" | grep -qv '\[合并阻塞\]'

echo "PASS: python full scan smoke"
