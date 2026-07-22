#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
SOURCE_MANIFEST="${2:?请输入 source manifest 路径}"
REVIEW_SCOPE="${3:-全量代码}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
[ -f "$SOURCE_MANIFEST" ] || { echo "SOURCE_MANIFEST_NOT_FOUND=$SOURCE_MANIFEST" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

if [ "$REVIEW_SCOPE" = "全量代码" ]; then
  cat "$SOURCE_MANIFEST"
  exit 0
fi

SCOPE_FILE="$(mktemp "${TMPDIR:-/tmp}/fe-scope.XXXXXX")"
MATCH_FILE="$(mktemp "${TMPDIR:-/tmp}/fe-matches.XXXXXX")"
trap 'rm -f "$SCOPE_FILE" "$MATCH_FILE"' EXIT

printf '%s\n' "$REVIEW_SCOPE" |
  perl -CS -Mutf8 -pe 's/[，、,\s]+/\n/g' |
  sed 's#^\./##; s#//*#/#g; s#/$##; /^[[:space:]]*$/d' > "$SCOPE_FILE"

while IFS= read -r scope; do
  [ -n "$scope" ] || continue
  case "$scope" in
    /*|..|../*|*/..|*/../*)
      echo "FRONTEND_SCOPE_OUTSIDE_PROJECT=$scope" >&2
      exit 1
      ;;
  esac
done < "$SCOPE_FILE"

: > "$MATCH_FILE"
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in
    "$PROJECT_DIR"/*) rel="${file#$PROJECT_DIR/}" ;;
    *) continue ;;
  esac

  while IFS= read -r scope; do
    [ -n "$scope" ] || continue
    # 匹配模式（与 Python filter 对齐）：
    # - 完整 src 路径含包前缀（apps/web/src/api）：精确前缀匹配
    # - src/ 前缀短路径（src/api）：去掉 src/ 前缀当短名处理，匹配 src/api/* 和 */src/api/*
    # - 完整 flat 路径（myapp/api，含 / 但不含 src/）：精确前缀匹配
    # - 短名（api）：匹配 src/api/*、*/src/api/*、api/*（根级 flat 包）、*/api/*（包级 flat 子目录）
    if [[ "$scope" == */src/* ]]; then
      # 完整路径含 src/（如 apps/web/src/api）：精确前缀匹配
      case "$rel" in
        "$scope"/*) printf '%s\n' "$file" >> "$MATCH_FILE"; break ;;
      esac
    elif [[ "$scope" == src/* ]]; then
      # src/ 前缀短路径（如 src/api）：当短名处理
      sub="${scope#src/}"
      case "$rel" in
        "src/$sub"/*|*/"src/$sub"/*|"$sub"/*|*/"$sub"/*) printf '%s\n' "$file" >> "$MATCH_FILE"; break ;;
      esac
    elif [[ "$scope" == */* ]]; then
      # 完整 flat 路径: myapp/api
      case "$rel" in
        "$scope"/*) printf '%s\n' "$file" >> "$MATCH_FILE"; break ;;
      esac
    else
      # 短名: api
      sub="$scope"
      case "$rel" in
        "src/$sub"/*|*/"src/$sub"/*|"$sub"/*|*/"$sub"/*) printf '%s\n' "$file" >> "$MATCH_FILE"; break ;;
      esac
    fi
  done < "$SCOPE_FILE"
done < "$SOURCE_MANIFEST"

if [ ! -s "$MATCH_FILE" ]; then
  echo "NO_FRONTEND_SOURCE_FILES_AFTER_SCOPE=$REVIEW_SCOPE" >&2
  exit 1
fi

awk '!seen[$0]++' "$MATCH_FILE"
