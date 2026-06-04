# Maven Large Repository Batch Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Maven large-repository planning from top-level module batching to semantic-cost batching that recursively splits oversized modules, avoids tiny orphan batches, bounds context roots, and preserves Java-file coverage semantics.

**Architecture:** Keep the existing scan skill and run-directory contract, but make `scripts/phase11-plan-large-batches.sh` produce work units before batch packing. The planner remains deterministic Bash/Perl and does not require jdtls; jdtls only adds optional affinity metadata. Existing phase12/phase13 consumers are updated to read the new `units`, `context_roots`, `planned_review_cost`, and `affinity_edges` fields while keeping compatibility with old `modules` fields during migration.

**Tech Stack:** Bash, Perl, jq in tests where already used, macOS/Linux POSIX tools, existing Markdown skill/agent contracts, existing `tests/run_all.sh` Bash suite.

---

## File Structure

- Modify `scripts/phase11-plan-large-batches.sh`: turn the current top-level module greedy planner into a semantic-cost planner with work-unit generation, recursive oversized splitting, affinity packing, bounded context roots, and tail rebalancing.
- Modify `scripts/phase13-show-large-batch-status.sh`: show review cost, split reasons, and unit labels while continuing to support old `modules` fields.
- Modify `scripts/phase12-merge-large-batches.sh`: keep Java-file coverage as the only coverage metric and tolerate new batch plan fields.
- Modify `skills/cc-code-reviewer/SKILL.md`: update the large-repo contract from module batching to semantic-cost batching, including oversize split and tail rebalance guarantees.
- Modify `agents/cc-code-reviewer.md`: tell batch agents to treat `units[].scan_roots` as formal review roots and `context_roots` as read-only context.
- Modify `references/examples.md`: refresh the large Maven example so it no longer shows 90k+ giant batches or 151-line orphan batches.
- Modify `tests/test_phase11_plan_large_batches.sh`: keep current base coverage and add semantic-cost regression cases.
- Modify `tests/test_phase13_show_large_batch_status.sh`: assert the status table remains readable with new schema fields.
- Modify `tests/test_contract_docs.sh`: lock the refined planning contract.

---

### Task 1: Lock The Refined Contract

**Files:**
- Modify: `tests/test_contract_docs.sh`
- Test: `tests/test_contract_docs.sh`

- [ ] **Step 1: Add contract assertions**

Add this block near the existing Maven large repository batching contract checks:

```bash
require_literal "$SKILL_FILE" "semantic-cost batching" "large repo strategy must be semantic-cost batching"
require_literal "$SKILL_FILE" "review_cost = java_loc + java_file_count * 25" "review cost formula must be documented"
require_literal "$SKILL_FILE" "TARGET_BATCH_COST = 32000" "target review cost must be documented"
require_literal "$SKILL_FILE" "HARD_MAX_BATCH_COST = 45000" "hard review cost must be documented"
require_literal "$SKILL_FILE" "context_roots" "large repo plan must include bounded context roots"
require_literal "$SKILL_FILE" "context cost" "large repo context cost must be bounded"
require_literal "$SKILL_FILE" "work units" "large repo planner must use work units"
require_literal "$SKILL_FILE" "oversized modules are split before plan emission" "oversized modules must be split, not only marked"
require_literal "$SKILL_FILE" "tiny tail batches" "tiny tail batches must be rebalanced"

require_literal "$AGENT_FILE" "context_roots" "batch agent must understand context roots"
require_literal "$AGENT_FILE" "Formal findings must point to locations inside scan_roots" "batch findings must stay inside scan roots"
require_literal "$AGENT_FILE" "context_roots are read-only context" "agent must not count context roots as reviewed"

require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "TARGET_BATCH_COST=32000" "planner must define target review cost"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "HARD_MAX_BATCH_COST=45000" "planner must define hard review cost"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "review_cost" "planner must compute review cost"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "context_roots" "planner must emit context roots"
require_literal "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "semantic-cost-batching" "planner must emit semantic-cost strategy"
```

If `require_literal` is not already available in `tests/test_contract_docs.sh`, add this helper once near the top:

```bash
require_literal() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}
```

- [ ] **Step 2: Run the contract test and verify it fails**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: FAIL because the skill, agent, and planner still use the older module-batching contract.

