#!/bin/bash
# 阶段四：lark-cli 检测
# 用途：检测系统是否安装 lark-cli 命令行工具
#
# 平台中立：Skill 搜索根覆盖 Claude Code / Codex / ZCode / 通用 .agents 四端。

set -e

has_skill() {
  local skill_name="$1"
  # 覆盖三端 Agent 产品的 skill 根目录（Claude / Codex / ZCode / 通用 .agents）。
  [ -d "$HOME/.agents/skills/$skill_name" ] ||
    [ -d "$HOME/.codex/skills/$skill_name" ] ||
    [ -d "$HOME/.claude/skills/$skill_name" ] ||
    [ -d "$HOME/.zcode/skills/$skill_name" ]
}

LARK_CLI_PATH="$(command -v lark-cli 2>/dev/null || true)"

if [ -z "$LARK_CLI_PATH" ]; then
  echo "LARK_PLUGIN_INSTALLED=false"
  echo "LARK_PLUGIN_REASON=lark-cli命令未安装"
elif ! "$LARK_CLI_PATH" --version >/dev/null 2>&1; then
  echo "LARK_PLUGIN_INSTALLED=false"
  echo "LARK_PLUGIN_REASON=lark-cli命令不可执行"
elif has_skill "lark-doc" && has_skill "lark-base"; then
  echo "LARK_PLUGIN_INSTALLED=true"
  echo "LARK_PLUGIN_NAME=lark-cli"
  echo "LARK_CLI_PATH=$LARK_CLI_PATH"
  echo "LARK_SKILLS_INSTALLED=true"
else
  echo "LARK_PLUGIN_INSTALLED=false"
  echo "LARK_PLUGIN_REASON=缺少lark-doc或lark-base技能"
fi
