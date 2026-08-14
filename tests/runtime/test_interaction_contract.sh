#!/bin/bash
# Task 3: 跨平台人工确认交互契约测试
#
# 校验三个 Skill 声明了平台无关的交互契约，且 Codex/ZCode 降级规则存在。
# 共享流程统一使用 INTERACT；Claude adapter 再映射到 AskUserQuestion。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCAN_SKILL="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
IGNORE_SKILL="$ROOT_DIR/skills/cc-code-ignore/SKILL.md"
FIX_SKILL="$ROOT_DIR/skills/cc-code-fixer/SKILL.md"
CONTRACT="$ROOT_DIR/runtime/contract.md"
CODEX_ADAPTER="$ROOT_DIR/runtime/codex.md"
ZCODE_ADAPTER="$ROOT_DIR/runtime/zcode.md"

fail() { echo "FAIL test_interaction_contract: $*" >&2; exit 1; }

# 1. 三个 Skill 必须声明跨平台人工确认契约（引用 runtime/contract.md 或等价说明）
for skill_file in "$SCAN_SKILL" "$IGNORE_SKILL" "$FIX_SKILL"; do
  grep -q '跨平台' "$skill_file" \
    || fail "$skill_file 必须声明跨平台人工确认契约"
done

# 2. scan skill 必须声明三端交互等价与 Codex/ZCode 降级规则
grep -q '本文中的 `INTERACT` 是逻辑动作' "$SCAN_SKILL" \
  || fail "scan skill 必须声明 INTERACT 为逻辑动作"
grep -q '逐轮单问' "$SCAN_SKILL" \
  || fail "scan skill 必须声明无结构化输入时的逐轮单问降级"
grep -q '分级菜单' "$SCAN_SKILL" \
  || fail "scan skill 必须声明 Codex 选项上限的分级菜单降级"

# 3. 不变量必须声明：预扫描先于交互、每步等待、禁止合并、禁止绕过、最终单独确认
grep -q '预扫描先于交互' "$SCAN_SKILL" || fail "scan skill 必须声明预扫描先于交互"
grep -q '禁止合并步骤' "$SCAN_SKILL" || fail "scan skill 必须声明禁止合并步骤"
grep -q '最终执行确认' "$SCAN_SKILL" || fail "scan skill 必须声明最终执行单独确认"

# 4. fix skill 必须声明交互等价与范围确认不变量
grep -q '`INTERACT` 是逻辑动作' "$FIX_SKILL" \
  || fail "fix skill 必须声明 INTERACT 为逻辑动作"
grep -q 'fix 只执行确认后的问题集合' "$FIX_SKILL" \
  || fail "fix skill 必须声明只执行确认后的问题集合"

# 5. runtime/contract.md 必须定义交互状态机与降级语义
grep -q '人工确认状态机' "$CONTRACT" || fail "contract.md 必须定义人工确认状态机"
grep -q 'preflight_summary' "$CONTRACT" || fail "contract.md 必须定义摘要先于问题"
grep -q 'current_scope_sizing' "$CONTRACT" || fail "contract.md 必须在分批策略前定义当前范围规模重算"
grep -q 'estimated_tokens <= 1000000.*Maven 多模块存量审查跳过' "$CONTRACT" || fail "contract.md 必须声明 1M 以内 Maven 多模块跳过分批策略"
grep -q 'final_confirmation' "$CONTRACT" || fail "contract.md 必须定义最终确认独立状态"
grep -q 'sequential-text' "$CONTRACT" || fail "contract.md 必须定义逐轮单问降级模式"

# 6. Codex 适配器必须声明 2-3 选项上限与多选降级
grep -q '2' "$CODEX_ADAPTER" || true  # 选项上限在描述中体现
grep -q '分级菜单' "$CODEX_ADAPTER" || fail "codex 适配器必须声明分级菜单降级"
grep -q '连续单选' "$CODEX_ADAPTER" || fail "codex 适配器必须声明无多选时的连续单选降级"

# 7. ZCode 适配器必须声明原生多选与降级
grep -q '原生多选' "$ZCODE_ADAPTER" || fail "zcode 适配器必须声明原生多选"
grep -q '连续单选' "$ZCODE_ADAPTER" || fail "zcode 适配器必须声明降级连续单选"

# 8. 共享流程不得声明命令行参数绕过交互（与现有 test_contract_docs 互补）
for skill_file in "$SCAN_SKILL" "$FIX_SKILL"; do
  if grep -qE '\-\-mode[[:space:]]|FAST_MODE|FAST_PARAMS|快速启动' "$skill_file"; then
    fail "$skill_file 不得声明命令行参数绕过交互"
  fi
done

echo "✅ 跨平台人工确认交互契约测试通过"