- [ ] **Step 3: Commit the failing contract test**

```bash
git add tests/test_contract_docs.sh
git commit -m "test: lock semantic cost batching contract"
```

---

### Task 2: Add Planner Regressions For Oversized Modules And Tiny Tails

**Files:**
- Modify: `tests/test_phase11_plan_large_batches.sh`
- Test: `tests/test_phase11_plan_large_batches.sh`

- [ ] **Step 1: Add a synthetic yudao-like fixture**

Add helper functions to `tests/test_phase11_plan_large_batches.sh` after the existing basic planner assertions:

```bash
create_nested_module() {
  local root="$1"
  local module_path="$2"
  local artifact="$3"
  local package_path="$4"
  local lines="$5"
  mkdir -p "$root/$module_path/src/main/java/$package_path"
  cat > "$root/$module_path/pom.xml" <<XML
<project>
  <modelVersion>4.0.0</modelVersion>
  <artifactId>$artifact</artifactId>
</project>
XML
  {
    echo "package ${package_path//\//.};"
    echo "public class Demo {"
    seq 1 "$lines" | sed 's/.*/  public void m&() {}/'
    echo "}"
  } > "$root/$module_path/src/main/java/$package_path/Demo.java"
}

create_aggregator_module() {
  local root="$1"
  local module_path="$2"
  shift 2
  mkdir -p "$root/$module_path"
  {
    echo "<project><modelVersion>4.0.0</modelVersion><artifactId>$(basename "$module_path")</artifactId><packaging>pom</packaging><modules>"
    for child in "$@"; do
      echo "<module>$child</module>"
    done
    echo "</modules></project>"
  } > "$root/$module_path/pom.xml"
}
```

- [ ] **Step 2: Add the oversized split and tail rebalance test**

Append this test case:

```bash
YUDAO_DIR="$TMP_DIR/yudao-like"
mkdir -p "$YUDAO_DIR"
cat > "$YUDAO_DIR/pom.xml" <<'XML'
<project>
  <modelVersion>4.0.0</modelVersion>
  <artifactId>yudao-like</artifactId>
  <packaging>pom</packaging>
  <modules>
    <module>yudao-module-mes</module>
    <module>yudao-module-mall</module>
    <module>yudao-framework</module>
    <module>yudao-gateway</module>
    <module>yudao-module-report</module>
    <module>yudao-dependencies</module>
    <module>yudao-server</module>
  </modules>
</project>
XML

create_aggregator_module "$YUDAO_DIR" "yudao-module-mes" "mes-api" "mes-server"
create_nested_module "$YUDAO_DIR" "yudao-module-mes/mes-api" "mes-api" "com/example/mes/api" 4200
create_nested_module "$YUDAO_DIR" "yudao-module-mes/mes-server" "mes-server" "com/example/mes/server/production" 26000
create_nested_module "$YUDAO_DIR" "yudao-module-mes/mes-server" "mes-server" "com/example/mes/server/quality" 24000
create_nested_module "$YUDAO_DIR" "yudao-module-mes/mes-server" "mes-server" "com/example/mes/server/material" 23000

create_aggregator_module "$YUDAO_DIR" "yudao-module-mall" "product" "trade" "promotion"
create_nested_module "$YUDAO_DIR" "yudao-module-mall/product" "product" "com/example/mall/product" 7000
create_nested_module "$YUDAO_DIR" "yudao-module-mall/trade" "trade" "com/example/mall/trade" 19500
create_nested_module "$YUDAO_DIR" "yudao-module-mall/promotion" "promotion" "com/example/mall/promotion" 18500

create_nested_module "$YUDAO_DIR" "yudao-framework" "yudao-framework" "com/example/framework" 23000
create_nested_module "$YUDAO_DIR" "yudao-gateway" "yudao-gateway" "com/example/gateway" 1500
create_nested_module "$YUDAO_DIR" "yudao-module-report" "yudao-module-report" "com/example/report" 1200
mkdir -p "$YUDAO_DIR/yudao-dependencies"
printf '<project><artifactId>yudao-dependencies</artifactId></project>\n' > "$YUDAO_DIR/yudao-dependencies/pom.xml"
create_nested_module "$YUDAO_DIR" "yudao-server" "yudao-server" "com/example/server" 150

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260601-010203 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$YUDAO_DIR" "deep" "main" "maven-static")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"

jq -e '.strategy == "semantic-cost-batching"' "$RUN_DIR/plan.json" >/dev/null
jq -e '.budget.target_batch_cost == 32000' "$RUN_DIR/plan.json" >/dev/null
jq -e '[.batches?] | length == 1' "$RUN_DIR/plan.json" >/dev/null 2>&1 || true

if jq -e '.planned_java_loc > 35000 or .planned_review_cost > 45000' "$RUN_DIR"/batches/batch-*.json >/dev/null; then
  echo "planner emitted an oversized batch" >&2
  exit 1
fi

if jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -Fxq "yudao-module-mes"; then
  echo "oversized top-level mes module must be split into smaller work units" >&2
  exit 1
fi

if jq -r 'select(.planned_java_loc < 5000) | .batch_id' "$RUN_DIR"/batches/batch-*.json | grep -q .; then
  echo "tiny tail batch should have been rebalanced or converted to context" >&2
  exit 1
fi

if jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -Fxq "yudao-dependencies"; then
  echo "zero LOC dependency module must not be a scan unit" >&2
  exit 1
fi

if jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -Fxq "yudao-server"; then
  echo "tiny bootstrap server module should be context, not scan unit" >&2
  exit 1
fi

jq -e '[.context_roots[]?] | length >= 1' "$RUN_DIR"/batches/batch-*.json >/dev/null
```

