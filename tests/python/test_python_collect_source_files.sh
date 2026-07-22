#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 测试：collect-source-files 正确排除 tests/venv/__pycache__/migrations ──
D="$TMP_DIR/myapp"; mkdir -p "$D/src/myapp" "$D/src/myapp/migrations" "$D/src/myapp/tests" "$D/tests" "$D/venv/lib"
echo "" > "$D/src/myapp/__init__.py"
echo "print('main')" > "$D/src/myapp/main.py"
echo "print('utils')" > "$D/src/myapp/utils.py"
echo "# migration" > "$D/src/myapp/migrations/0001_initial.py"
echo "class Factory: pass" > "$D/src/myapp/tests/factories.py"
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

# ── 测试：namespace package（无 __init__.py，PEP 420）──
D3="$TMP_DIR/ns-app"; mkdir -p "$D3/myapp/api" "$D3/myapp/models"
cat > "$D3/pyproject.toml" <<'EOF'
[project]
name = "myapp"
EOF
echo "def route(): pass" > "$D3/myapp/api/routes.py"
echo "def model(): pass" > "$D3/myapp/models/user.py"

OUT3="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D3")"
# namespace package 必须被识别，不再返回空
test -n "$OUT3"
echo "$OUT3" | grep -q '/myapp/api/routes.py'
echo "$OUT3" | grep -q '/myapp/models/user.py'

# ── 测试：根级单文件应用（app.py 入口，无 src 无包）──
D4="$TMP_DIR/single-app"
mkdir -p "$D4"
echo "import sys" > "$D4/app.py"
echo "import pytest" > "$D4/conftest.py"  # conftest 不应被收集

OUT4="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D4")"
echo "$OUT4" | grep -q '/app.py'
echo "$OUT4" | grep -vq '/conftest.py'
COUNT4="$(echo "$OUT4" | grep -c .)"
test "$COUNT4" -eq 1

# ── 测试：flat layout 包不重复扫描（顶层包 myapp + 子目录 myapp/api 不应重复）──
D5="$TMP_DIR/dup-app"; mkdir -p "$D5/myapp/api" "$D5/myapp/models"
echo "" > "$D5/myapp/__init__.py"
echo "" > "$D5/myapp/api/__init__.py"
echo "def route(): pass" > "$D5/myapp/api/routes.py"
echo "def model(): pass" > "$D5/myapp/models/user.py"

OUT5="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D5")"
# 4 个文件，不重复（__init__.py x2 + routes.py + user.py）
COUNT5="$(echo "$OUT5" | grep -c .)"
test "$COUNT5" -eq 4
# 去重验证：sort -u 后数量不变
COUNT5_UNIQ="$(echo "$OUT5" | sort -u | grep -c .)"
test "$COUNT5" -eq "$COUNT5_UNIQ"

# ── 测试：根级入口与 flat 包必须共存（FastAPI 常见 main.py + app/）──
D6="$TMP_DIR/main-plus-package"; mkdir -p "$D6/app/api"
echo "from app.api.routes import router" > "$D6/main.py"
echo "" > "$D6/app/__init__.py"
echo "router = object()" > "$D6/app/api/routes.py"

OUT6="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D6")"
echo "$OUT6" | grep -q '/main.py'
echo "$OUT6" | grep -q '/app/api/routes.py'
COUNT6="$(echo "$OUT6" | grep -c .)"
test "$COUNT6" -eq 3

# ── 测试：无包的通用根级脚本也应成为正式源码 ──
D7="$TMP_DIR/generic-cli"; mkdir -p "$D7"
echo "def main(): pass" > "$D7/cli.py"
echo "from setuptools import setup" > "$D7/setup.py"
echo "def test_cli(): pass" > "$D7/test_cli.py"

OUT7="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D7")"
echo "$OUT7" | grep -q '/cli.py'
echo "$OUT7" | grep -vq '/setup.py'
echo "$OUT7" | grep -vq '/test_cli.py'
COUNT7="$(echo "$OUT7" | grep -c .)"
test "$COUNT7" -eq 1

# ── 测试：项目路径含 /test/ 段不被误杀（回归 P0 bug）──
# 旧版用 -not -path '*/test/*' 会误杀路径中任何 test 段，导致 manifest 为空。
D8="$TMP_DIR/proj/test/backend"; mkdir -p "$D8/src/myapp"
echo "" > "$D8/src/myapp/__init__.py"
echo "x = 1" > "$D8/src/myapp/views.py"

OUT8="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D8")"
echo "$OUT8" | grep -q '/src/myapp/views.py'
echo "$OUT8" | grep -q '/src/myapp/__init__.py'
COUNT8="$(echo "$OUT8" | grep -c .)"
test "$COUNT8" -eq 2

# ── 测试：路径含 /tests/ 段同样不被误杀 ──
D9="$TMP_DIR/proj/tests/backend"; mkdir -p "$D9/src/myapp"
echo "" > "$D9/src/myapp/__init__.py"
echo "x = 1" > "$D9/src/myapp/views.py"

OUT9="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D9")"
echo "$OUT9" | grep -q '/src/myapp/views.py'
COUNT9="$(echo "$OUT9" | grep -c .)"
test "$COUNT9" -eq 2

# ── 测试：项目祖先路径含 /build/ 或 /dist/ 不得误杀扫描根 ──
D10="$TMP_DIR/workspace/build/backend"; mkdir -p "$D10/src/myapp"
echo "" > "$D10/src/myapp/__init__.py"
echo "x = 1" > "$D10/src/myapp/service.py"
OUT10="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D10")"
echo "$OUT10" | grep -q '/src/myapp/service.py'
test "$(echo "$OUT10" | grep -c .)" -eq 2

D11="$TMP_DIR/workspace/dist/backend"; mkdir -p "$D11/src/myapp"
echo "x = 1" > "$D11/src/myapp/main.py"
OUT11="$(bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$D11")"
echo "$OUT11" | grep -q '/src/myapp/main.py'

echo "PASS: python collect-source-files"
