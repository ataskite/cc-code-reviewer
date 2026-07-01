#!/bin/bash
# 模型上下文窗口侦测
# 用途：根据 Claude Code 的逻辑模型名（opus/sonnet/haiku）侦测实际模型的上下文窗口大小，
#       输出缩放系数供分批脚本（core/plan-file-batches.sh、languages/java/plan-large-batches.sh）按窗口动态调整批次预算。
#
# 侦测原理：
#   Claude Code 通过 ~/.claude/settings.json 的 env 块把逻辑模型名映射到实际模型：
#     ANTHROPIC_DEFAULT_OPUS_MODEL    = "glm-5.2[1M]"   ← [1M] 后缀表示 1M 上下文窗口
#     ANTHROPIC_DEFAULT_SONNET_MODEL  = "glm-5-turbo"
#     ANTHROPIC_DEFAULT_HAIKU_MODEL   = "glm-4.7"
#   本脚本读取该映射，判断实际模型是否支持 1M 窗口，并计算缩放系数。
#
# 侦测优先级（多源容错）：
#   1. 环境变量 CC_REVIEW_CONTEXT_WINDOW 强制覆盖（最高优先级）
#   2. settings.json 中模型值含 [1M] 后缀 → 1M 窗口
#   3. 模型名匹配内置 1M 白名单 → 1M 窗口
#   4. 以上均不命中 → 保守默认 200K 窗口
set -euo pipefail

MODEL_ROLE="${1:-}"
SETTINGS_FILE="${HOME}/.claude/settings.json"
BASE_WINDOW=200000
LARGE_WINDOW=1000000
MAX_SCALE=10

# ── 1M 窗口模型白名单（fallback，当无 [1M] 后缀时按模型名前缀匹配，大小写不敏感） ──
# 仅收录已确认支持 1M 上下文的国产模型；新模型建议在 settings.json 用 [1M] 后缀标记
ONE_M_WHITELIST="deepseek-v4-flash deepseek-v4-pro qwen3.7-plus qwen3.7-max glm-5.2 minimax-m3 mimo-v2.5-pro"

usage() {
  echo "用法: bash core/detect-model-context.sh <opus|sonnet|haiku>" >&2
  echo "  读取 ~/.claude/settings.json 侦测实际模型的上下文窗口大小" >&2
}

if [ -z "$MODEL_ROLE" ]; then
  usage
  exit 1
fi

# 归一化逻辑模型名：opus / sonnet / haiku（容错大小写）
MODEL_ROLE_LOWER="$(printf '%s' "$MODEL_ROLE" | tr '[:upper:]' '[:lower:]')"
case "$MODEL_ROLE_LOWER" in
  opus|sonnet|haiku) ;;
  *)
    echo "无效的模型角色: ${MODEL_ROLE}（应为 opus / sonnet / haiku）" >&2
    exit 1
    ;;
esac

# 从 settings.json 提取实际模型名。读取顺序：ANTHROPIC_DEFAULT_{ROLE}_MODEL → ANTHROPIC_MODEL → 顶层 model
# 提取逻辑用 perl 解析 JSON，容错文件缺失/字段缺失
extract_model_from_settings() {
  local role_upper
  role_upper="$(printf '%s' "$MODEL_ROLE_LOWER" | tr '[:lower:]' '[:upper:]')"
  [ -f "$SETTINGS_FILE" ] || return 0

  perl -MJSON::PP -e '
    my ($file, $role_upper) = @ARGV;
    open my $fh, "<", $file or exit 0;
    local $/;
    my $data = eval { decode_json(<$fh>) } or exit 0;
    my $env = $data->{env} || {};
    # 优先级：ANTHROPIC_DEFAULT_{ROLE}_MODEL > ANTHROPIC_MODEL > 顶层 model
    my $m = $env->{"ANTHROPIC_DEFAULT_${role_upper}_MODEL"}
         || $env->{ANTHROPIC_MODEL}
         || $data->{model}
         || "";
    $m =~ s/^\s+|\s+$//g;
    print $m;
  ' "$SETTINGS_FILE" "$role_upper" 2>/dev/null
}