- [ ] **Step 3: Run the planner test and verify it fails**

Run:

```bash
bash tests/test_phase11_plan_large_batches.sh
```

Expected: FAIL because the current planner still emits top-level oversized batches and tiny tails.

- [ ] **Step 4: Commit the failing planner regression**

```bash
git add tests/test_phase11_plan_large_batches.sh
git commit -m "test: cover semantic large repo batch planning"
```

---

### Task 3: Implement Work Unit Generation

**Files:**
- Modify: `scripts/phase11-plan-large-batches.sh`
- Test: `tests/test_phase11_plan_large_batches.sh`

- [ ] **Step 1: Add review-cost constants**

Add near the existing LOC constants:

```bash
TARGET_BATCH_COST=32000
SOFT_MIN_BATCH_COST=18000
SOFT_MAX_BATCH_COST=38000
HARD_MAX_BATCH_COST=45000
TINY_BATCH_LOC=5000
TINY_BATCH_COST=8000
CONTEXT_COST_RATIO_PERCENT=25
```

- [ ] **Step 2: Add cost helpers**

Add:

```bash
review_cost() {
  local loc="$1"
  local files="$2"
  echo $((loc + files * 25))
}

is_tiny_scan_unit() {
  local loc="$1"
  local cost="$2"
  [ "$loc" -lt "$TINY_BATCH_LOC" ] && [ "$cost" -lt "$TINY_BATCH_COST" ]
}

is_over_hard_limit() {
  local loc="$1"
  local cost="$2"
  [ "$loc" -gt "$HARD_MAX_BATCH_LOC" ] || [ "$cost" -gt "$HARD_MAX_BATCH_COST" ]
}
```

- [ ] **Step 3: Add recursive module extraction**

Replace root-only module extraction with helpers that accept a POM path:

```bash
extract_modules_from_pom() {
  local pom_path="$1"
  perl -0ne '
    while (/<module>\s*([^<]+?)\s*<\/module>/g) {
      my $module = $1;
      $module =~ s/&amp;/&/g;
      $module =~ s/&lt;/</g;
      $module =~ s/&gt;/>/g;
      $module =~ s/&quot;/"/g;
      $module =~ s/&apos;/'\''/g;
      print "$module\n";
    }
  ' "$pom_path"
}

has_child_modules() {
  local module_dir="$1"
  [ -f "$module_dir/pom.xml" ] && extract_modules_from_pom "$module_dir/pom.xml" | grep -q .
}
```

- [ ] **Step 4: Add package unit discovery**

Add:

