#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/tests"

echo "== cc-code-reviewer test suite =="
echo "Root: $ROOT_DIR"
echo ""

# 递归发现所有子目录下的 test_*.sh，保证 tests/java、tests/core、tests/frontend 被纳入
while IFS= read -r -d '' test_file; do
  test_name="${test_file#$TEST_DIR/}"
  echo "==> $test_name"
  bash "$test_file"
  echo "    ok"
done < <(find "$TEST_DIR" -type f -name 'test_*.sh' -print0 | sort -z)

echo ""
echo "==> git diff --check"
git -C "$ROOT_DIR" diff --check
echo "    ok"

echo ""
echo "✅ All tests passed."
