# Maven Large Repository Batch Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a resumable Maven multi-module full-stock review mode that plans module-aware batches, runs a bounded number of atomic batch reviews per invocation, and merges completed batch reports.

**Architecture:** Keep the existing scan skill as the orchestrator, add focused Bash scripts for jdtls detection, Maven batch planning, status display, and deterministic merge. Batch plans are directory-level (`scan_roots`), batch execution is atomic, and completed batch reports are persisted under `.cc-code-reviewer/runs/{RUN_ID}` so later sessions can continue without rerunning finished work.

**Tech Stack:** Bash, POSIX tools available on macOS/Linux, Perl for lightweight XML/JSON-safe parsing, existing Claude Code skill/agent Markdown contracts, existing `tests/run_all.sh` Bash test suite.

---

## File Structure

- Create `scripts/phase10-detect-code-intelligence.sh`: detects whether `jdtls` and the Claude Code `jdtls-lsp` plugin appear available. It never blocks review; it emits `CODE_INTELLIGENCE_AVAILABLE=true|false`.
- Create `scripts/phase11-plan-large-batches.sh`: parses Maven reactor modules, computes module LOC, builds reactor-local dependency edges, creates `.cc-code-reviewer/runs/{RUN_ID}`, writes `plan.json`, `batches/batch-XXX.json`, initial `results/batch-XXX.status.json`, and `progress.jsonl`.
- Create `scripts/phase12-merge-large-batches.sh`: reads a run directory, reconciles statuses, merges only completed batch reports, writes `summary.json` and `final/code-review-report-*`.
- Create `scripts/phase13-show-large-batch-status.sh`: prints the latest compatible run status with Chinese labels.
- Modify `skills/cc-code-reviewer/SKILL.md`: adds the Maven large-repo flow, user confirmations, per-run execution count, resume behavior, batch agent orchestration, and final merge/upload rules.
- Modify `agents/cc-code-reviewer.md`: adds atomic batch mode contract based on `BATCH_PLAN_PATH`, `BATCH_STATUS_PATH`, `BATCH_RESULT_PATH`, `scan_roots`, and jdtls semantic lookup rules.
- Modify `references/examples.md`: adds one large Maven stock review example showing planning, status table, bounded execution, resume, and final merge.
- Modify `references/report-format.md`: documents the large-repo execution summary section for staged and full reports.
- Modify `AGENTS.md`, `CLAUDE.md`, `README.md` only if contract text needs to reflect the new scripts and user-visible workflow.
- Create `tests/test_phase10_detect_code_intelligence.sh`.
- Create `tests/test_phase11_plan_large_batches.sh`.
- Create `tests/test_phase12_merge_large_batches.sh`.
- Create `tests/test_phase13_show_large_batch_status.sh`.
- Modify `tests/test_contract_docs.sh`.

---

### Task 1: Lock The Contract In Tests

**Files:**
- Modify: `tests/test_contract_docs.sh`
- Test: `tests/test_contract_docs.sh`

- [ ] **Step 1: Add failing contract checks**

Append this block near the existing batch scanning contract section in `tests/test_contract_docs.sh`:

```bash
# === Maven large repository batching contracts ===

grep -q "phase10-detect-code-intelligence.sh" "$SKILL_FILE"
grep -q "phase11-plan-large-batches.sh" "$SKILL_FILE"
grep -q "phase12-merge-large-batches.sh" "$SKILL_FILE"
grep -q "phase13-show-large-batch-status.sh" "$SKILL_FILE"

grep -q "Maven 多模块" "$SKILL_FILE"
grep -q "存量审查" "$SKILL_FILE"
grep -q "全量代码" "$SKILL_FILE"
grep -q "TOTAL_JAVA_LOC >= 120000" "$SKILL_FILE"

grep -q "TARGET_BATCH_LOC = 25000" "$SKILL_FILE"
grep -q "SOFT_MIN_BATCH_LOC = 15000" "$SKILL_FILE"
grep -q "SOFT_MAX_BATCH_LOC = 30000" "$SKILL_FILE"
grep -q "HARD_MAX_BATCH_LOC = 35000" "$SKILL_FILE"

grep -q "pending.*待执行" "$SKILL_FILE"
grep -q "running.*执行中" "$SKILL_FILE"
grep -q "completed.*已完成" "$SKILL_FILE"
grep -q "failed.*失败待重试" "$SKILL_FILE"
if grep -qE "partial|stale|skipped|部分完成|中断待确认|已跳过|reviewed_java_files|remaining_files" "$SKILL_FILE" "$AGENT_FILE"; then
  echo "large repo v1 must keep atomic batch states only: pending/running/completed/failed" >&2
  exit 1
fi

grep -q "scan_roots" "$SKILL_FILE"
grep -q "正式问题.*scan_roots" "$SKILL_FILE"
grep -q "jdtls.*跨目录" "$SKILL_FILE"
grep -q "跨批依赖待复核" "$SKILL_FILE"

grep -q "BATCH_PLAN_PATH" "$AGENT_FILE"
grep -q "BATCH_STATUS_PATH" "$AGENT_FILE"
grep -q "BATCH_RESULT_PATH" "$AGENT_FILE"
grep -q "scan_roots" "$AGENT_FILE"
grep -q "正式问题.*scan_roots" "$AGENT_FILE"
grep -q "跨批依赖待复核" "$AGENT_FILE"
```

