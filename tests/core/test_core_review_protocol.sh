#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-review-protocol.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# P0: incremental input must freeze refs, selected paths and content identity.
REPO="$TMP_DIR/repo"; mkdir -p "$REPO/src"; cd "$REPO"
git init -q; git config user.email test@example.com; git config user.name test
printf 'one\n' > src/a.py; git add .; git commit -qm initial
printf 'two\n' > src/a.py
printf '%s\n' "$REPO/src/a.py" > "$TMP_DIR/python.manifest"
INPUT_OUT="$(bash "$ROOT_DIR/scripts/core/prepare-review-input.sh" "$REPO" python incremental 1 "$TMP_DIR/python.manifest" "$TMP_DIR/review-input.json")"
grep -q '^REVIEW_INPUT_SELECTED_COUNT=1$' <<< "$INPUT_OUT"
jq -e '.schema_version == 1 and .selection_mode == "incremental" and .selected_item_count == 1 and .selected_line_count == 1 and .items[0].path == "src/a.py" and .items[0].selected == true and (.items[0].fingerprint | length == 64)' "$TMP_DIR/review-input.json" >/dev/null

# Java 单 agent 存量/指定模块也能先冻结同一生产源码口径。
mkdir -p "$REPO/module-a/src/main/java/demo" "$REPO/module-a/src/test/java/demo"
printf 'class Demo {}\n' > "$REPO/module-a/src/main/java/demo/Demo.java"
printf 'class DemoTest {}\n' > "$REPO/module-a/src/test/java/demo/DemoTest.java"
bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$REPO" module-a > "$TMP_DIR/java.manifest"
bash "$ROOT_DIR/scripts/core/prepare-review-input.sh" "$REPO" java scoped 0 "$TMP_DIR/java.manifest" "$TMP_DIR/java-review-input.json" >/dev/null
jq -e '.selected_item_count == 1 and .selected_line_count == 1 and .items[0].path == "module-a/src/main/java/demo/Demo.java"' "$TMP_DIR/java-review-input.json" >/dev/null

# Manifest paths are opaque file names: a valid trailing-space file must not be
# rewritten as a different path while CRLF and whitespace-only lines are ignored.
TRAILING_SPACE_FILE="$REPO/src/trailing.py "
printf 'value = 1\n' > "$TRAILING_SPACE_FILE"
printf '\r\n%s\r\n' "$TRAILING_SPACE_FILE" > "$TMP_DIR/trailing.manifest"
bash "$ROOT_DIR/scripts/core/prepare-review-input.sh" "$REPO" python full 0 "$TMP_DIR/trailing.manifest" "$TMP_DIR/trailing-input.json" >/dev/null
jq -e '.selected_item_count == 1 and (.items[0].path | endswith("trailing.py ")) and (.items[0].fingerprint | length == 64)' "$TMP_DIR/trailing-input.json" >/dev/null

# P1: a direct relative import creates one atomic review unit, and an explicit
# project rule is resolved per file and carried into the file-token run plan.
APP="$TMP_DIR/app"; mkdir -p "$APP/src/api" "$APP/src/shared" "$APP/.cc-code-reviewer"
printf 'export const auth = true;\n' > "$APP/src/shared/auth.ts"
printf 'import { auth } from "../shared/auth";\nexport const route = auth;\n' > "$APP/src/api/route.ts"
printf '%s\n' "$APP/src/shared/auth.ts" "$APP/src/api/route.ts" > "$TMP_DIR/frontend.manifest"
cat > "$APP/.cc-code-reviewer/review-rules.yml" <<'YAML'
version: 1
rules:
  - name: api-boundary
    paths:
      - "src/api/**"
    instruction: "核对鉴权、输入校验和错误契约"
    merge_language_rule: true
YAML
bash "$ROOT_DIR/scripts/core/plan-review-units.sh" "$APP" frontend "$TMP_DIR/frontend.manifest" "$TMP_DIR/review-units.json" >/dev/null
jq -e '(.units | length) == 1 and (.units[0].files | length) == 2' "$TMP_DIR/review-units.json" >/dev/null
bash "$ROOT_DIR/scripts/core/resolve-review-rules.sh" "$APP" "$TMP_DIR/frontend.manifest" "$TMP_DIR/review-rules.json" >/dev/null
jq -e '.rule_count == 1 and (.files[] | select(.path == "src/api/route.ts") | .rules[0].name == "api-boundary") and (.files[] | select(.path == "src/shared/auth.ts") | (.rules | length) == 0)' "$TMP_DIR/review-rules.json" >/dev/null

cat > "$TMP_DIR/scoped-review-input.json" <<'JSON'
{"schema_version":1,"items":[
  {"path":"src/api/route.ts","selected":true},
  {"path":"src/shared/auth.ts","selected":false,"exclude_reason":"outside-scope"}
]}
JSON
bash "$ROOT_DIR/scripts/core/resolve-review-rules.sh" "$APP" "$TMP_DIR/scoped-review-input.json" "$TMP_DIR/scoped-review-rules.json" "$APP/.cc-code-reviewer/review-rules.yml" review-input >/dev/null
jq -e '.rule_count == 1 and (.files | length) == 1 and .files[0].path == "src/api/route.ts" and .files[0].rules[0].name == "api-boundary"' "$TMP_DIR/scoped-review-rules.json" >/dev/null

