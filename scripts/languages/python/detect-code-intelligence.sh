#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "CODE_INTELLIGENCE_AVAILABLE=false"; echo "CODE_INTELLIGENCE_REASON=project-dir-not-found"; exit 0; }

# 探测 Python LSP / 类型检查器。优先级：pyright language server
# > pylsp(python-lsp-server) > jedi > pyright CLI > none。完整 LSP 始终优先于
# 只有 diagnostics 的 CLI；CLI 与 LSP 必须用不同 provider，
# 避免上层把只有 diagnostics 的 pyright CLI 当成 definition/references LSP。
# 输出 PROFILE_SCHEMA 兼容的 CODE_INTELLIGENCE_* key=value。

detect_pyright_langserver() {
  command -v pyright-langserver >/dev/null 2>&1 && return 0
  [ -x "$PROJECT_DIR/node_modules/.bin/pyright-langserver" ] && return 0
  [ -x "$PROJECT_DIR/.venv/bin/pyright-langserver" ] && return 0
  [ -x "$PROJECT_DIR/venv/bin/pyright-langserver" ] && return 0
  return 1
}

detect_pyright_cli() {
  command -v pyright >/dev/null 2>&1 && return 0
  [ -x "$PROJECT_DIR/node_modules/.bin/pyright" ] && return 0
  [ -x "$PROJECT_DIR/.venv/bin/pyright" ] && return 0
  [ -x "$PROJECT_DIR/venv/bin/pyright" ] && return 0
  return 1
}

detect_pylsp() {
  command -v pylsp >/dev/null 2>&1 && return 0
  # venv 内
  [ -x "$PROJECT_DIR/.venv/bin/pylsp" ] && return 0
  [ -x "$PROJECT_DIR/venv/bin/pylsp" ] && return 0
  return 1
}

detect_jedi() {
  command -v jedi-language-server >/dev/null 2>&1 && return 0
  [ -x "$PROJECT_DIR/.venv/bin/jedi-language-server" ] && return 0
  [ -x "$PROJECT_DIR/venv/bin/jedi-language-server" ] && return 0
  return 1
}

if detect_pyright_langserver; then
  if command -v pyright-langserver >/dev/null 2>&1; then
    CMD="pyright-langserver --stdio"
  elif [ -x "$PROJECT_DIR/node_modules/.bin/pyright-langserver" ]; then
    CMD="$PROJECT_DIR/node_modules/.bin/pyright-langserver --stdio"
  elif [ -x "$PROJECT_DIR/.venv/bin/pyright-langserver" ]; then
    CMD="$PROJECT_DIR/.venv/bin/pyright-langserver --stdio"
  else
    CMD="$PROJECT_DIR/venv/bin/pyright-langserver --stdio"
  fi
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=python"
  echo "CODE_INTELLIGENCE_PROVIDER=pyright"
  echo "CODE_INTELLIGENCE_COMMAND=$CMD"
  echo "CODE_INTELLIGENCE_CAPABILITIES=definition,references,diagnostics,type_info,hover"
  exit 0
fi

if detect_pylsp; then
  if command -v pylsp >/dev/null 2>&1; then
    CMD="pylsp"
  elif [ -x "$PROJECT_DIR/.venv/bin/pylsp" ]; then
    CMD="$PROJECT_DIR/.venv/bin/pylsp"
  else
    CMD="$PROJECT_DIR/venv/bin/pylsp"
  fi
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=python"
  echo "CODE_INTELLIGENCE_PROVIDER=pylsp"
  echo "CODE_INTELLIGENCE_COMMAND=$CMD"
  echo "CODE_INTELLIGENCE_CAPABILITIES=definition,references,diagnostics,completion"
  exit 0
fi

if detect_jedi; then
  if command -v jedi-language-server >/dev/null 2>&1; then
    CMD="jedi-language-server"
  elif [ -x "$PROJECT_DIR/.venv/bin/jedi-language-server" ]; then
    CMD="$PROJECT_DIR/.venv/bin/jedi-language-server"
  else
    CMD="$PROJECT_DIR/venv/bin/jedi-language-server"
  fi
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=python"
  echo "CODE_INTELLIGENCE_PROVIDER=jedi"
  echo "CODE_INTELLIGENCE_COMMAND=$CMD"
  echo "CODE_INTELLIGENCE_CAPABILITIES=definition,references,diagnostics,completion"
  exit 0
fi

if detect_pyright_cli; then
  if command -v pyright >/dev/null 2>&1; then
    CMD="pyright"
  elif [ -x "$PROJECT_DIR/node_modules/.bin/pyright" ]; then
    CMD="$PROJECT_DIR/node_modules/.bin/pyright"
  elif [ -x "$PROJECT_DIR/.venv/bin/pyright" ]; then
    CMD="$PROJECT_DIR/.venv/bin/pyright"
  else
    CMD="$PROJECT_DIR/venv/bin/pyright"
  fi
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=python"
  echo "CODE_INTELLIGENCE_PROVIDER=pyright-cli"
  echo "CODE_INTELLIGENCE_COMMAND=$CMD"
  echo "CODE_INTELLIGENCE_CAPABILITIES=diagnostics"
  exit 0
fi

echo "CODE_INTELLIGENCE_AVAILABLE=false"
echo "CODE_INTELLIGENCE_LANGUAGE=python"
echo "CODE_INTELLIGENCE_PROVIDER=none"
echo "CODE_INTELLIGENCE_REASON=no-pyright-pylsp-jedi-found"
echo "CODE_INTELLIGENCE_HINT=安装 pyright（npm i -g pyright）或 python-lsp-server（pip install python-lsp-server）启用语义增强"
exit 0
