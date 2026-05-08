#!/bin/bash
set -euo pipefail

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
  echo "修复输入不能为空" >&2
  exit 1
fi

if [[ "$INPUT" == *$'\n'* || "$INPUT" == *$'\r'* ]]; then
  echo "修复输入不能包含换行符" >&2
  exit 1
fi

case "$INPUT" in
  http://*docx/*|https://*docx/*|http://*docs/*|https://*docs/*)
    echo "FIX_INPUT_TYPE=feishu-doc"
    echo "FIX_INPUT_URL=$INPUT"
    ;;
  http://*base/*|https://*base/*)
    echo "FIX_INPUT_TYPE=feishu-base"
    echo "FIX_INPUT_URL=$INPUT"
    ;;
  base:*:*)
    REST="${INPUT#base:}"
    BASE_TOKEN="${REST%%:*}"
    TABLE_ID="${REST#*:}"
    if [ -z "$BASE_TOKEN" ] || [ -z "$TABLE_ID" ] || [ "$BASE_TOKEN" = "$TABLE_ID" ] || [ "$TABLE_ID" != "${TABLE_ID%%:*}" ]; then
      echo "无法识别修复输入来源: $INPUT" >&2
      exit 1
    fi
    echo "FIX_INPUT_TYPE=feishu-base-token"
    echo "FEISHU_BASE_TOKEN=$BASE_TOKEN"
    echo "FEISHU_TABLE_ID=$TABLE_ID"
    ;;
  *.md)
    if [ ! -f "$INPUT" ]; then
      echo "修复输入不存在: $INPUT" >&2
      exit 1
    fi
    if [[ "$INPUT" = /* ]]; then
      ABS_PATH="$INPUT"
    else
      ABS_PATH="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
    fi
    echo "FIX_INPUT_TYPE=local-markdown"
    echo "FIX_INPUT_PATH=$ABS_PATH"
    echo "FIX_INPUT_EXISTS=true"
    ;;
  *)
    echo "无法识别修复输入来源: $INPUT" >&2
    exit 1
    ;;
esac
