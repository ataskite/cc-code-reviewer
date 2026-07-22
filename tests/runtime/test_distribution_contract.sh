#!/bin/bash
# Task 7: 三端分发契约与自动化门禁测试
#
# 自动化门禁：
#   - bash tests/run_all.sh 全绿（由 run_all.sh 本身保证）
#   - git diff --check 通过（由 run_all.sh 保证）
#   - 三端清单 JSON/必填字段/版本/Skill 路径校验通过（Task 1 已覆盖）
#   - 仓库内活跃文件不存在 ${CLAUDE_PLUGIN_ROOT}、强制 model: sonnet、仅 Claude 可理解的调度指令
#     （允许历史计划文档 docs/superpowers/ 保留背景文本）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

fail() { echo "FAIL test_distribution_contract: $*" >&2; exit 1; }

# 1. 活跃文件（skills/ + agents/）不得残留 ${CLAUDE_PLUGIN_ROOT}
while IFS= read -r -d '' active_file; do
  if grep -qF '${CLAUDE_PLUGIN_ROOT}' "$active_file"; then
    fail "活跃文件残留 \${CLAUDE_PLUGIN_ROOT}: ${active_file}"
  fi
done < <(find "$ROOT_DIR/skills" "$ROOT_DIR/agents" -type f \( -name '*.md' -o -name '*.sh' \) -print0)

# 2. 活跃 Agent Prompt 不得在 frontmatter 强制 model: sonnet/opus/haiku
while IFS= read -r -d '' agent_file; do
  if head -8 "$agent_file" | grep -qE '^model:[[:space:]]*(sonnet|opus|haiku)'; then
    fail "Agent frontmatter 强制 Claude 模型: ${agent_file}"
  fi
done < <(find "$ROOT_DIR/agents" -type f -name '*.md' -print0)

# 3. 历史计划文档允许保留背景文本（不参与断言）
#    docs/superpowers/ 下的 ${CLAUDE_PLUGIN_ROOT} 和 model: sonnet 是历史背景，允许保留。

# 4. 三端清单必须全部存在且可解析
for manifest in \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  .codex-plugin/plugin.json \
  .agents/plugins/marketplace.json \
  .zcode-plugin/plugin.json; do
  [ -f "$ROOT_DIR/$manifest" ] || fail "分发清单缺失: $manifest"
  perl -MJSON::PP -e 'decode_json(do { local $/; open my $fh, "<", $ARGV[0] or die $!; <$fh> })' "$ROOT_DIR/$manifest" \
    >/dev/null 2>&1 || fail "清单 JSON 不可解析: $manifest"
done

# 5. VERSION 单一真相源必须存在且与版本化插件清单一致。
# Codex marketplace 是目录索引，版本由 source 指向的 plugin.json 提供。
[ -f "$ROOT_DIR/VERSION" ] || fail "VERSION 文件缺失"
VERSION_TRUTH="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
[ -n "$VERSION_TRUTH" ] || fail "VERSION 内容为空"
for manifest in \
  .claude-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  .codex-plugin/plugin.json \
  .zcode-plugin/plugin.json; do
  ver="$(grep -E '"version"' "$ROOT_DIR/$manifest" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
  [ "$ver" = "$VERSION_TRUTH" ] || fail "$manifest 版本与 VERSION 不一致: '$ver' != '$VERSION_TRUTH'"
done

# 6. 三个共享 Skill 必须被三端原生清单共同发现
for skill in cc-code-reviewer cc-code-ignore cc-code-fixer; do
  [ -f "$ROOT_DIR/skills/$skill/SKILL.md" ] || fail "Skill 缺失: $skill"
done

# 7. runtime/ 契约目录必须完整
for rt_file in runtime/contract.md runtime/claude-code.md runtime/codex.md runtime/zcode.md; do
  [ -f "$ROOT_DIR/$rt_file" ] || fail "runtime 契约文件缺失: $rt_file"
done

# 8. 集成校验脚本必须通过
bash "$ROOT_DIR/scripts/core/validate-plugin-manifests.sh" >/dev/null \
  || fail "validate-plugin-manifests.sh 校验失败"

echo "✅ 三端分发契约与自动化门禁测试通过"