ACTUAL_MODEL="$(extract_model_from_settings)"

# ── 环境变量强制覆盖（最高优先级） ──
if [ -n "${CC_REVIEW_CONTEXT_WINDOW:-}" ]; then
  # 校验为正整数
  if [[ "$CC_REVIEW_CONTEXT_WINDOW" =~ ^[0-9]+$ ]] && [ "$CC_REVIEW_CONTEXT_WINDOW" -gt 0 ]; then
    CONTEXT_WINDOW_TOKENS="$CC_REVIEW_CONTEXT_WINDOW"
    DETECTION_SOURCE="env_override"
  else
    echo "CC_REVIEW_CONTEXT_WINDOW 值无效: $CC_REVIEW_CONTEXT_WINDOW（应为正整数）" >&2
    exit 1
  fi
else
  # ── 优先级 2：[1M] 后缀标记 ──
  # 实际模型值形如 "glm-5.2[1M]"，方括号内的窗口标记是最可靠的信号
  if printf '%s' "$ACTUAL_MODEL" | grep -qiE '\[1m\]'; then
    CONTEXT_WINDOW_TOKENS="$LARGE_WINDOW"
    DETECTION_SOURCE="suffix_marker"
  else
    # ── 优先级 3：白名单前缀匹配 ──
    # 去除 [任意] 后缀得到纯模型名，再小写化做前缀匹配
    MODEL_NAME_CLEAN="$(printf '%s' "$ACTUAL_MODEL" | sed 's/\[[^]]*\]//g' | tr '[:upper:]' '[:lower:]')"
    HIT_WHITELIST=0
    for candidate in $ONE_M_WHITELIST; do
      # 前缀匹配：白名单条目是模型名的前缀（如 glm-5.2 匹配 glm-5.2-preview）
      case "$MODEL_NAME_CLEAN" in
        "$candidate"*) HIT_WHITELIST=1; break ;;
      esac
    done
    if [ "$HIT_WHITELIST" -eq 1 ]; then
      CONTEXT_WINDOW_TOKENS="$LARGE_WINDOW"
      DETECTION_SOURCE="whitelist_match"
    else
      # ── 优先级 4：保守默认 ──
      CONTEXT_WINDOW_TOKENS="$BASE_WINDOW"
      DETECTION_SOURCE="default_fallback"
    fi
  fi
fi

# ── 计算缩放系数与档位 ──
CONTEXT_SCALE=$((CONTEXT_WINDOW_TOKENS / BASE_WINDOW))
# 封顶防极端：单批过大反而降低审查质量
[ "$CONTEXT_SCALE" -lt 1 ] && CONTEXT_SCALE=1
[ "$CONTEXT_SCALE" -gt "$MAX_SCALE" ] && CONTEXT_SCALE="$MAX_SCALE"

case "$CONTEXT_WINDOW_TOKENS" in
  1000000|1[0-9][0-9][0-9][0-9][0-9][0-9]|[2-9][0-9][0-9][0-9][0-9][0-9][0-9]) CONTEXT_TIER="large" ;;
  *) CONTEXT_TIER="standard" ;;
esac

# 纯模型名（去除 [后缀]）用于输出展示
ACTUAL_MODEL_NAME="$(printf '%s' "$ACTUAL_MODEL" | sed 's/\[[^]]*\]//g')"
[ -z "$ACTUAL_MODEL_NAME" ] && ACTUAL_MODEL_NAME="(未配置)"

# ── 输出 key=value（与 core 其他预扫描脚本风格一致，供主 skill 解析） ──
echo "MODEL_ROLE=$MODEL_ROLE_LOWER"
echo "ACTUAL_MODEL=$ACTUAL_MODEL"
echo "ACTUAL_MODEL_NAME=$ACTUAL_MODEL_NAME"
echo "CONTEXT_WINDOW_TOKENS=$CONTEXT_WINDOW_TOKENS"
echo "CONTEXT_TIER=$CONTEXT_TIER"
echo "CONTEXT_SCALE=$CONTEXT_SCALE"
echo "DETECTION_SOURCE=$DETECTION_SOURCE"
