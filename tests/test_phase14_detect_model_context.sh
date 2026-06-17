#!/bin/bash
# 测试：phase14-detect-model-context.sh
# 覆盖场景：
#   1. settings.json 含 [1M] 后缀 → 1M 窗口（suffix_marker）
#   2. 模型名匹配白名单 → 1M 窗口（whitelist_match）
#   3. 普通模型 → 200K 窗口（default_fallback）
#   4. 环境变量强制覆盖（env_override）
#   5. settings.json 不存在 → 安全回退 200K
#   6. 无效模型角色 / 无参数 → 报错退出
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/phase14-detect-model-context.sh"
TMPHOME="/tmp/test_phase14_$$"

cleanup() { rm -rf "$TMPHOME"; }
trap cleanup EXIT

# 构造临时 HOME，其下放测试用 settings.json
make_settings() {
  local content="$1"
  mkdir -p "$TMPHOME/.claude"
  printf '%s' "$content" > "$TMPHOME/.claude/settings.json"
}

# 运行脚本（用临时 HOME 隔离），捕获输出
run_with_home() {
  HOME="$TMPHOME" bash "$SCRIPT" "$@"
}

assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL: $label" >&2
    echo "  期望: $expected" >&2
    echo "  实际: $actual" >&2
    exit 1
  fi
}

echo "==> test_phase14_detect_model_context.sh"

# ── 场景 1：[1M] 后缀标记 ──
echo "    [1/6] [1M] 后缀 → 1M 窗口"
make_settings '{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"glm-5.2[1M]","ANTHROPIC_DEFAULT_SONNET_MODEL":"glm-5-turbo","ANTHROPIC_DEFAULT_HAIKU_MODEL":"glm-4.7"}}'
OUT="$(run_with_home opus)"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_WINDOW_TOKENS=' | cut -d= -f2)" "1000000" "[1M]后缀 窗口"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_SCALE=' | cut -d= -f2)" "5" "[1M]后缀 scale"
assert_eq "$(echo "$OUT" | grep '^DETECTION_SOURCE=' | cut -d= -f2)" "suffix_marker" "[1M]后缀 source"
assert_eq "$(echo "$OUT" | grep '^ACTUAL_MODEL_NAME=' | cut -d= -f2)" "glm-5.2" "[1M]后缀 模型名(去后缀)"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_TIER=' | cut -d= -f2)" "large" "[1M]后缀 tier"

# ── 场景 2：白名单匹配（无 [1M] 后缀）──
echo "    [2/6] 白名单匹配 → 1M 窗口"
make_settings '{"env":{"ANTHROPIC_DEFAULT_SONNET_MODEL":"qwen3.7-max"}}'
OUT="$(run_with_home sonnet)"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_WINDOW_TOKENS=' | cut -d= -f2)" "1000000" "白名单 窗口"
assert_eq "$(echo "$OUT" | grep '^DETECTION_SOURCE=' | cut -d= -f2)" "whitelist_match" "白名单 source"

# ── 场景 3：普通模型 → 200K ──
echo "    [3/6] 普通模型 → 200K 窗口"
make_settings '{"env":{"ANTHROPIC_DEFAULT_HAIKU_MODEL":"glm-4.7"}}'
OUT="$(run_with_home haiku)"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_WINDOW_TOKENS=' | cut -d= -f2)" "200000" "普通模型 窗口"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_SCALE=' | cut -d= -f2)" "1" "普通模型 scale"
assert_eq "$(echo "$OUT" | grep '^DETECTION_SOURCE=' | cut -d= -f2)" "default_fallback" "普通模型 source"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_TIER=' | cut -d= -f2)" "standard" "普通模型 tier"

# ── 场景 4：环境变量强制覆盖 ──
echo "    [4/6] 环境变量覆盖 → 自定义窗口"
make_settings '{"env":{"ANTHROPIC_DEFAULT_OPUS_MODEL":"glm-4.7"}}'
OUT="$(HOME="$TMPHOME" CC_REVIEW_CONTEXT_WINDOW=500000 bash "$SCRIPT" opus)"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_WINDOW_TOKENS=' | cut -d= -f2)" "500000" "env覆盖 窗口"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_SCALE=' | cut -d= -f2)" "2" "env覆盖 scale"
assert_eq "$(echo "$OUT" | grep '^DETECTION_SOURCE=' | cut -d= -f2)" "env_override" "env覆盖 source"

# ── 场景 5：settings.json 不存在 → 安全回退 ──
echo "    [5/6] settings.json 不存在 → 回退 200K"
rm -rf "$TMPHOME"
mkdir -p "$TMPHOME"
OUT="$(run_with_home opus)"
assert_eq "$(echo "$OUT" | grep '^CONTEXT_WINDOW_TOKENS=' | cut -d= -f2)" "200000" "无配置 窗口"
assert_eq "$(echo "$OUT" | grep '^DETECTION_SOURCE=' | cut -d= -f2)" "default_fallback" "无配置 source"
assert_eq "$(echo "$OUT" | grep '^ACTUAL_MODEL_NAME=' | cut -d= -f2)" "(未配置)" "无配置 模型名占位"

# ── 场景 6：无效模型角色 / 无参数 → 报错 ──
echo "    [6/6] 无效角色 / 无参数 → 报错"
if run_with_home invalid >/dev/null 2>&1; then
  echo "FAIL: 无效角色应报错退出" >&2; exit 1
fi
if run_with_home >/dev/null 2>&1; then
  echo "FAIL: 无参数应报错退出" >&2; exit 1
fi

echo "    ok"
