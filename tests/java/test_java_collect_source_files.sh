#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/java-source-manifest.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/a/src/main/java/demo" "$TMP_DIR/a/src/test/java/demo" "$TMP_DIR/a/target/generated" "$TMP_DIR/b/src/main/java/demo"
printf 'class A {}\n' > "$TMP_DIR/a/src/main/java/demo/A.java"
printf 'class ATest {}\n' > "$TMP_DIR/a/src/test/java/demo/ATest.java"
printf 'class Generated {}\n' > "$TMP_DIR/a/target/generated/Generated.java"
printf 'class B {}\n' > "$TMP_DIR/b/src/main/java/demo/B.java"

FULL="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR")"
test "$(printf '%s\n' "$FULL" | wc -l | tr -d ' ')" = 2
printf '%s\n' "$FULL" | grep -q '/a/src/main/java/demo/A.java'
printf '%s\n' "$FULL" | grep -q '/b/src/main/java/demo/B.java'

SCOPED="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR" a)"
test "$(printf '%s\n' "$SCOPED" | wc -l | tr -d ' ')" = 1
printf '%s\n' "$SCOPED" | grep -q '/a/src/main/java/demo/A.java'

set +e
OUT="$(bash "$ROOT_DIR/scripts/languages/java/collect-source-files.sh" "$TMP_DIR" ../outside 2>&1)"
STATUS=$?
set -e
test "$STATUS" -ne 0
printf '%s\n' "$OUT" | grep -q 'INVALID_SCOPE_PATH'

echo "PASS: java collect-source-files"