- [ ] **Step 2: Run the contract test and verify it fails**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: FAIL because the scripts and contract wording do not exist yet.

- [ ] **Step 3: Commit the failing contract test**

```bash
git add tests/test_contract_docs.sh
git commit -m "test: lock maven large repo batching contract"
```

---

### Task 2: Add jdtls Capability Detection

**Files:**
- Create: `scripts/phase10-detect-code-intelligence.sh`
- Create: `tests/test_phase10_detect_code_intelligence.sh`

- [ ] **Step 1: Write tests for code intelligence detection**

Create `tests/test_phase10_detect_code_intelligence.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase10.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/demo"
mkdir -p "$PROJECT_DIR/src/main/java/com/example"
printf 'public class Demo {}\n' > "$PROJECT_DIR/src/main/java/com/example/Demo.java"

OUTPUT="$(PATH="/usr/bin:/bin" bash "$ROOT_DIR/scripts/phase10-detect-code-intelligence.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_LANGUAGE=java"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PROVIDER=none"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_REASON="

NON_JAVA="$TMP_DIR/non-java"
mkdir -p "$NON_JAVA"
OUTPUT="$(bash "$ROOT_DIR/scripts/phase10-detect-code-intelligence.sh" "$NON_JAVA")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=false"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_REASON=未识别Java项目"

FAKE_BIN="$TMP_DIR/bin"
FAKE_PLUGIN_ROOT="$TMP_DIR/plugins"
mkdir -p "$FAKE_BIN" "$FAKE_PLUGIN_ROOT/claude-plugins-official/jdtls-lsp"
cat > "$FAKE_BIN/jdtls" <<'SH'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "jdtls fake"
  exit 0
fi
exit 0
SH
chmod +x "$FAKE_BIN/jdtls"

OUTPUT="$(CLAUDE_CODE_PLUGIN_ROOTS="$FAKE_PLUGIN_ROOT" PATH="$FAKE_BIN:/usr/bin:/bin" bash "$ROOT_DIR/scripts/phase10-detect-code-intelligence.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_AVAILABLE=true"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PROVIDER=jdtls-lsp"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_JDTLS_READY=true"
printf '%s\n' "$OUTPUT" | grep -q "CODE_INTELLIGENCE_PLUGIN_INSTALLED=true"
```

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```bash
bash tests/test_phase10_detect_code_intelligence.sh
```

Expected: FAIL because `scripts/phase10-detect-code-intelligence.sh` does not exist.

- [ ] **Step 3: Implement `phase10-detect-code-intelligence.sh`**

Create `scripts/phase10-detect-code-intelligence.sh`:

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"

emit_unavailable() {
  echo "CODE_INTELLIGENCE_AVAILABLE=false"
  echo "CODE_INTELLIGENCE_LANGUAGE=java"
  echo "CODE_INTELLIGENCE_PROVIDER=none"
  echo "CODE_INTELLIGENCE_JDTLS_INSTALLED=${JDTLS_INSTALLED:-false}"
  echo "CODE_INTELLIGENCE_JDTLS_READY=${JDTLS_READY:-false}"
  echo "CODE_INTELLIGENCE_PLUGIN_INSTALLED=${PLUGIN_INSTALLED:-false}"
  echo "CODE_INTELLIGENCE_REASON=$1"
  echo "CODE_INTELLIGENCE_INSTALL_HINT=建议安装 jdtls 并启用 Claude Code jdtls-lsp 插件；不可用时将回退到 Maven 静态依赖分批"
}

is_java_project() {
  [ -f "$PROJECT_DIR/pom.xml" ] ||
    [ -f "$PROJECT_DIR/build.gradle" ] ||
    [ -f "$PROJECT_DIR/build.gradle.kts" ] ||
    find "$PROJECT_DIR" -name '*.java' -not -path '*/target/*' -not -path '*/build/*' -not -path '*/.git/*' -print -quit 2>/dev/null | grep -q .
}

if [ ! -d "$PROJECT_DIR" ]; then
  emit_unavailable "项目路径不存在"
  exit 0
fi

if ! is_java_project; then
  emit_unavailable "未识别Java项目"
  exit 0
fi

JDTLS_PATH="$(command -v jdtls 2>/dev/null || true)"
JDTLS_INSTALLED=false
JDTLS_READY=false
PLUGIN_INSTALLED=false

if [ -n "$JDTLS_PATH" ]; then
  JDTLS_INSTALLED=true
  if perl -e 'alarm 5; exec @ARGV' "$JDTLS_PATH" --version >/dev/null 2>&1; then
    JDTLS_READY=true
  fi
fi

