#!/bin/bash
# Task 3: 跨平台人工确认交互契约测试
#
# 校验三个 Skill 的交互契约、Codex 原生工具映射与 ZCode 降级规则。
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

# 2. Codex 三个入口必须路由到原生工具契约，文本降级仅保留给 ZCode
grep -q '本文中的 `INTERACT` 是逻辑动作' "$SCAN_SKILL" \
  || fail "scan skill 必须声明 INTERACT 为逻辑动作"
grep -q '逐轮单问' "$SCAN_SKILL" \
  || fail "scan skill 必须保留 ZCode 的逐轮单问降级"
grep -q '分级菜单' "$SCAN_SKILL" \
  || fail "scan skill 必须声明 Codex 选项上限的分级菜单降级"
for skill_file in "$SCAN_SKILL" "$IGNORE_SKILL" "$FIX_SKILL"; do
  grep -q 'runtime/codex.md' "$skill_file" || fail "$skill_file 缺少 Codex adapter 路由"
  grep -q '禁止文本降级' "$skill_file" || fail "$skill_file 不得允许 Codex 静默文本降级"
  grep -q '用户实际回答' "$skill_file" || fail "$skill_file 必须等待实际回答"
done

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

# 6. Codex 原生工具选择、模式限制、异步状态和组合保真
grep -q '优先使用 `request_user_input_async`' "$CODEX_ADAPTER" || fail "Codex 必须明确异步原生工具优先"
grep -q '仅限 Plan 模式' "$CODEX_ADAPTER" || fail "Codex 必须尊重同步工具模式限制"
grep -q '用途限制' "$CODEX_ADAPTER" || fail "Codex 必须尊重审批用途限制"
grep -q '预选项不代表确认' "$CODEX_ADAPTER" || fail "Codex 不得把默认选项当作确认"
grep -q '禁止文本降级' "$CODEX_ADAPTER" || fail "Codex 工具不可用时必须阻塞"
if grep -q 'sequential-text' "$CODEX_ADAPTER"; then
  fail "Codex adapter 不得重新引入文本降级模式"
fi
grep -q '分级菜单' "$CODEX_ADAPTER" || fail "codex 适配器必须声明分级菜单降级"
grep -q '连续单选' "$CODEX_ADAPTER" || fail "codex 适配器必须声明无多选时的连续单选降级"
grep -q '保留任意组合' "$CODEX_ADAPTER" || fail "多选适配不得丢失可选组合"

# 参数示例作为 Agent 的调用模板，验证可解析及两种 schema 不混用。
perl -MJSON::PP -0777 -e '
  my $doc = <>;
  my @examples = $doc =~ /```json\n(.*?)\n```/sg;
  die "expected async and sync examples\n" unless @examples == 2;
  for my $i (0..1) {
    my $p = decode_json($examples[$i]);
    die "one question per call\n" unless @{$p->{questions}} == 1;
    my $q = $p->{questions}[0];
    die "unsupported multiSelect\n" if exists $q->{multiSelect};
    die "missing options\n" unless @{$q->{options}} >= 1;
    if ($i == 0) {
      die "async title required\n" unless $q->{title};
      die "async fields mixed\n" if exists $q->{header} || exists $q->{id} || exists $q->{question};
      for (@{$q->{options}}) { die "async option must be a string\n" if ref($_); }
    } else {
      die "sync option count must be 2-3\n" unless @{$q->{options}} >= 2 && @{$q->{options}} <= 3;
      die "sync fields required\n" unless $q->{id} && $q->{header} && $q->{question};
      die "sync title unsupported\n" if exists $q->{title};
      for (@{$q->{options}}) {
        die "sync option must have label and description\n" unless ref($_) eq "HASH" && $_->{label} && $_->{description};
      }
    }
  }
' "$CODEX_ADAPTER" || fail "Codex 工具参数示例 schema 不正确"

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
