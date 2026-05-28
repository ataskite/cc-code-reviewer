#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"

JDTLS_INSTALLED=false
JDTLS_READY=false
PLUGIN_INSTALLED=false

emit_unavailable() {
  echo "CODE_INTELLIGENCE_AVAILABLE=false"
  echo "CODE_INTELLIGENCE_LANGUAGE=java"
  echo "CODE_INTELLIGENCE_PROVIDER=none"
  echo "CODE_INTELLIGENCE_JDTLS_INSTALLED=${JDTLS_INSTALLED:-false}"
  echo "CODE_INTELLIGENCE_JDTLS_READY=${JDTLS_READY:-false}"
  echo "CODE_INTELLIGENCE_PLUGIN_INSTALLED=${PLUGIN_INSTALLED:-false}"
  echo "CODE_INTELLIGENCE_REASON=$1"
  echo "CODE_INTELLIGENCE_INSTALL_HINT=建议安装 jdtls 并启用 Claude Code jdtls-lsp 插件；不可用时将回退到 Maven 静态依赖分批"
}

is_java_project() {
  [ -f "$PROJECT_DIR/pom.xml" ] ||
    find "$PROJECT_DIR" -maxdepth 1 -name 'build.gradle*' -type f -print -quit 2>/dev/null | grep -q . ||
    find "$PROJECT_DIR" \
      \( -path '*/target/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune -o \
      -name '*.java' -print -quit 2>/dev/null | grep -q .
}

plugin_installed() {
  local roots="${CLAUDE_CODE_PLUGIN_ROOTS:-}"
  local root
  local home_dir="${HOME:-}"

  if [ -n "$roots" ]; then
    IFS=':' read -r -a root_array <<< "$roots"
    for root in "${root_array[@]}"; do
      [ -z "$root" ] && continue
      [ -d "$root/jdtls-lsp" ] && return 0
      [ -d "$root/claude-plugins-official/jdtls-lsp" ] && return 0
    done
  fi

  [ -n "$home_dir" ] && [ -d "$home_dir/.claude/plugins/data/jdtls-lsp-claude-plugins-official" ]
}

if [ ! -d "$PROJECT_DIR" ]; then
  emit_unavailable "项目路径不存在"
  exit 0
fi

if ! is_java_project; then
  emit_unavailable "未识别Java项目"
  exit 0
fi

JDTLS_PATH="$(command -v jdtls 2>/dev/null || true)"
if [ -n "$JDTLS_PATH" ]; then
  JDTLS_INSTALLED=true
  if perl -e 'alarm 5; exec @ARGV' "$JDTLS_PATH" --version >/dev/null 2>&1; then
    JDTLS_READY=true
  fi
fi

if plugin_installed; then
  PLUGIN_INSTALLED=true
fi

if [ "$JDTLS_INSTALLED" = true ] && [ "$JDTLS_READY" = true ] && [ "$PLUGIN_INSTALLED" = true ]; then
  echo "CODE_INTELLIGENCE_AVAILABLE=true"
  echo "CODE_INTELLIGENCE_LANGUAGE=java"
  echo "CODE_INTELLIGENCE_PROVIDER=jdtls-lsp"
  echo "CODE_INTELLIGENCE_COMMAND=$JDTLS_PATH"
  echo "CODE_INTELLIGENCE_JDTLS_INSTALLED=true"
  echo "CODE_INTELLIGENCE_JDTLS_READY=true"
  echo "CODE_INTELLIGENCE_PLUGIN_INSTALLED=true"
  echo "CODE_INTELLIGENCE_CAPABILITIES=definition,references,implementations,call_hierarchy,diagnostics"
else
  if [ "$JDTLS_INSTALLED" != true ] && [ "$PLUGIN_INSTALLED" != true ]; then
    emit_unavailable "未检测到jdtls命令和Claude Code jdtls-lsp插件"
  elif [ "$JDTLS_INSTALLED" != true ]; then
    emit_unavailable "未检测到jdtls命令"
  elif [ "$JDTLS_READY" != true ]; then
    emit_unavailable "jdtls命令不可用或响应超时"
  else
    emit_unavailable "未检测到Claude Code jdtls-lsp插件"
  fi
fi