```bash
discover_package_units() {
  local module_name="$1"
  local module_path="$2"
  local java_root="$PROJECT_DIR/$module_path/src/main/java"
  [ -d "$java_root" ] || return 0

  find "$java_root" -mindepth 1 -maxdepth 3 -type d -print0 2>/dev/null |
    while IFS= read -r -d '' dir; do
      if find "$dir" -maxdepth 1 -name '*.java' -print -quit | grep -q .; then
        local rel="${dir#$PROJECT_DIR/}"
        local loc files cost unit_id
        loc="$(module_loc "$dir")"
        files="$(module_files "$dir")"
        cost="$(review_cost "$loc" "$files")"
        unit_id="package:${rel}"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$unit_id" "package" "$module_name:$rel" "$rel" "$loc" "$files" "$cost" "$module_name"
      fi
    done
}
```

- [ ] **Step 5: Build `units.tsv`**

Replace the current `MODULES_TSV` planning source with `UNITS_TSV`. Each row format is:

```text
unit_id<TAB>kind<TAB>name<TAB>path<TAB>loc<TAB>files<TAB>cost<TAB>parent_module<TAB>context_only<TAB>risk
```

Implementation rules:

```bash
# Pseudocode to translate directly into the script:
# for each root module:
#   compute loc/files/cost
#   if loc == 0: add context_only row
#   else if tiny and module name matches server|dependencies|bom: add context_only row
#   else if over hard and has child modules: add child submodule rows
#   else if over hard: add package rows
#   else: add module row
# after adding child rows, recursively split any child row still over hard by package roots
```

Use concrete `case` rules for context-only modules:

```bash
case "$module" in
  *dependencies*|*bom*|*-server|*server) context_only=true ;;
  *) context_only=false ;;
esac
```

- [ ] **Step 6: Emit plan budget fields**

In `plan.json`, change:

```json
"strategy": "maven-module-batching"
```

to:

```json
"strategy": "semantic-cost-batching"
```

and include:

```json
"budget": {
  "target_batch_loc": 25000,
  "soft_min_batch_loc": 15000,
  "soft_max_batch_loc": 30000,
  "hard_max_batch_loc": 35000,
  "target_batch_cost": 32000,
  "soft_min_batch_cost": 18000,
  "soft_max_batch_cost": 38000,
  "hard_max_batch_cost": 45000
}
```

- [ ] **Step 7: Run the focused planner test**

Run:

```bash
bash tests/test_phase11_plan_large_batches.sh
```

Expected: still FAIL because packing and JSON emission do not yet use `units`.

- [ ] **Step 8: Commit work-unit generation**

```bash
git add scripts/phase11-plan-large-batches.sh
git commit -m "feat: build semantic work units for large repo batches"
```

---

### Task 4: Implement Semantic-Cost Packing And Tail Rebalancing

**Files:**
- Modify: `scripts/phase11-plan-large-batches.sh`
- Test: `tests/test_phase11_plan_large_batches.sh`

- [ ] **Step 1: Add unit field accessors**

Add:

```bash
unit_field() {
  local unit_id="$1"
  local field="$2"
  awk -F '\t' -v unit_id="$unit_id" -v field="$field" '
    $1 == unit_id {
      if (field == "kind") print $2;
      else if (field == "name") print $3;
      else if (field == "path") print $4;
      else if (field == "loc") print $5;
      else if (field == "files") print $6;
      else if (field == "cost") print $7;
      else if (field == "parent") print $8;
      else if (field == "context_only") print $9;
      else if (field == "risk") print $10;
      exit
    }
  ' "$UNITS_TSV"
}
```

- [ ] **Step 2: Build affinity edges**

Add `UNIT_EDGES_TSV` rows:

```text
from_unit<TAB>to_unit<TAB>weight<TAB>reason
```

Use these deterministic static weights:

```text
same parent module: 80
Maven reactor dependency: 70
same top-level prefix: 50
bootstrap context to server dependency: 40
shared domain token: 30
```

The first implementation can add same-parent and shared-domain edges without waiting for jdtls.

- [ ] **Step 3: Replace module packing with unit packing**

Use this concrete loop structure:

