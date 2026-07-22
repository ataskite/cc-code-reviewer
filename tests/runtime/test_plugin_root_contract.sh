#!/bin/bash
# Verify deterministic plugin-root resolution from the shared root Skill resources.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL test_plugin_root_contract: $*" >&2; exit 1; }

for rt_file in runtime/contract.md runtime/claude-code.md runtime/codex.md runtime/zcode.md; do
  [ -f "$ROOT_DIR/$rt_file" ] || fail "runtime 契约文件缺失: $rt_file"
done

for token in RUNTIME_ID PLUGIN_ROOT INTERACTION_MODE AGENT_DISPATCH_MODE MODEL_PROFILE INTERACT DISPATCH_AGENT; do
  grep -q "$token" "$ROOT_DIR/runtime/contract.md" || fail "runtime/contract.md 缺少逻辑契约: $token"
done

for skill in cc-code-reviewer cc-code-ignore cc-code-fixer; do
  shared="$ROOT_DIR/skills/$skill/SKILL.md"
  [ -f "$shared" ] || fail "共享 Skill 缺失: $shared"
  resolved="$(cd "$(dirname "$shared")/../.." && pwd)"
  [ "$resolved" = "$ROOT_DIR" ] || fail "$shared 解析到错误根目录: $resolved"
  [ -f "$resolved/VERSION" ] || fail "$shared 解析结果缺少 VERSION"
  [ -f "$resolved/scripts/core/detect-project.sh" ] || fail "$shared 解析结果缺少核心脚本"
  [ -f "$resolved/skills/$skill/SKILL.md" ] || fail "$shared 解析结果缺少当前 Skill"
  grep -q '当前宿主身份' "$shared" || fail "$shared 未声明由宿主身份选择 RUNTIME_ID"
  if grep -qF '${CLAUDE_PLUGIN_ROOT}' "$shared"; then
    fail "共享 Skill 残留 CLAUDE_PLUGIN_ROOT: $shared"
  fi
done

for adapter in runtime/codex.md runtime/zcode.md; do
  if grep -qF 'dirname "$0"' "$ROOT_DIR/$adapter"; then
    fail "$adapter 仍使用 shell \$0 推断 Skill 路径"
  fi
  grep -qF '../..' "$ROOT_DIR/$adapter" || fail "$adapter 未声明根 Skill 固定相对层级"
done

echo "✅ PLUGIN_ROOT 契约测试通过"