plugin_installed() {
  local roots="${CLAUDE_CODE_PLUGIN_ROOTS:-}"
  local root
  if [ -n "$roots" ]; then
    IFS=':' read -r -a root_array <<< "$roots"
    for root in "${root_array[@]}"; do
      [ -d "$root/jdtls-lsp" ] && return 0
      [ -d "$root/claude-plugins-official/jdtls-lsp" ] && return 0
    done
  fi
  [ -d "$HOME/.claude/plugins/data/jdtls-lsp-claude-plugins-official" ]
}

if plugin_installed; then
  PLUGIN_INSTALLED=true
fi

if [ "$JDTLS_INSTALLED" = true ] && [ "$JDTLS_READY" = true ] && [ "$PLUGIN_INSTALLED" = true ]; then
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=java"
  echo "CODE_INTELLIGENCE_PROVIDER=jdtls-lsp"
  echo "CODE_INTELLIGENCE_COMMAND=$JDTLS_PATH"
  echo "CODE_INTELLIGENCE_JDTLS_INSTALLED=true"
  echo "CODE_INTELLIGENCE_JDTLS_READY=true"
  echo "CODE_INTELLIGENCE_PLUGIN_INSTALLED=true"
  echo "CODE_INTELLIGENCE_CAPABILITIES=definition,references,implementations,call_hierarchy,diagnostics"
else
  if [ "$JDTLS_INSTALLED" != true ] && [ "$PLUGIN_INSTALLED" != true ]; then
    emit_unavailable "未检测到jdtls命令和Claude Code jdtls-lsp插件"
  elif [ "$JDTLS_INSTALLED" != true ]; then
    emit_unavailable "未检测到jdtls命令"
  elif [ "$JDTLS_READY" != true ]; then
    emit_unavailable "jdtls命令不可用或响应超时"
  else
    emit_unavailable "未检测到Claude Code jdtls-lsp插件"
  fi
fi
```

- [ ] **Step 4: Make it executable and run the test**

Run:

```bash
chmod +x scripts/phase10-detect-code-intelligence.sh
bash tests/test_phase10_detect_code_intelligence.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/phase10-detect-code-intelligence.sh tests/test_phase10_detect_code_intelligence.sh
git commit -m "feat: detect java code intelligence capability"
```

---

### Task 3: Implement Maven Module Batch Planning

**Files:**
- Create: `scripts/phase11-plan-large-batches.sh`
- Create: `tests/test_phase11_plan_large_batches.sh`

- [ ] **Step 1: Write planner tests**

Create `tests/test_phase11_plan_large_batches.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase11-large.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/maven-large"
mkdir -p "$PROJECT_DIR"
cat > "$PROJECT_DIR/pom.xml" <<'XML'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>root</artifactId>
  <version>1.0</version>
  <packaging>pom</packaging>
  <modules>
    <module>order-api</module>
    <module>order-service</module>
    <module>order-dao</module>
    <module>inventory</module>
  </modules>
</project>
XML

create_module() {
  local module="$1"
  local artifact="$2"
  local dependency="${3:-}"
  local lines="$4"
  mkdir -p "$PROJECT_DIR/$module/src/main/java/com/example/$module"
  cat > "$PROJECT_DIR/$module/pom.xml" <<XML
<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.example</groupId>
    <artifactId>root</artifactId>
    <version>1.0</version>
  </parent>
  <artifactId>$artifact</artifactId>
  <dependencies>
    $dependency
  </dependencies>
</project>
XML
  {
    echo "package com.example.$module;"
    echo "public class Demo {"
    seq 1 "$lines" | sed 's/.*/  public void m&() {}/'
    echo "}"
  } > "$PROJECT_DIR/$module/src/main/java/com/example/$module/Demo.java"
}

DEP_SERVICE='<dependency><groupId>com.example</groupId><artifactId>order-service</artifactId><version>1.0</version></dependency>'
DEP_DAO='<dependency><groupId>com.example</groupId><artifactId>order-dao</artifactId><version>1.0</version></dependency>'
create_module "order-api" "order-api" "$DEP_SERVICE" 8000
create_module "order-service" "order-service" "$DEP_DAO" 10000
create_module "order-dao" "order-dao" "" 5000
create_module "inventory" "inventory" "" 6000

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260528-010203 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$PROJECT_DIR" "standard" "main" "jdtls-lsp")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"

test -f "$RUN_DIR/plan.json"
test -f "$RUN_DIR/batches/batch-001.json"
test -f "$RUN_DIR/results/batch-001.status.json"
test -f "$RUN_DIR/progress.jsonl"

