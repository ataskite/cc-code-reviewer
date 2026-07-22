#!/bin/bash
# Task 4: 子 Agent 调度跨平台契约测试
#
# 校验：
#   - Java / 前端 / Python 各至少有一个单 Agent 调度契约
#   - batch 调度不依赖 Claude Agent 名称（通用 subagent 可承担）
#   - 三端适配器声明各自的 AGENT_DISPATCH_MODE
#   - 子 Agent 不与用户交互、不上传飞书、不扩展正式扫描范围
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

fail() { echo "FAIL test_agent_dispatch_contract: $*" >&2; exit 1; }

SCAN_SKILL="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
CONTRACT="$ROOT_DIR/runtime/contract.md"

# 1. 三端适配器必须声明 AGENT_DISPATCH_MODE
grep -q 'native-agent' "$ROOT_DIR/runtime/claude-code.md" \
  || fail "claude-code 适配器必须声明 native-agent 调度模式"
grep -q 'generic-subagent' "$ROOT_DIR/runtime/codex.md" \
  || fail "codex 适配器必须声明 generic-subagent 调度模式"
grep -q 'generic-subagent' "$ROOT_DIR/runtime/zcode.md" \
  || fail "zcode 适配器必须声明 generic-subagent 降级"

# 2. 共享 Agent Prompt 必须保留统一角色与输出契约（三端复用）
for agent_file in \
  "$ROOT_DIR/agents/cc-code-reviewer.md" \
  "$ROOT_DIR/agents/cc-code-reviewer-frontend.md" \
  "$ROOT_DIR/agents/cc-code-reviewer-python.md"; do
  [ -f "$agent_file" ] || fail "Agent Prompt 缺失: ${agent_file}"
  # 必须有 name frontmatter（三端复用的稳定标识）
  head -8 "$agent_file" | grep -q '^name:' || fail "Agent 缺 name frontmatter: ${agent_file}"
done

# 3. runtime/contract.md 必须声明子 Agent 职责边界
grep -q '不与用户交互' "$CONTRACT" || fail "contract.md 必须声明子 Agent 不与用户交互"
grep -q '不上传飞书' "$CONTRACT" || fail "contract.md 必须声明子 Agent 不上传飞书"
grep -q '不扩展正式扫描范围' "$CONTRACT" || fail "contract.md 必须声明子 Agent 不扩展正式扫描范围"

# 4. 共享流程只能通过平台中立 DISPATCH_AGENT + Agent Prompt 路径调度
grep -q 'DISPATCH_AGENT' "$SCAN_SKILL" || fail "scan skill 必须使用 DISPATCH_AGENT"
for prompt in agents/cc-code-reviewer.md agents/cc-code-reviewer-frontend.md agents/cc-code-reviewer-python.md; do
  grep -q "$prompt" "$SCAN_SKILL" || fail "scan skill 缺少 Agent Prompt 路径: $prompt"
done
if grep -q 'subagent_type:' "$SCAN_SKILL"; then
  fail "共享 scan skill 不得绑定 Claude subagent_type"
fi

# 5. batch agent 必须写 status/result 文件（三端统一文件协议，不依赖 Agent 名称）
grep -q 'BATCH_STATUS_PATH' "$ROOT_DIR/agents/cc-code-reviewer.md" \
  || fail "Java batch agent 必须写 BATCH_STATUS_PATH"
grep -q 'BATCH_RESULT_PATH' "$ROOT_DIR/agents/cc-code-reviewer.md" \
  || fail "Java batch agent 必须写 BATCH_RESULT_PATH"

# 6. 平台无 subagent 时必须阻塞，不得静默接管
grep -q '阻塞' "$CONTRACT" || fail "contract.md 必须声明无 subagent 时阻塞"
grep -q '不得.*静默' "$CONTRACT" || fail "contract.md 必须声明不得静默接管审查"

echo "✅ 子 Agent 调度跨平台契约测试通过"
