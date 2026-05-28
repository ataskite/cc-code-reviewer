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

echo "PASS: phase11 large Maven batch planner"