grep -q '"strategy": "maven-module-batching"' "$RUN_DIR/plan.json"
grep -q '"semantic_level": "jdtls-lsp"' "$RUN_DIR/plan.json"
grep -q '"status": "pending"' "$RUN_DIR/results/batch-001.status.json"
grep -q '"scan_roots"' "$RUN_DIR/batches/batch-001.json"
grep -q '"order-api"' "$RUN_DIR/batches/batch-001.json"
grep -q '"order-service"' "$RUN_DIR/batches/batch-001.json"
grep -q '"order-dao"' "$RUN_DIR/batches/batch-001.json"
grep -q '"from": "order-api"' "$RUN_DIR/batches/batch-001.json"
grep -q '"to": "order-service"' "$RUN_DIR/batches/batch-001.json"
if grep -q 'files.txt\|reviewed_java_files\|remaining_files' "$RUN_DIR"/batches/*.json "$RUN_DIR"/results/*.status.json; then
  echo "planner must not create file manifests or file-level reviewed state" >&2
  exit 1
fi

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260528-020304 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$PROJECT_DIR" "standard" "main" "maven-static")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"
grep -q '"semantic_level": "maven-static"' "$RUN_DIR/plan.json"

STATUS_COUNT="$(find "$RUN_DIR/results" -name 'batch-*.status.json' | wc -l | tr -d ' ')"
BATCH_COUNT="$(sed -n 's/.*"batch_count": \([0-9][0-9]*\).*/\1/p' "$RUN_DIR/plan.json" | head -1)"
test "$STATUS_COUNT" = "$BATCH_COUNT"
```

- [ ] **Step 2: Run planner test and verify it fails**

Run:

```bash
bash tests/test_phase11_plan_large_batches.sh
```

Expected: FAIL because the planner script does not exist.

- [ ] **Step 3: Implement the planner skeleton**

Create `scripts/phase11-plan-large-batches.sh` with these top-level functions and constants:

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_MODE="${2:?请输入审查模式}"
BRANCH_NAME="${3:-no-branch}"
SEMANTIC_LEVEL="${4:-maven-static}"

TARGET_BATCH_LOC=25000
SOFT_MIN_BATCH_LOC=15000
SOFT_MAX_BATCH_LOC=30000
HARD_MAX_BATCH_LOC=35000

json_escape() {
  printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'
}

branch_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//' | cut -c1-40
}

short_hash() {
  printf '%s' "$1" | shasum -a 256 | awk '{print substr($1, 1, 8)}'
}

module_loc() {
  local dir="$1"
  find "$dir" -name '*.java' -not -path '*/target/*' -print0 2>/dev/null |
    xargs -0 wc -l 2>/dev/null |
    awk 'END {print $1 + 0}'
}

module_files() {
  local dir="$1"
  find "$dir" -name '*.java' -not -path '*/target/*' 2>/dev/null | wc -l | tr -d ' '
}
```

- [ ] **Step 4: Add Maven reactor parsing**

Add static parsing helpers to the same script:

```bash
extract_modules() {
  perl -0ne 'while (/<module>\s*([^<]+?)\s*<\/module>/g) { print "$1\n" }' "$PROJECT_DIR/pom.xml"
}

artifact_id_for_pom() {
  perl -0ne '
    s/<parent>.*?<\/parent>//sg;
    if (/<artifactId>\s*([^<]+?)\s*<\/artifactId>/) { print $1; exit }
  ' "$1"
}

dependencies_for_pom() {
  perl -0ne '
    while (/<dependency>.*?<artifactId>\s*([^<]+?)\s*<\/artifactId>.*?<\/dependency>/sg) {
      print "$1\n";
    }
  ' "$1"
}
```

- [ ] **Step 5: Add batch JSON/status writers**

Implement writers that produce directory-level batch plans:

```bash
write_status() {
  local status_path="$1"
  local batch_id="$2"
  local planned_loc="$3"
  local planned_files="$4"
  cat > "$status_path.tmp" <<JSON
{
  "schema_version": 1,
  "run_id": "$(json_escape "$RUN_ID")",
  "batch_id": "$batch_id",
  "status": "pending",
  "planned_java_loc": $planned_loc,
  "planned_java_file_count": $planned_files,
  "attempt": 0,
  "started_at": null,
  "finished_at": null,
  "result_path": "results/$batch_id.md",
  "finding_count": 0,
  "error": null
}
JSON
  mv "$status_path.tmp" "$status_path"
}
```

Use `batch-001`, `batch-002`, etc. for ids. Store `scan_roots` as module paths, not file paths.

- [ ] **Step 6: Add simple dependency-aware grouping**

Implement v1 grouping with these concrete rules:

```text
For each unassigned module sorted by risk score:
  start a new batch with that module
  add direct reactor dependencies if they are unassigned and total LOC <= SOFT_MAX_BATCH_LOC
  if current batch LOC < SOFT_MIN_BATCH_LOC, add the nearest unassigned module with the strongest dependency relation
  if any single module LOC > HARD_MAX_BATCH_LOC, emit one batch for the module path and set split_reason="oversized_module"
```

The oversized-module split can be improved later; v1 must mark it clearly but may keep the module as one batch if no safe package directories are detected. If it stays above hard max, set `"large_batch": true` and `"split_reason": "oversized_module_needs_package_split"` so the status table is honest.

- [ ] **Step 7: Run planner tests**

Run:

