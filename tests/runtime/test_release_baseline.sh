#!/bin/bash
# Task 0: v1.5.0 三端插件兼容 — 发布基线测试
#
# 目的：冻结 v1.5.0 三端兼容开发前的基线，记录三个 Skill、三个语言 Agent、
# Claude 插件版本字段和测试套件结果，明确区分“原工作区既有修改”与“三端兼容新增内容”。
#
# 本测试只校验基线不变量，不修改运行时行为。它必须在本计划后续任务之前全绿。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

fail() { echo "BASELINE FAIL: $*" >&2; exit 1; }

# 1. 三个共享 Skill 必须存在（Claude Code 现有入口，三端复用）
for skill in cc-code-reviewer cc-code-ignore cc-code-fixer; do
  skill_file="$ROOT_DIR/skills/$skill/SKILL.md"
  [ -f "$skill_file" ] || fail "基线 Skill 缺失: $skill_file"
done

# 2. 三个语言 Agent 必须存在（Java / 前端 / Python）
for agent in cc-code-reviewer cc-code-reviewer-frontend cc-code-reviewer-python; do
  agent_file="$ROOT_DIR/agents/$agent.md"
  [ -f "$agent_file" ] || fail "基线 Agent 缺失: $agent_file"
done

# 3. Claude 插件清单和 Marketplace 清单必须可解析且版本非空
for manifest in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  manifest_file="$ROOT_DIR/$manifest"
  [ -f "$manifest_file" ] || fail "Claude 清单缺失: $manifest_file"
  perl -MJSON::PP -e 'decode_json(do { local $/; open my $fh, "<", $ARGV[0] or die $!; <$fh> })' "$manifest_file" \
    >/dev/null 2>&1 || fail "Claude 清单 JSON 不可解析: $manifest"
done

# 4. Claude plugin.json 与 marketplace.json 顶层版本必须一致且非空
PLUGIN_VERSION="$(grep -E '"version"' "$ROOT_DIR/.claude-plugin/plugin.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
MARKET_VERSION="$(grep -E '"version"' "$ROOT_DIR/.claude-plugin/marketplace.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
[ -n "$PLUGIN_VERSION" ] || fail "plugin.json 版本为空"
[ "$PLUGIN_VERSION" = "$MARKET_VERSION" ] || fail "Claude 清单版本不一致: '$PLUGIN_VERSION' != '$MARKET_VERSION'"

# 5. 共享内核目录必须存在（语言中立 + 语言适配）
for core_dir in scripts/core scripts/languages/java scripts/languages/frontend scripts/languages/python references/languages; do
  [ -d "$ROOT_DIR/$core_dir" ] || fail "共享内核目录缺失: $core_dir"
done

# 6. 三个 Skill 必须各自有 description frontmatter（name 字段在 Task 2 补齐）
for skill in cc-code-reviewer cc-code-ignore cc-code-fixer; do
  skill_file="$ROOT_DIR/skills/$skill/SKILL.md"
  head -5 "$skill_file" | grep -q '^description:' || fail "Skill 缺 description frontmatter: $skill"
done

# 7. 记录基线已知限制（三端兼容前的预期差距，非回归）
#    - Skills 仍使用 ${CLAUDE_PLUGIN_ROOT}（Task 2 替换为 ${PLUGIN_ROOT}）
#    - Agents 仍有 model: sonnet（Task 4 平台化）
#    - 仅存在 .claude-plugin 清单（Task 1 增加 .codex-plugin / .zcode-plugin）
#    - 无 runtime/ 契约目录（Task 2 创建）
# 这些差距在后续任务中消除，本测试只确认基线起点。

echo "✅ v1.5.0 三端兼容基线校验通过（version=${PLUGIN_VERSION}）"
