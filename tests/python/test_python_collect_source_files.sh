#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 测试：collect-source-files 正确排除 tests/venv/__pycache__/migrations ──
D="$TMP_DIR/myapp"; mkdir -p "$D/src/myapp" "$D/src/myapp/migrations" "$D/tests" "$D/venv/lib"
echo "" > "$D/src/myapp/__init__.py"
echo "print('main')" > "$D/src/myapp/main.py"
echo "print('utils')" > "$D/src/myapp/utils.py"
echo "# migration" > "$D/src/myapp/migrations/0001_initial.py"
echo "def test_main(): pass" > "$D/tests/test_main.py"
echo "# venv file" > "$D/venv/lib/site.py"
mkdir -p "$D/src/myapp/__pycache__"
echo "cached" > "$D/src/myapp/__pycache__/main.cpython-310.pyc"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D")"

# 必须包含生产 .py
echo "$OUT" | grep -q '/src/myapp/main.py'
echo "$OUT" | grep -q '/src/myapp/utils.py'
echo "$OUT" | grep -q '/src/myapp/__init__.py'

# 必须排除 tests/migrations/venv/__pycache__
echo "$OUT" | grep -vq '/tests/'
echo "$OUT" | grep -vq '/migrations/'
echo "$OUT" | grep -vq '/venv/'
echo "$OUT" | grep -vq '/__pycache__/'

# 必须正好 3 个文件
COUNT="$(echo "$OUT" | grep -c .)"
test "$COUNT" -eq 3

# ── 测试：flat layout（无 src/，顶层包）──
D2="$TMP_DIR/flat-app"; mkdir -p "$D2/mypkg" "$D2/tests"
echo "" > "$D2/mypkg/__init__.py"
echo "print('core')" > "$D2/mypkg/core.py"
echo "def test(): pass" > "$D2/tests/test_core.py"

OUT2="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D2")"
echo "$OUT2" | grep -q '/mypkg/core.py'
echo "$OUT2" | grep -vq '/tests/'

echo "PASS: python collect-source-files"