```bash
chmod +x scripts/phase11-plan-large-batches.sh
bash tests/test_phase11_plan_large_batches.sh
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/phase11-plan-large-batches.sh tests/test_phase11_plan_large_batches.sh
git commit -m "feat: plan maven large repo batches"
```

---

### Task 4: Add Status Console

**Files:**
- Create: `scripts/phase13-show-large-batch-status.sh`
- Create: `tests/test_phase13_show_large_batch_status.sh`

- [ ] **Step 1: Write status console test**

Create `tests/test_phase13_show_large_batch_status.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase13.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_DIR="$TMP_DIR/project"
RUN_DIR="$PROJECT_DIR/.cc-code-reviewer/runs/20260528-010203-main-standard-full-large-maven"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"

cat > "$RUN_DIR/plan.json" <<JSON
{"run_id":"20260528-010203-main-standard-full-large-maven","project_name":"project","project_dir":"$PROJECT_DIR","review_mode":"standard","review_scope":"全量代码","semantic_level":"maven-static","total_java_loc":500000,"total_java_file_count":4000,"batch_count":2}
JSON

cat > "$RUN_DIR/batches/batch-001.json" <<JSON
{"batch_id":"batch-001","planned_java_loc":24800,"planned_java_file_count":186,"scan_roots":["user-api","user-service"],"modules":[{"name":"user-api"},{"name":"user-service"}]}
JSON
cat > "$RUN_DIR/batches/batch-002.json" <<JSON
{"batch_id":"batch-002","planned_java_loc":26100,"planned_java_file_count":201,"scan_roots":["order-core","order-dao"],"modules":[{"name":"order-core"},{"name":"order-dao"}]}
JSON

cat > "$RUN_DIR/results/batch-001.status.json" <<'JSON'
{"batch_id":"batch-001","status":"completed","planned_java_loc":24800,"planned_java_file_count":186,"finished_at":"2026-05-28T14:30:00Z","finding_count":5}
JSON
cat > "$RUN_DIR/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed","planned_java_loc":26100,"planned_java_file_count":201,"finished_at":"2026-05-28T15:30:00Z","error":"上次执行中断，需要整批重跑"}
JSON

OUTPUT="$(bash "$ROOT_DIR/scripts/phase13-show-large-batch-status.sh" "$PROJECT_DIR")"
printf '%s\n' "$OUTPUT" | grep -q "大仓库审查任务"
printf '%s\n' "$OUTPUT" | grep -q "已完成"
printf '%s\n' "$OUTPUT" | grep -q "失败待重试"
printf '%s\n' "$OUTPUT" | grep -q "user-api,user-service"
printf '%s\n' "$OUTPUT" | grep -q "Java 行覆盖: 24,800 / 500,000"
if printf '%s\n' "$OUTPUT" | grep -qE "pending|running|completed|failed"; then
  echo "status console must show Chinese labels, not internal enum values" >&2
  exit 1
fi
```

- [ ] **Step 2: Run status test and verify it fails**

Run:

```bash
bash tests/test_phase13_show_large_batch_status.sh
```

Expected: FAIL because the status console script does not exist.

- [ ] **Step 3: Implement status console**

Create `scripts/phase13-show-large-batch-status.sh` with:

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
RUNS_DIR="$PROJECT_DIR/.cc-code-reviewer/runs"

json_value() {
  local key="$1"
  local file="$2"
  perl -0ne '
    BEGIN { our $key = shift @ARGV; }
    our $key;
    if (/"\Q$key\E"\s*:\s*("(?:\\.|[^"\\])*"|[0-9]+|true|false|null)/s) {
      my $v = $1;
      if ($v =~ /^"/) { $v = substr($v, 1, -1); $v =~ s/\\(["\\\/])/$1/g; }
      print $v unless $v eq "null";
      exit;
    }
  ' "$key" "$file"
}

status_label() {
  case "$1" in
    pending) echo "待执行" ;;
    running) echo "执行中" ;;
    completed) echo "已完成" ;;
    failed) echo "失败待重试" ;;
    *) echo "未知" ;;
  esac
}