```bash
ASSIGNED_UNITS="|"
BATCH_IDS=()

while has_unassigned_scan_units; do
  seed="$(next_unassigned_unit_by_risk)"
  CURRENT_UNITS=()
  CURRENT_CONTEXT_UNITS=()
  CURRENT_LOC=0
  CURRENT_FILES=0
  CURRENT_COST=0
  add_unit_to_batch "$seed"

  while candidate="$(best_affinity_candidate_under_soft_max)"; [ -n "$candidate" ]; do
    add_unit_to_batch "$candidate"
  done

  if [ "$CURRENT_LOC" -lt "$SOFT_MIN_BATCH_LOC" ] && [ "$CURRENT_COST" -lt "$SOFT_MIN_BATCH_COST" ]; then
    candidate="$(best_low_cost_candidate_under_hard_max)"
    [ -n "$candidate" ] && add_unit_to_batch "$candidate"
  fi

  validate_current_batch_not_over_hard
  write_current_batch
done
```

- [ ] **Step 4: Add bounded context roots**

For each batch, attach context-only units with affinity to the batch until:

```bash
context_cost <= CURRENT_COST * CONTEXT_COST_RATIO_PERCENT / 100
```

If a context-only unit is too large, skip it and rely on jdtls or module summaries rather than expanding the batch.

- [ ] **Step 5: Add tail rebalancing**

Before writing final batch JSON files, run:

```text
for each planned batch with loc < 5000 and cost < 8000:
  find target batch with highest affinity and hard-limit headroom
  if found: move its scan units into target and mark split_reason tail_rebalanced
  else if all units are tiny/bootstrap/dependency: move to context_roots of strongest batch
  else keep it and set split_reason tiny_batch_no_legal_merge
```

Keep this implementation simple by storing draft batches in temporary TSV rows before writing JSON:

```text
batch_id<TAB>unit_id
batch_id<TAB>context_unit_id
```

- [ ] **Step 6: Emit new batch JSON schema**

Each batch JSON must include:

```json
{
  "strategy": "semantic-cost-batching",
  "planned_review_cost": 31250,
  "planned_java_loc": 24800,
  "planned_java_file_count": 186,
  "scan_roots": [],
  "context_roots": [],
  "units": [],
  "affinity_edges": [],
  "split_reason": "dependency_affinity_group"
}
```

Keep a compatibility `modules` array with `{ "name": "...", "path": "..." }` entries generated from `units` so phase13 and older docs/tests continue to work during the transition.

- [ ] **Step 7: Run planner test**

Run:

```bash
bash tests/test_phase11_plan_large_batches.sh
```

Expected: PASS.

- [ ] **Step 8: Commit semantic packing**

```bash
git add scripts/phase11-plan-large-batches.sh tests/test_phase11_plan_large_batches.sh
git commit -m "feat: pack large repo batches by semantic cost"
```

---

### Task 5: Update Status, Merge, Skill, Agent, And Examples

**Files:**
- Modify: `scripts/phase13-show-large-batch-status.sh`
- Modify: `scripts/phase12-merge-large-batches.sh`
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `agents/cc-code-reviewer.md`
- Modify: `references/examples.md`
- Test: `tests/test_phase13_show_large_batch_status.sh`
- Test: `tests/test_contract_docs.sh`

- [ ] **Step 1: Update phase13 status display**

Teach `phase13-show-large-batch-status.sh` to read:

```text
planned_review_cost
units[].name
context_roots
split_reason
```

Fallback behavior:

```text
if units exists: display units names
else if modules exists: display modules names
else: display scan_roots
```

Keep internal enum labels hidden from user-facing output.

- [ ] **Step 2: Update phase13 test**

Extend `tests/test_phase13_show_large_batch_status.sh` fixture batch JSON:

```json
{
  "batch_id": "batch-001",
  "strategy": "semantic-cost-batching",
  "planned_review_cost": 31250,
  "planned_java_loc": 24800,
  "planned_java_file_count": 186,
  "context_roots": ["yudao-server"],
  "units": [
    {"name": "user-api", "path": "user-api"},
    {"name": "user-service", "path": "user-service"}
  ],
  "split_reason": "dependency_affinity_group"
}
```

Assert:

```bash
printf '%s\n' "$OUTPUT" | grep -q "user-api,user-service"
printf '%s\n' "$OUTPUT" | grep -q "dependency_affinity_group"
```

- [ ] **Step 3: Keep phase12 coverage file-based**

In `scripts/phase12-merge-large-batches.sh`, ensure summary wording and JSON continue to use Java files as the coverage denominator. Do not introduce LOC coverage as the primary metric. If the script displays LOC, label it as planning scale, not coverage.

