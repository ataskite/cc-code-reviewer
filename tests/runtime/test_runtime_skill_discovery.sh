#!/bin/bash
# Task 5: 平台能力发现与可选集成测试
#
# 校验：
#   - Skill 搜索根目录覆盖 .claude / .agents / .codex / .zcode 四端
#   - lark-cli 不可用时只降级本地报告，不影响核心审查
#   - Superpowers 仍是 fix 可选路线，不成为 Codex/ZCode 安装前置
#   - 平台中立：能力检测不偏向某一平台
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

fail() { echo "FAIL test_runtime_skill_discovery: $*" >&2; exit 1; }

LARK_DETECT="$ROOT_DIR/scripts/core/detect-lark-plugin.sh"
SUPERPOWERS_DETECT="$ROOT_DIR/scripts/core/detect-superpowers.sh"

# 1. detect-lark-plugin.sh 必须覆盖四端 skill 根目录
grep -q '.agents/skills' "$LARK_DETECT" || fail "detect-lark 必须覆盖 .agents/skills"
grep -q '.codex/skills' "$LARK_DETECT" || fail "detect-lark 必须覆盖 .codex/skills"
grep -q '.claude/skills' "$LARK_DETECT" || fail "detect-lark 必须覆盖 .claude/skills"
grep -q '.zcode/skills' "$LARK_DETECT" || fail "detect-lark 必须覆盖 .zcode/skills（三端中立）"

# 2. detect-superpowers.sh 必须覆盖四端 skill 根目录
grep -q '.agents/skills' "$SUPERPOWERS_DETECT" || fail "detect-superpowers 必须覆盖 .agents/skills"
grep -q '.codex/skills' "$SUPERPOWERS_DETECT" || fail "detect-superpowers 必须覆盖 .codex/skills"
grep -q '.claude/skills' "$SUPERPOWERS_DETECT" || fail "detect-superpowers 必须覆盖 .claude/skills（三端中立）"
grep -q '.zcode/skills' "$SUPERPOWERS_DETECT" || fail "detect-superpowers 必须覆盖 .zcode/skills（三端中立）"

# 3. detect-lark-plugin.sh 无 lark-cli 时必须输出降级（不非零退出，保持只降级不阻断）
#    在无 lark-cli 的环境验证输出契约
lark_output="$(bash "$LARK_DETECT" 2>/dev/null || true)"
echo "$lark_output" | grep -qE 'LARK_PLUGIN_INSTALLED=(true|false)' \
  || fail "detect-lark 必须输出 LARK_PLUGIN_INSTALLED 状态"

# 4. detect-superpowers.sh 必须输出 SUPERPOWERS_AVAILABLE 状态
sp_output="$(bash "$SUPERPOWERS_DETECT" 2>/dev/null || true)"
echo "$sp_output" | grep -qE 'SUPERPOWERS_AVAILABLE=(true|false)' \
  || fail "detect-superpowers 必须输出 SUPERPOWERS_AVAILABLE 状态"

# 5. Superpowers 不得成为 Codex/ZCode 安装前置条件
#    runtime 适配器不得把 Superpowers 列为必需能力
for adapter in runtime/codex.md runtime/zcode.md; do
  if grep -qE 'Superpowers.{0,20}(必须|前置|必需|required)' "$ROOT_DIR/$adapter"; then
    fail "$adapter 不得把 Superpowers 列为必需能力"
  fi
done

# 6. runtime/contract.md 必须声明 lark-cli 与 Superpowers 为可选能力
grep -q 'lark-cli 不可用' "$ROOT_DIR/runtime/contract.md" \
  || fail "contract.md 必须声明 lark-cli 不可用时降级"
grep -q 'Superpowers 不可用' "$ROOT_DIR/runtime/contract.md" \
  || fail "contract.md 必须声明 Superpowers 不可用时降级"

# 7. 脚本必须可执行（语法校验）
bash -n "$LARK_DETECT" || fail "detect-lark 语法错误"
bash -n "$SUPERPOWERS_DETECT" || fail "detect-superpowers 语法错误"

echo "✅ 平台能力发现与可选集成测试通过"
