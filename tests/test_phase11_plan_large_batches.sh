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
    <module>svc space</module>
    <module>svc&amp;core</module>
  </modules>
</project>
XML

validate_json_file() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq empty "$file"
  else
    perl -MJSON::PP -0777 -ne 'decode_json($_)' "$file"
  fi
}

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
create_module "svc space" "svc-space" "" 10
create_module "svc&core" "svc-core" "" 10

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260528-010203 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$PROJECT_DIR" "standard" "main" "jdtls-lsp")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"
RUN_ID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_ID=//p')"

test "$RUN_ID" = "20260528-010203-main-standard"
test "$(basename "$RUN_DIR")" = "$RUN_ID"
test -f "$RUN_DIR/plan.json"
test -f "$RUN_DIR/batches/batch-001.json"
test -f "$RUN_DIR/results/batch-001.status.json"
test -f "$RUN_DIR/progress.jsonl"

validate_json_file "$RUN_DIR/plan.json"
for json_file in "$RUN_DIR"/batches/*.json "$RUN_DIR"/results/*.status.json; do
  validate_json_file "$json_file"
done

jq -e '.strategy == "semantic-cost-batching"' "$RUN_DIR/plan.json" >/dev/null
grep -q '"semantic_level": "jdtls-lsp"' "$RUN_DIR/plan.json"
grep -q '"status": "pending"' "$RUN_DIR/results/batch-001.status.json"
grep -q '"scan_roots"' "$RUN_DIR/batches/batch-001.json"
grep -q '"order-api"' "$RUN_DIR/batches/batch-001.json"
grep -q '"order-service"' "$RUN_DIR/batches/batch-001.json"
grep -q '"order-dao"' "$RUN_DIR/batches/batch-001.json"
grep -q '"from": "maven-module:order-api"' "$RUN_DIR/batches/batch-001.json"
grep -q '"to": "maven-module:order-service"' "$RUN_DIR/batches/batch-001.json"
grep -q '"svc space"' "$RUN_DIR"/batches/*.json
grep -q '"svc&core"' "$RUN_DIR"/batches/*.json
if grep -q 'files.txt\|reviewed_java_files\|remaining_files' "$RUN_DIR"/batches/*.json "$RUN_DIR"/results/*.status.json; then
  echo "planner must not create file manifests or file-level reviewed state" >&2
  exit 1
fi

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

if jq -e 'select(.planned_java_loc > 35000 or .planned_review_cost > 45000)' "$RUN_DIR"/batches/batch-*.json >/dev/null; then
  echo "planner emitted an oversized batch" >&2
  exit 1
fi

if jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -Fxq "yudao-module-mes"; then
  echo "oversized top-level mes module must be split into smaller work units" >&2
  exit 1
fi
for expected_unit in \
  "yudao-module-mes:com/example/mes/server/production" \
  "yudao-module-mes:com/example/mes/server/quality" \
  "yudao-module-mes:com/example/mes/server/material"; do
  if ! jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -Fxq "$expected_unit"; then
    echo "oversized mes server package unit missing: $expected_unit" >&2
    exit 1
  fi
done

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

if jq -e 'select((.context_roots // []) | length == 0)' "$RUN_DIR"/batches/batch-*.json >/dev/null; then
  echo "each semantic batch must declare bounded context_roots" >&2
  exit 1
fi
if jq -r '.split_reason' "$RUN_DIR"/batches/batch-*.json | grep -qE '^[0-9]+$'; then
  echo "batch split_reason must be a reason string, not a numeric review cost" >&2
  exit 1
fi
if ! jq -r '.split_reason' "$RUN_DIR"/batches/batch-*.json | grep -qE 'oversized_module_package_split|maven_module|tiny_tail_context'; then
  echo "semantic batch split_reason should expose planner reasoning" >&2
  exit 1
fi

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260601-020203 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$YUDAO_DIR" "deep" "main" "maven-static" "yudao-module-mall")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"

jq -e '.review_scope == "yudao-module-mall"' "$RUN_DIR/plan.json" >/dev/null
jq -e '.selected_modules == ["yudao-module-mall"]' "$RUN_DIR/plan.json" >/dev/null
if jq -r '.scan_roots[]' "$RUN_DIR"/batches/batch-*.json | grep -v '^yudao-module-mall/' | grep -q .; then
  echo "selected-module smart batching must keep scan_roots inside the selected module" >&2
  exit 1
fi
if jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -q "yudao-module-mes"; then
  echo "selected-module smart batching must not include unselected module units" >&2
  exit 1
fi

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260601-030203 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$YUDAO_DIR" "deep" "main" "maven-static" "yudao-module-mes,yudao-framework" "module-sequential")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"

jq -e '.strategy == "module-sequential-batching"' "$RUN_DIR/plan.json" >/dev/null
jq -e '.selected_modules == ["yudao-module-mes", "yudao-framework"]' "$RUN_DIR/plan.json" >/dev/null
jq -e '.batch_count == 2' "$RUN_DIR/plan.json" >/dev/null
jq -e 'select(.split_reason == "module_sequential_user_selected")' "$RUN_DIR"/batches/batch-*.json >/dev/null
if ! jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -Fxq "yudao-module-mes"; then
  echo "module-sequential batching must keep the selected oversized module as one batch" >&2
  exit 1
fi
if ! jq -e 'select(.large_batch == true and (.units[].name == "yudao-module-mes"))' "$RUN_DIR"/batches/batch-*.json >/dev/null; then
  echo "module-sequential oversized modules must be flagged but not blocked" >&2
  exit 1
fi

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260601-040203 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$YUDAO_DIR" "deep" "main" "maven-static" "yudao-module-mall" "module-sequential")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"
RUN_ID="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_ID=//p')"

test "$RUN_ID" = "20260601-040203-main-deep"
test "$(basename "$RUN_DIR")" = "$RUN_ID"
jq -e '.strategy == "module-sequential-batching"' "$RUN_DIR/plan.json" >/dev/null
jq -e '.review_scope == "yudao-module-mall"' "$RUN_DIR/plan.json" >/dev/null
jq -e '.selected_modules == ["yudao-module-mall"]' "$RUN_DIR/plan.json" >/dev/null
jq -e '.batch_count == 1' "$RUN_DIR/plan.json" >/dev/null
if jq -r '.scan_roots[]' "$RUN_DIR"/batches/batch-*.json | grep -v '^yudao-module-mall$' | grep -q .; then
  echo "single selected module-sequential batch must not include other module scan_roots" >&2
  exit 1
fi
if jq -r '.units[].name? // empty' "$RUN_DIR"/batches/batch-*.json | grep -v '^yudao-module-mall$' | grep -q .; then
  echo "single selected module-sequential batch must only include the selected module unit" >&2
  exit 1
fi

OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260528-020304 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$PROJECT_DIR" "standard" "main" "maven-static")"
RUN_DIR="$(printf '%s\n' "$OUTPUT" | sed -n 's/^RUN_DIR=//p')"
grep -q '"semantic_level": "maven-static"' "$RUN_DIR/plan.json"

STATUS_COUNT="$(find "$RUN_DIR/results" -name 'batch-*.status.json' | wc -l | tr -d ' ')"
BATCH_COUNT="$(sed -n 's/.*"batch_count": \([0-9][0-9]*\).*/\1/p' "$RUN_DIR/plan.json" | head -1)"
test "$STATUS_COUNT" = "$BATCH_COUNT"

MISSING_PROJECT_DIR="$TMP_DIR/missing-modules"
mkdir -p "$MISSING_PROJECT_DIR"
cat > "$MISSING_PROJECT_DIR/pom.xml" <<'XML'
<project>
  <modules>
    <module>missing-one</module>
    <module>missing-two</module>
  </modules>
</project>
XML

set +e
MISSING_OUTPUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260528-030405 bash "$ROOT_DIR/scripts/phase11-plan-large-batches.sh" "$MISSING_PROJECT_DIR" "standard" "main" "maven-static" 2>&1)"
MISSING_STATUS=$?
set -e
test "$MISSING_STATUS" -ne 0
printf '%s\n' "$MISSING_OUTPUT" | grep -q 'NO_MAVEN_MODULES'
if printf '%s\n' "$MISSING_OUTPUT" | grep -q 'modules.risk.tsv'; then
  echo "planner leaked internal risk TSV error for empty module set" >&2
  exit 1
fi

echo "PASS: phase11 large Maven batch planner"