cat > "$TMP_DIR/malformed-review-rules.yml" <<'YAML'
version: 1
rules:
  - name: malformed
    paths:
      - "src/api/**"
    instruction: |
      this must be rejected
YAML
if bash "$ROOT_DIR/scripts/core/resolve-review-rules.sh" "$APP" "$TMP_DIR/frontend.manifest" "$TMP_DIR/malformed-review-rules.json" "$TMP_DIR/malformed-review-rules.yml" >/dev/null 2>&1; then
  echo "FAIL: malformed review-rules YAML was accepted" >&2
  exit 1
fi

# Stable repository identity canonicalizes equivalent HTTPS and SCP-style SSH
# remotes, so local clone path and transport choice cannot perturb item IDs.
git -C "$APP" init -q
git -C "$APP" config user.email test@example.com
git -C "$APP" config user.name test
git -C "$APP" add .
git -C "$APP" commit -qm initial
git -C "$APP" remote add origin https://git@example.com/org/app.git

PLAN_OUT="$(CC_CODE_REVIEWER_RUNS_ROOT="$TMP_DIR/runs" CC_CODE_REVIEWER_RUN_TIMESTAMP=fixture \
  bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$APP" standard main frontend "$TMP_DIR/frontend.manifest")"
RUN_DIR="$(sed -n 's/^RUN_DIR=//p' <<< "$PLAN_OUT")"
jq -e '.association_enabled == true and .total_source_file_count == 2 and (.review_rules_resolved_path | endswith("review-rules.json"))' "$RUN_DIR/plan.json" >/dev/null
jq -e '(.review_units | length) == 1' "$RUN_DIR/batches/batch-001.json" >/dev/null

# P0: merge derives a coverage ledger from planned files and status, then links
# it from summary.json rather than relying on Markdown issue counting.
cat > "$RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":2,"planned_source_file_count":2,"result_path":"$RUN_DIR/results/batch-001.md","finding_count":0}
JSON
printf '# Batch 001\n\n（无正式发现）\n' > "$RUN_DIR/results/batch-001.md"
MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$RUN_DIR" >/dev/null
jq -e '(.coverage | length) == 2 and (.coverage | all(.status == "completed"))' "$RUN_DIR/run-manifest.json" >/dev/null
jq -e '.contract_version == "cc-code-reviewer.run-manifest/v1" and .terminal_state == "complete" and .selected_item_count == 2 and (.coverage_sets.selected | length) == 2 and (.coverage_sets.completed | all(.item_id | length == 64))' "$RUN_DIR/run-manifest.json" >/dev/null
jq -e '(.coverage | all(.path | startswith("/") | not))' "$RUN_DIR/run-manifest.json" >/dev/null
jq -e '.run_manifest_path | endswith("run-manifest.json")' "$RUN_DIR/summary.json" >/dev/null

# Stable audit IDs must survive the same project being reviewed from another
# clone/workspace root. Both the repository identity and per-file IDs are part
# of the public v1.6 contract and therefore cannot depend on local absolutes.
SECOND_PARENT="$TMP_DIR/second-root"; mkdir -p "$SECOND_PARENT"
cp -R "$APP" "$SECOND_PARENT/app"
SECOND_APP="$SECOND_PARENT/app"
git -C "$SECOND_APP" remote set-url origin git@example.com:org/app.git
printf '%s\n' "$SECOND_APP/src/shared/auth.ts" "$SECOND_APP/src/api/route.ts" > "$TMP_DIR/frontend-second.manifest"
SECOND_PLAN_OUT="$(CC_CODE_REVIEWER_RUNS_ROOT="$TMP_DIR/runs-second" CC_CODE_REVIEWER_RUN_TIMESTAMP=fixture \
  bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$SECOND_APP" standard main frontend "$TMP_DIR/frontend-second.manifest")"
SECOND_RUN_DIR="$(sed -n 's/^RUN_DIR=//p' <<< "$SECOND_PLAN_OUT")"
cat > "$SECOND_RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_source_loc":2,"planned_source_file_count":2,"result_path":"$SECOND_RUN_DIR/results/batch-001.md","finding_count":0}
JSON
printf '# Batch 001\n\n（无正式发现）\n' > "$SECOND_RUN_DIR/results/batch-001.md"
MERGE_WAIT_TIMEOUT_SECONDS=0 bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$SECOND_RUN_DIR" >/dev/null
test "$(jq -r '.repository_identity_sha256' "$RUN_DIR/run-manifest.json")" = "$(jq -r '.repository_identity_sha256' "$SECOND_RUN_DIR/run-manifest.json")"
test "$(jq -c '[.coverage_sets.selected[].item_id] | sort' "$RUN_DIR/run-manifest.json")" = "$(jq -c '[.coverage_sets.selected[].item_id] | sort' "$SECOND_RUN_DIR/run-manifest.json")"

echo "PASS: core review protocol (input, rules, units, coverage)"