format_num() {
  printf "%'d" "$1" 2>/dev/null || printf "%s" "$1"
}
```

Find the newest run with `ls -td "$RUNS_DIR"/*-large-maven`, read its plan, total completed LOC from completed statuses, and print a fixed-width table:

```bash
printf '%-5s %-12s %-10s %-6s %s\n' "批次" "状态" "行数" "文件" "模块"
```

- [ ] **Step 4: Run status console test**

Run:

```bash
chmod +x scripts/phase13-show-large-batch-status.sh
bash tests/test_phase13_show_large_batch_status.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/phase13-show-large-batch-status.sh tests/test_phase13_show_large_batch_status.sh
git commit -m "feat: show large review batch status"
```

---

### Task 5: Add Deterministic Merge

**Files:**
- Create: `scripts/phase12-merge-large-batches.sh`
- Create: `tests/test_phase12_merge_large_batches.sh`

- [ ] **Step 1: Write merge tests**

Create `tests/test_phase12_merge_large_batches.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase12-large.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run"
mkdir -p "$RUN_DIR/batches" "$RUN_DIR/results"

cat > "$RUN_DIR/plan.json" <<'JSON'
{"run_id":"run-1","project_name":"demo","review_mode":"standard","review_scope":"全量代码","semantic_level":"maven-static","total_java_loc":50000,"total_java_file_count":400,"batch_count":2}
JSON

cat > "$RUN_DIR/batches/batch-001.json" <<'JSON'
{"batch_id":"batch-001","planned_java_loc":25000,"planned_java_file_count":200,"scan_roots":["order-api"],"modules":[{"name":"order-api"}]}
JSON
cat > "$RUN_DIR/batches/batch-002.json" <<'JSON'
{"batch_id":"batch-002","planned_java_loc":25000,"planned_java_file_count":200,"scan_roots":["payment"],"modules":[{"name":"payment"}]}
JSON

cat > "$RUN_DIR/results/batch-001.status.json" <<JSON
{"batch_id":"batch-001","status":"completed","planned_java_loc":25000,"planned_java_file_count":200,"result_path":"$RUN_DIR/results/batch-001.md","finding_count":1}
JSON
cat > "$RUN_DIR/results/batch-001.md" <<'MD'
# Batch 001

## 发现列表

### P1 | [维度1-正确性] 示例问题
- 文件：order-api/src/main/java/Demo.java:10
- 置信度：高
- 证据：示例证据
- 影响：示例影响
- 建议：示例建议

## 跨批依赖待复核
- payment 模块调用链需要在对应批次复核
MD

cat > "$RUN_DIR/results/batch-002.status.json" <<'JSON'
{"batch_id":"batch-002","status":"failed","planned_java_loc":25000,"planned_java_file_count":200,"error":"subagent failed"}
JSON

OUTPUT="$(bash "$ROOT_DIR/scripts/phase12-merge-large-batches.sh" "$RUN_DIR")"
FINAL_REPORT="$(printf '%s\n' "$OUTPUT" | sed -n 's/^FINAL_REPORT_PATH=//p')"

test -f "$RUN_DIR/summary.json"
test -f "$FINAL_REPORT"
grep -q '"completed_batches": 1' "$RUN_DIR/summary.json"
grep -q '"failed_batches": 1' "$RUN_DIR/summary.json"
grep -q '"java_loc_coverage_percent": 50' "$RUN_DIR/summary.json"
grep -q '\[阶段性\]' "$FINAL_REPORT"
grep -q "示例问题" "$FINAL_REPORT"
grep -q "跨批依赖线索" "$FINAL_REPORT"
grep -q "payment 模块调用链" "$FINAL_REPORT"
```

- [ ] **Step 2: Run merge test and verify it fails**

Run:

```bash
bash tests/test_phase12_merge_large_batches.sh
```

Expected: FAIL because the merge script does not exist.

- [ ] **Step 3: Implement merge script**

Create `scripts/phase12-merge-large-batches.sh` using the same `json_value` helper from Task 4. Implement:

```text
read plan.json
for each batches/batch-*.json:
  read matching results/batch-XXX.status.json
  if status=completed and result_path exists:
    include result markdown
    add planned_java_loc and planned_java_file_count to covered totals
  else:
    count as failed or pending
write summary.json
write final/code-review-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md
```

Report title logic:

```bash
if [ "$COMPLETED_BATCHES" -lt "$BATCH_COUNT" ]; then
  REPORT_TITLE="[阶段性] 代码审查报告 - $PROJECT_NAME"
else
  REPORT_TITLE="代码审查报告 - $PROJECT_NAME"
fi
```

The final report must include:

```markdown
## 大仓库审查执行摘要

- Run ID：
- 批次完成：
- Java 行覆盖：
- Java 文件覆盖：
- 语义增强：
- 未完成批次：
```

- [ ] **Step 4: Run merge test**

Run:

```bash
chmod +x scripts/phase12-merge-large-batches.sh
bash tests/test_phase12_merge_large_batches.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/phase12-merge-large-batches.sh tests/test_phase12_merge_large_batches.sh
git commit -m "feat: merge completed large review batches"
```

---

### Task 6: Update Batch Agent Contract

**Files:**
- Modify: `agents/cc-code-reviewer.md`
- Test: `tests/test_contract_docs.sh`

- [ ] **Step 1: Update the agent batch input contract**

In `agents/cc-code-reviewer.md`, add a section named `大型仓库批次模式` near the existing batch output mode instructions. Include this exact contract text:

```markdown
## 大型仓库批次模式

当参数中包含 `BATCH_PLAN_PATH`、`BATCH_STATUS_PATH`、`BATCH_RESULT_PATH` 时，进入大型仓库批次模式。

执行规则：
- 必须先读取 `BATCH_PLAN_PATH`。
- `scan_roots` 是本批正式审查边界。
- 正式问题的位置必须位于 `scan_roots` 内。
- 允许使用 jdtls 跨目录查询 definition、references、implementations、call hierarchy 来理解调用链。
- `scan_roots` 外的代码只能作为外部依赖上下文，不得作为本批正式问题位置。
- 如果疑似问题位置在 `scan_roots` 外，写入「跨批依赖待复核」，不计入正式问题数量。
- 批次是原子的；不要写 partial、stale、skipped 或文件级 reviewed 状态。
- 完整写入 `BATCH_RESULT_PATH` 后，才能把 `BATCH_STATUS_PATH` 写为 `completed`。
- 无法完整完成时，把 `BATCH_STATUS_PATH` 写为 `failed`，并写明错误原因。
```

- [ ] **Step 2: Add batch status write examples**

Add status examples:

```json
{
  "schema_version": 1,
  "batch_id": "batch-001",
  "status": "completed",
  "planned_java_loc": 24800,
  "planned_java_file_count": 186,
  "finding_count": 12,
  "result_path": "results/batch-001.md",
  "error": null
}
```

```json
{
  "schema_version": 1,
  "batch_id": "batch-001",
  "status": "failed",
  "planned_java_loc": 24800,
  "planned_java_file_count": 186,
  "finding_count": 0,
  "result_path": null,
  "error": "上次执行中断，需要整批重跑"
}
```

- [ ] **Step 3: Run contract test**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: still FAIL until the skill is updated in Task 7, but agent-related grep checks should now pass.

- [ ] **Step 4: Commit**

```bash
git add agents/cc-code-reviewer.md
git commit -m "docs: define large batch agent contract"
```

---

### Task 7: Update Scan Skill Orchestration

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Test: `tests/test_contract_docs.sh`

- [ ] **Step 1: Add pre-scan jdtls detection**

In `skills/cc-code-reviewer/SKILL.md`, update the pre-scan script list to run phase10 after phase3 and before phase4:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase10-detect-code-intelligence.sh" "$PROJECT_DIR"
# 输出：CODE_INTELLIGENCE_AVAILABLE=true|false CODE_INTELLIGENCE_PROVIDER=jdtls-lsp|none ...
```

Update the pre-scan summary with:

```text
🧠 代码智能：{CODE_INTELLIGENCE_AVAILABLE=true 时显示 "✅ jdtls-lsp 可用，可用于跨目录调用链理解" / false 时显示 "⚠️ 未启用 jdtls-lsp，将使用 Maven 静态依赖分批；建议安装 jdtls 并启用 jdtls-lsp 提升跨模块理解质量"}
```

- [ ] **Step 2: Add large mode trigger wording**

Add a section `### Maven 大仓库模式判定`:

```markdown
仅当以下条件全部满足时进入 Maven 大仓库模式：
- `PROJECT_TYPE=maven-multi`
- `REVIEW_TYPE=存量审查`
- `REVIEW_SCOPE=全量代码`
- `TOTAL_JAVA_LOC >= 120000`

判定公式：
```text
TOTAL_JAVA_LOC >= 120000
TARGET_BATCH_LOC = 25000
SOFT_MIN_BATCH_LOC = 15000
SOFT_MAX_BATCH_LOC = 30000
HARD_MAX_BATCH_LOC = 35000
```
```

- [ ] **Step 3: Add planning command and status display**

Add this execution contract before batch agent launch:

```bash
SEMANTIC_LEVEL="maven-static"
if [ "$CODE_INTELLIGENCE_AVAILABLE" = "true" ]; then
  SEMANTIC_LEVEL="jdtls-lsp"
fi

bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase11-plan-large-batches.sh" "$PROJECT_DIR" "$REVIEW_MODE" "{TARGET_BRANCH 或 CURRENT_BRANCH}" "$SEMANTIC_LEVEL"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase13-show-large-batch-status.sh" "$PROJECT_DIR"
```

- [ ] **Step 4: Add per-run execution count question**

Add an AskUserQuestion step shown only in Maven large mode:

```text
question: "请选择本轮执行批次"
header: "执行批次"
options:
  - label: "执行 3 批"
    description: "适合额度紧张或先试跑"
  - label: "执行 5 批（推荐）"
    description: "适合大多数 50 万行级项目，便于跨天继续"
  - label: "执行 10 批"
    description: "适合当前额度充足时加速推进"
  - label: "执行全部未完成批次"
    description: "一次性执行所有待执行和失败待重试批次"
multiSelect: false
```

- [ ] **Step 5: Add resume behavior**

Document:

```text
恢复时必须读取兼容 RUN_DIR 的 plan.json。
running 状态一律转为 failed，错误写为“上次执行中断，需要整批重跑”。
completed 批次默认跳过。
pending 和 failed 批次按用户本轮执行批次数调度。
```

- [ ] **Step 6: Add batch prompt injection**

For each selected batch, inject:

```markdown
| 运行目录 | {RUN_DIR} |
| 批次计划文件 | {BATCH_PLAN_PATH} |
| 批次状态文件 | {BATCH_STATUS_PATH} |
| 批次结果文件 | {BATCH_RESULT_PATH} |
| 审查输出模式 | 仅发现清单 |

### 本批审查边界
请读取 `BATCH_PLAN_PATH`，以其中 `scan_roots` 作为正式审查边界。
允许使用 jdtls 跨目录理解调用链，但正式问题必须位于 `scan_roots` 内。
```

- [ ] **Step 7: Add merge command**

After selected batch execution:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase12-merge-large-batches.sh" "$RUN_DIR"
```

Document that staged reports are allowed and full reports require all batches completed.

- [ ] **Step 8: Run contract test**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add skills/cc-code-reviewer/SKILL.md tests/test_contract_docs.sh
git commit -m "docs: orchestrate maven large repo batching"
```

---

### Task 8: Update Examples And Report Format

**Files:**
- Modify: `references/examples.md`
- Modify: `references/report-format.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Test: `tests/test_contract_docs.sh`

- [ ] **Step 1: Add report format section**

In `references/report-format.md`, add:

```markdown
## 大仓库审查执行摘要

分批审查报告必须包含：
- Run ID
- 审查分支
- 审查模式
- 语义增强：`jdtls-lsp` 或 `maven-static`
- 批次完成情况：已完成 / 失败待重试 / 待执行
- Java 行覆盖率
- Java 文件覆盖率
- 未完成批次说明

阶段性报告标题必须包含 `[阶段性]`。
完整报告仅在所有批次为 `已完成` 后生成。
```

- [ ] **Step 2: Add examples**

In `references/examples.md`, add a section `## 示例：Maven 大仓库分批审查` with this flow:

```text
用户：帮我审查 /repo/large-maven
系统：预扫描完成，识别 Maven 多模块，500,000 行，jdtls-lsp 可用
系统：进入 Maven 大仓库模式，预计 20 批
系统：展示批次状态表，状态使用 待执行 / 执行中 / 已完成 / 失败待重试
AskUserQuestion：请选择本轮执行批次
用户：执行 5 批（推荐）
系统：执行 batch-001 到 batch-005
系统：生成阶段性报告或等待继续
次日用户：继续审查 /repo/large-maven
系统：读取 RUN_DIR，跳过已完成批次，继续待执行批次
```

- [ ] **Step 3: Update README/AGENTS/CLAUDE only with stable user-facing contract**

Add concise mentions:

```text
Maven 多模块存量全量审查超过阈值时，插件会生成可恢复的大仓库批次任务。批次是原子的，已完成批次跨会话保留，未完成批次整批重跑。
```

- [ ] **Step 4: Run contract test**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add references/examples.md references/report-format.md README.md AGENTS.md CLAUDE.md
git commit -m "docs: document maven large repo review flow"
```

---

### Task 9: Full Verification

**Files:**
- Test: `tests/run_all.sh`

- [ ] **Step 1: Run focused tests**

Run:

```bash
bash tests/test_phase10_detect_code_intelligence.sh
bash tests/test_phase11_plan_large_batches.sh
bash tests/test_phase12_merge_large_batches.sh
bash tests/test_phase13_show_large_batch_status.sh
bash tests/test_contract_docs.sh
```

Expected: all PASS.

- [ ] **Step 2: Run full suite**

Run:

```bash
bash tests/run_all.sh
```

Expected: all PASS, including `git diff --check`.

- [ ] **Step 3: Inspect worktree**

Run:

```bash
git status --short
```

Expected: only intentional files are modified.

- [ ] **Step 4: Commit any verification-only fixes**

If verification required small fixes, commit them:

```bash
git add scripts tests skills agents references README.md AGENTS.md CLAUDE.md
git commit -m "test: verify maven large repo batching"
```

If no files changed after verification, do not create an empty commit.

---

## Self-Review

Spec coverage:

- Maven multi-module stock full-scope only: Task 1, Task 7, Task 8.
- 25k target batch budget and 15k/30k/35k bounds: Task 1, Task 3, Task 7.
- Maven module graph and dependency-aware planning: Task 3.
- jdtls recommended but optional: Task 2, Task 7, Task 8.
- Batch atomicity and four states only: Task 1, Task 3, Task 6, Task 7.
- No file manifests or file-level reviewed state: Task 1, Task 3.
- Persistent run directory: Task 3, Task 4, Task 5.
- Resume without rerunning completed batches: Task 4, Task 7.
- Console status table in Chinese: Task 4, Task 8.
- Batch agent formal boundary vs jdtls semantic lookup: Task 6, Task 7.
- Staged/full report merge: Task 5, Task 8.
- Feishu parent-only upload is covered in Task 7/8 documentation and remains implemented by the existing upload path.

Placeholder scan:

- No placeholder markers or deferred-detail language.
- Each task has exact file paths, commands, expected results, and concrete snippets.

Type and name consistency:

- Script names use `phase10-detect-code-intelligence.sh`, `phase11-plan-large-batches.sh`, `phase12-merge-large-batches.sh`, and `phase13-show-large-batch-status.sh`.
- Batch status states are consistently `pending`, `running`, `completed`, `failed`.
- User-facing status labels are consistently `待执行`, `执行中`, `已完成`, `失败待重试`.
