#!/bin/bash
# 状态：预留脚本，当前未接入运行时流程。
# 计划在后续 scope 校验增强中接入（多模块选择时的路径边界校验）。
# 保留 test_contract_docs.sh 的存在性断言。
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
SCOPE_INPUT="${2:-}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

normalize_input() {
  # 将中文逗号/顿号/制表符/空格统一为 ASCII 逗号，再按逗号拆行
  printf '%s\n' "$SCOPE_INPUT" | tr '，、\t ' ',,,' | tr -s ',' '\n' | sed '/^$/d'
}

fail() { echo "SCOPE_OUTSIDE_PROJECT=$1" >&2; exit 1; }

[ -n "$SCOPE_INPUT" ] || { echo "$PROJECT_DIR"; exit 0; }

while IFS= read -r raw; do
  [ -n "$raw" ] || continue
  case "$raw" in
    /*|\~*) fail "$raw" ;;
  esac
  resolved="$PROJECT_DIR/$raw"
  case "$resolved" in
    "$PROJECT_DIR"/*) ;;
    *) fail "$raw" ;;
  esac
  # 解析符号链接后再校验是否仍在项目内（pwd -P 取物理路径，避免逻辑路径绕过）
  if resolved_real="$(cd "$resolved" 2>/dev/null && pwd -P)"; then
    case "$resolved_real" in
      "$PROJECT_DIR"/*|"$PROJECT_DIR") printf '%s\n' "$resolved_real" ;;
      *) fail "$raw" ;;
    esac
  else
    printf '%s\n' "$PROJECT_DIR/$raw"
  fi
done < <(normalize_input)
