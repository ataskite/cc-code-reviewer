#!/bin/bash
# Task 4: 模型档位平台中立契约测试
#
# 校验：
#   - 共享 Agent Prompt 不绑定 Claude 专属模型（model: sonnet）
#   - scan skill 声明平台无关 MODEL_PROFILE 档位
#   - runtime/contract.md 定义 MODEL_PROFILE 与 REVIEW_MODE 分离
#   - 三端适配器各自声明模型映射
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

fail() { echo "FAIL test_model_profile_contract: $*" >&2; exit 1; }

# 1. 共享 Agent Prompt 不得绑定 Claude 专属模型（frontmatter 无 model: sonnet/opus/haiku）
for agent_file in \
  "$ROOT_DIR/agents/cc-code-reviewer.md" \
  "$ROOT_DIR/agents/cc-code-reviewer-frontend.md" \
  "$ROOT_DIR/agents/cc-code-reviewer-python.md"; do
  # frontmatter 前 8 行不得有 model: sonnet/opus/haiku
  if head -8 "$agent_file" | grep -qE '^model:[[:space:]]*(sonnet|opus|haiku)'; then
    fail "Agent frontmatter 绑定 Claude 专属模型: ${agent_file}"
  fi
done

# 2. Agent Prompt 不得在正文硬编码强制模型名（允许在注释/说明中提及作为映射源）
#    正文（frontmatter 之后）不得出现"必须使用 sonnet"等强制语句
for agent_file in \
  "$ROOT_DIR/agents/cc-code-reviewer.md" \
  "$ROOT_DIR/agents/cc-code-reviewer-frontend.md" \
  "$ROOT_DIR/agents/cc-code-reviewer-python.md"; do
  if grep -qE '必须.{0,10}(sonnet|opus|haiku)|强制.{0,10}(sonnet|opus|haiku)' "$agent_file"; then
    fail "Agent 正文强制 Claude 模型: ${agent_file}"
  fi
done

# 3. runtime/contract.md 必须定义 MODEL_PROFILE 档位与 REVIEW_MODE 分离
CONTRACT="$ROOT_DIR/runtime/contract.md"
grep -q 'MODEL_PROFILE' "$CONTRACT" || fail "contract.md 必须定义 MODEL_PROFILE"
for profile in inherit economy balanced maximum; do
  grep -q "$profile" "$CONTRACT" || fail "contract.md 必须定义 $profile 档位"
done
grep -q 'MODEL_PROFILE. 分离' "$CONTRACT" || fail "contract.md 必须声明 REVIEW_MODE 与 MODEL_PROFILE 分离"

# 4. 三端适配器必须各自声明模型映射
for adapter in runtime/claude-code.md runtime/codex.md runtime/zcode.md; do
  grep -q 'MODEL_PROFILE' "$ROOT_DIR/$adapter" || fail "$adapter 必须声明 MODEL_PROFILE 映射"
done

# 5. scan skill 必须声明平台无关模型档位（MODEL_PROFILE）
SCAN_SKILL="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
grep -q 'MODEL_PROFILE' "$SCAN_SKILL" || fail "scan skill 必须声明平台无关 MODEL_PROFILE 档位"
for profile in inherit economy balanced maximum; do
  grep -q "$profile" "$SCAN_SKILL" || fail "scan skill 必须声明 $profile 档位"
done
if grep -qE 'MODEL_PROFILE[^\n]*(fast|deep)|MODEL_PROFILE[^\n]*(opus|sonnet|haiku)' "$SCAN_SKILL"; then
  fail "scan skill 使用了过期模型档位或 Claude 模型名"
fi
if grep -q 'REVIEW_MODEL' "$SCAN_SKILL"; then
  fail "scan skill 残留 REVIEW_MODEL"
fi

echo "✅ 模型档位平台中立契约测试通过"
