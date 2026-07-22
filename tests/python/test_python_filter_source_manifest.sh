#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/py-filter.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 场景 1: flat layout（无 src/，顶层包 myapp 含 api/models/services 子目录）──
W1="$TMP_DIR/flat-app"
mkdir -p "$W1/myapp/api" "$W1/myapp/models" "$W1/myapp/services"
echo "" > "$W1/myapp/__init__.py"
echo "" > "$W1/myapp/api/__init__.py"
echo "def route(): pass" > "$W1/myapp/api/routes.py"
echo "def model(): pass" > "$W1/myapp/models/user.py"
echo "def auth(): pass" > "$W1/myapp/services/auth.py"
W1="$(cd "$W1" && pwd -P)"

MANIFEST1="$TMP_DIR/flat-manifest.txt"
bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$W1" > "$MANIFEST1"

# 短名 api：应匹配 myapp/api/ 下文件（flat layout 短名扩展）
OUT1A="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W1" "$MANIFEST1" "api")"
grep -F "$W1/myapp/api/routes.py" <<< "$OUT1A"
! grep -F "$W1/myapp/models/user.py" <<< "$OUT1A"
! grep -F "$W1/myapp/services/auth.py" <<< "$OUT1A"

# 完整 flat 路径 myapp/api：精确匹配
OUT1B="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W1" "$MANIFEST1" "myapp/api")"
grep -F "$W1/myapp/api/routes.py" <<< "$OUT1B"
! grep -F "$W1/myapp/models/user.py" <<< "$OUT1B"

# 多目录 myapp/api,myapp/models
OUT1C="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W1" "$MANIFEST1" "myapp/api,myapp/models")"
grep -F "$W1/myapp/api/routes.py" <<< "$OUT1C"
grep -F "$W1/myapp/models/user.py" <<< "$OUT1C"
! grep -F "$W1/myapp/services/auth.py" <<< "$OUT1C"

# ── 场景 2: src layout（短名匹配 src/api）──
W2="$TMP_DIR/src-app"
mkdir -p "$W2/src/api" "$W2/src/models"
echo "def route(): pass" > "$W2/src/api/routes.py"
echo "def model(): pass" > "$W2/src/models/user.py"
W2="$(cd "$W2" && pwd -P)"

MANIFEST2="$TMP_DIR/src-manifest.txt"
bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$W2" > "$MANIFEST2"

# 短名 api：应匹配 src/api/
OUT2A="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W2" "$MANIFEST2" "api")"
grep -F "$W2/src/api/routes.py" <<< "$OUT2A"
! grep -F "$W2/src/models/user.py" <<< "$OUT2A"

# 完整 src 路径 src/api
OUT2B="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W2" "$MANIFEST2" "src/api")"
grep -F "$W2/src/api/routes.py" <<< "$OUT2B"
! grep -F "$W2/src/models/user.py" <<< "$OUT2B"

# ── 场景 3: 全量代码（不过滤）──
OUT3="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W2" "$MANIFEST2" "全量代码")"
test "$OUT3" = "$(cat "$MANIFEST2")"

# ── 场景 4: 路径穿越拒绝 ──
if bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W2" "$MANIFEST2" "../etc" 2>/dev/null; then
  echo "FAIL: 路径穿越应被拒绝" >&2
  exit 1
fi

if bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W2" "$MANIFEST2" "/etc/passwd" 2>/dev/null; then
  echo "FAIL: 绝对路径应被拒绝" >&2
  exit 1
fi

# ── 场景 5: 空结果报错 ──
if bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W2" "$MANIFEST2" "unknown_dir" 2>/dev/null; then
  echo "FAIL: 无匹配文件应报错退出" >&2
  exit 1
fi

# 验证空结果错误信息
ERR5="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W2" "$MANIFEST2" "unknown_dir" 2>&1 >/dev/null || true)"
echo "$ERR5" | grep -q "NO_PYTHON_SOURCE_FILES_AFTER_SCOPE"

# ── 场景 6: monorepo（多子项目根）── 选择单个子项目 ──
W6="$TMP_DIR/monorepo-app"
mkdir -p "$W6/services/api/src" "$W6/services/worker" "$W6/packages/shared"
cat > "$W6/services/api/pyproject.toml" <<'EOF'
[project]
name = "api"
EOF
cat > "$W6/services/worker/pyproject.toml" <<'EOF'
[project]
name = "worker"
EOF
cat > "$W6/packages/shared/pyproject.toml" <<'EOF'
[project]
name = "shared"
EOF
echo 'def route(): pass' > "$W6/services/api/src/routes.py"
echo 'def main(): pass' > "$W6/services/api/src/main.py"
echo 'def task(): pass' > "$W6/services/worker/tasks.py"
echo 'def helper(): pass' > "$W6/packages/shared/helpers.py"
W6="$(cd "$W6" && pwd -P)"

MANIFEST6="$TMP_DIR/monorepo-manifest.txt"
bash "$ROOT_DIR/scripts/languages/python/collect-source-files.sh" "$W6" > "$MANIFEST6"

# 选择 services/api：只命中该子项目的 2 个文件
OUT6A="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W6" "$MANIFEST6" "services/api")"
grep -F "$W6/services/api/src/routes.py" <<< "$OUT6A"
grep -F "$W6/services/api/src/main.py" <<< "$OUT6A"
! grep -F "$W6/services/worker/tasks.py" <<< "$OUT6A"
! grep -F "$W6/packages/shared/helpers.py" <<< "$OUT6A"

# 多选 services/api + services/worker
OUT6B="$(bash "$ROOT_DIR/scripts/languages/python/filter-source-manifest.sh" "$W6" "$MANIFEST6" "services/api,services/worker")"
grep -F "$W6/services/api/src/routes.py" <<< "$OUT6B"
grep -F "$W6/services/worker/tasks.py" <<< "$OUT6B"
! grep -F "$W6/packages/shared/helpers.py" <<< "$OUT6B"

echo "PASS: python filter-source-manifest"