- [ ] **Step 4: Update skill contract**

In `skills/cc-code-reviewer/SKILL.md`, replace the old planner description with:

```text
Maven 大仓库规划使用 semantic-cost batching：
- 先生成 work units，而不是直接把顶层 Maven module 当批次
- review_cost = java_loc + java_file_count * 25
- 超过 HARD_MAX_BATCH_LOC 或 HARD_MAX_BATCH_COST 的 unit 必须继续拆分
- 0 行依赖/BOM 模块与极小 bootstrap 模块默认进入 context_roots，不单独成批
- tiny tail batches 必须合并、转为 context，或写明无法合法合并的原因
- context_roots 只用于理解，不计入 Java 文件覆盖率
```

- [ ] **Step 5: Update agent contract**

In `agents/cc-code-reviewer.md`, add:

```text
批次计划中的 `units[].scan_roots` 和顶层 `scan_roots` 是正式审查边界。
`context_roots` 只能作为只读上下文使用，不得计入已审查 Java 文件，不得从 context_roots 产出正式问题。
正式问题必须定位在 scan_roots 内；context_roots 中发现的风险只能写入跨批依赖待复核。
```

- [ ] **Step 6: Update examples**

In `references/examples.md`, adjust the large Maven example table so no batch is above 35k and no tiny batch appears alone. Use a yudao-like example:

```text
batch-001 待执行 28,400 310 yudao-module-mes:production
batch-002 待执行 27,900 295 yudao-module-mes:quality,material
batch-003 待执行 26,800 276 yudao-module-mall:trade,statistics
batch-004 待执行 25,700 260 yudao-module-mall:promotion,product
batch-005 待执行 24,900 403 yudao-gateway,yudao-framework context:yudao-server
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
bash tests/test_phase13_show_large_batch_status.sh
bash tests/test_contract_docs.sh
```

Expected: PASS.

- [ ] **Step 8: Commit contract and display updates**

```bash
git add scripts/phase13-show-large-batch-status.sh scripts/phase12-merge-large-batches.sh skills/cc-code-reviewer/SKILL.md agents/cc-code-reviewer.md references/examples.md tests/test_phase13_show_large_batch_status.sh tests/test_contract_docs.sh
git commit -m "docs: update semantic large repo batch contract"
```

---

### Task 6: Run Full Verification And Clean Up

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
bash tests/test_phase11_plan_large_batches.sh
bash tests/test_phase13_show_large_batch_status.sh
bash tests/test_contract_docs.sh
```

Expected: all PASS.

- [ ] **Step 2: Run full suite**

Run:

```bash
bash tests/run_all.sh
```

Expected: all tests PASS, including `git diff --check`.

- [ ] **Step 3: Inspect generated yudao-like plan**

Run the planner test once and inspect the latest temporary failure output only if a test fails. If the test passes, manually run a local fixture only when needed. The final implementation must satisfy:

```text
no batch planned_java_loc > 35000
no batch planned_review_cost > 45000
no standalone batch below 5000 LOC unless split_reason=tiny_batch_no_legal_merge
no zero-LOC scan unit
context_roots present for bootstrap/dependency modules when applicable
strategy=semantic-cost-batching
```

- [ ] **Step 4: Check worktree**

Run:

```bash
git status --short
```

Expected: only intentional files changed. Do not revert unrelated pre-existing user changes.

- [ ] **Step 5: Final commit if needed**

If Tasks 1-5 were not committed one by one, create a final commit:

```bash
git add scripts/phase11-plan-large-batches.sh scripts/phase13-show-large-batch-status.sh scripts/phase12-merge-large-batches.sh skills/cc-code-reviewer/SKILL.md agents/cc-code-reviewer.md references/examples.md tests/test_phase11_plan_large_batches.sh tests/test_phase13_show_large_batch_status.sh tests/test_contract_docs.sh
git commit -m "feat: implement semantic large repo batching"
```

---

## Self-Review

- Spec coverage: covered work units, review cost, recursive oversized splitting, affinity packing, tail rebalancing, bounded context roots, Java-file coverage, skill/agent contracts, examples, and tests.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: canonical batch fields are `units`, `context_roots`, `planned_review_cost`, `affinity_edges`, and `strategy=semantic-cost-batching`; `modules` remains only as a compatibility alias.
