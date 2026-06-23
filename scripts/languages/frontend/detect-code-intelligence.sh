#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"

emit_unavailable() {
  echo "CODE_INTELLIGENCE_AVAILABLE=false"
  echo "CODE_INTELLIGENCE_LANGUAGE=frontend"
  echo "CODE_INTELLIGENCE_PROVIDER=none"
  echo "CODE_INTELLIGENCE_REASON=$1"
  echo "CODE_INTELLIGENCE_INSTALL_HINT=建议启用 TypeScript LSP（如 typescript-language-server）以获得定义/引用/调用链语义增强；不可用时回退 import graph + 配置 + 文本检索静态分析"
}

# 项目路径不存在 → 降级输出，不崩溃
if [ ! -d "$PROJECT_DIR" ]; then
  emit_unavailable "项目路径不存在"
  exit 0
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# TypeScript LSP 检测：全局 typescript-language-server 或本地 node_modules/.bin/tsserver
TS_LSP=""
if command -v typescript-language-server >/dev/null 2>&1; then
  TS_LSP="typescript-language-server"
elif [ -x "$PROJECT_DIR/node_modules/.bin/tsserver" ]; then
  TS_LSP="node_modules/.bin/tsserver"
fi

if [ -n "$TS_LSP" ]; then
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=frontend"
  echo "CODE_INTELLIGENCE_PROVIDER=typescript-lsp"
  echo "CODE_INTELLIGENCE_COMMAND=$TS_LSP"
  echo "CODE_INTELLIGENCE_CAPABILITIES=definition,references,implementations,diagnostics"
else
  emit_unavailable "未检测到 typescript-language-server 或本地 tsserver"
fi
exit 0
