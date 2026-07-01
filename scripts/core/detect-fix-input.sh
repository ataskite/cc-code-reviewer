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
  http://*docx/*|https://*docx/*|http://*docs/*|https://*docs/*|http://*base/*|https://*base/*|http://*wiki/*|https://*wiki/*|base:*:*)
    echo "飞书云文档和飞书多维表格输入不得调用 core/detect-fix-input.sh；请使用 lark-doc 或 lark-base 读取并归一化问题清单" >&2
    exit 1
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
