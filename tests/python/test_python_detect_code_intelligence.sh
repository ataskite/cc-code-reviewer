#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# detect-code-intelligence.sh 输出契约测试
D="$TMP_DIR/py-project"; mkdir -p "$D"
echo "" > "$D/pyproject.toml"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" "$D")"

# 无论是否安装 LSP，都必须输出这些字段
grep -qE 'CODE_INTELLIGENCE_AVAILABLE=(true|false)' <<< "$OUT"
grep -q 'CODE_INTELLIGENCE_LANGUAGE=python' <<< "$OUT"
grep -q 'CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT"

# 若可用，必须有 COMMAND 和 CAPABILITIES
if grep -q 'CODE_INTELLIGENCE_AVAILABLE=true' <<< "$OUT"; then
  grep -q 'CODE_INTELLIGENCE_COMMAND=' <<< "$OUT"
  grep -q 'CODE_INTELLIGENCE_CAPABILITIES=' <<< "$OUT"
  # provider 必须是已知值之一
  PROVIDER="$(grep '^CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT" | cut -d= -f2)"
  case "$PROVIDER" in
    pyright|pyright-cli|pylsp|jedi) ;;
    *) echo "FAIL: unknown provider $PROVIDER" >&2; exit 1 ;;
  esac
else
  # 不可用时必须有 REASON
  grep -q 'CODE_INTELLIGENCE_REASON=' <<< "$OUT"
fi

echo "PASS: python detect-code-intelligence"

# ── P2-2: pyright CLI（无 langserver）应只输出 diagnostics 能力 ──
# 用 mock binary 模拟只有 pyright CLI、没有 pyright-langserver 的环境
MOCK_BIN="$TMP_DIR/mock-bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/pyright" <<'EOF'
#!/bin/bash
# mock pyright CLI（仅类型检查，非 LSP）
exit 0
EOF
chmod +x "$MOCK_BIN/pyright"

D2="$TMP_DIR/py-cli-only"; mkdir -p "$D2"
echo "" > "$D2/pyproject.toml"

# 用 mock PATH 运行，确保只有 pyright CLI 被发现（不含 pyright-langserver/pylsp/jedi）
OUT2="$(PATH="$MOCK_BIN:/usr/bin:/bin" bash "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" "$D2")"

if grep -q 'CODE_INTELLIGENCE_AVAILABLE=true' <<< "$OUT2"; then
  grep -q 'CODE_INTELLIGENCE_PROVIDER=pyright-cli' <<< "$OUT2"
  CAPS="$(grep '^CODE_INTELLIGENCE_CAPABILITIES=' <<< "$OUT2" | cut -d= -f2)"
  # pyright CLI（非 langserver）应只含 diagnostics，不含 definition/references/hover
  if [ "$CAPS" != "diagnostics" ]; then
    echo "FAIL: pyright CLI 应只输出 diagnostics 能力，实际: $CAPS" >&2
    exit 1
  fi
fi

# 项目本地 node_modules/.bin/pyright-langserver 也必须优先识别为 LSP。
D3="$TMP_DIR/local-langserver"; mkdir -p "$D3/node_modules/.bin"
cat > "$D3/node_modules/.bin/pyright-langserver" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$D3/node_modules/.bin/pyright-langserver"
OUT_LOCAL="$(PATH="/usr/bin:/bin" bash "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" "$D3")"
# 精确匹配 provider=pyright（非 pyright-cli），避免子串匹配掩盖回归
LOCAL_PROVIDER="$(grep '^CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT_LOCAL" | cut -d= -f2)"
test "$LOCAL_PROVIDER" = "pyright"
grep -qF "CODE_INTELLIGENCE_COMMAND=$D3/node_modules/.bin/pyright-langserver --stdio" <<< "$OUT_LOCAL"
grep -q 'CODE_INTELLIGENCE_CAPABILITIES=.*definition' <<< "$OUT_LOCAL"

# Python 虚拟环境内的 pyright-langserver 也必须按完整 LSP 识别，不能降级成 CLI。
D_LOCAL_VENV="$TMP_DIR/local-venv-langserver"; mkdir -p "$D_LOCAL_VENV/.venv/bin"
cat > "$D_LOCAL_VENV/.venv/bin/pyright-langserver" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$D_LOCAL_VENV/.venv/bin/pyright-langserver"
OUT_LOCAL_VENV="$(PATH="/usr/bin:/bin" bash "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" "$D_LOCAL_VENV")"
VENV_PROVIDER="$(grep '^CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT_LOCAL_VENV" | cut -d= -f2)"
test "$VENV_PROVIDER" = "pyright"
grep -qF "CODE_INTELLIGENCE_COMMAND=$D_LOCAL_VENV/.venv/bin/pyright-langserver --stdio" <<< "$OUT_LOCAL_VENV"

# ── P2-2: pyright-langserver 应输出完整 LSP 能力 ──
cat > "$MOCK_BIN/pyright-langserver" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$MOCK_BIN/pyright-langserver"

OUT3="$(PATH="$MOCK_BIN:/usr/bin:/bin" bash "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" "$D2")"

if grep -q 'CODE_INTELLIGENCE_AVAILABLE=true' <<< "$OUT3"; then
  # 精确匹配 provider=pyright（langserver，非 pyright-cli）
  PROVIDER3="$(grep '^CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT3" | cut -d= -f2)"
  test "$PROVIDER3" = "pyright"
  CAPS3="$(grep '^CODE_INTELLIGENCE_CAPABILITIES=' <<< "$OUT3" | cut -d= -f2)"
  # pyright-langserver 应含 definition/references/diagnostics/type_info/hover
  echo "$CAPS3" | grep -q 'definition' || { echo "FAIL: pyright-langserver 应含 definition" >&2; exit 1; }
  echo "$CAPS3" | grep -q 'hover' || { echo "FAIL: pyright-langserver 应含 hover" >&2; exit 1; }
fi

# 完整项目 LSP 必须优先于全局 pyright CLI diagnostics。
D4="$TMP_DIR/pylsp-over-cli"; mkdir -p "$D4/.venv/bin"
CLI_ONLY_BIN="$TMP_DIR/cli-only-bin"; mkdir -p "$CLI_ONLY_BIN"
cat > "$CLI_ONLY_BIN/pyright" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$CLI_ONLY_BIN/pyright"
cat > "$D4/.venv/bin/pylsp" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$D4/.venv/bin/pylsp"
OUT4="$(PATH="$CLI_ONLY_BIN:/usr/bin:/bin" bash "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" "$D4")"
PROVIDER4="$(grep '^CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT4" | cut -d= -f2)"
test "$PROVIDER4" = "pylsp"
grep -qF "CODE_INTELLIGENCE_COMMAND=$D4/.venv/bin/pylsp" <<< "$OUT4"

echo "PASS: python detect-code-intelligence pyright CLI vs LSP"
