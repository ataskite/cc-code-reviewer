#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/tests"

echo "== cc-code-reviewer test suite =="
echo "Root: $ROOT_DIR"
echo ""

for test_file in "$TEST_DIR"/test_*.sh; do
  test_name="$(basename "$test_file")"
  echo "==> $test_name"
  bash "$test_file"
  echo "    ok"
done

echo ""
echo "==> git diff --check"
git -C "$ROOT_DIR" diff --check
echo "    ok"

echo ""
echo "All tests passed."
