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

SCOPE_FILE="$(mktemp "${TMPDIR:-/tmp}/py-scope.XXXXXX")"
MATCH_FILE="$(mktemp "${TMPDIR:-/tmp}/py-matches.XXXXXX")"
trap 'rm -f "$SCOPE_FILE" "$MATCH_FILE"' EXIT

printf '%s\n' "$REVIEW_SCOPE" |
  perl -CS -Mutf8 -pe 's/[，、,\s]+/\n/g' |
  sed 's#^\./##; s#//*#/#g; s#/$##; /^[[:space:]]*$/d' > "$SCOPE_FILE"

while IFS= read -r scope; do
  [ -n "$scope" ] || continue
  case "$scope" in
    /*|..|../*|*/..|*/../*)
      echo "PYTHON_SCOPE_OUTSIDE_PROJECT=$scope" >&2
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
    # src/<dir> 或 <dir> 匹配模式（与前端 filter 对齐）：
    # - 完整路径 src/api 匹配 src/api/... 和 */src/api/...
    # - 短名 api 匹配 */api/...（所有包下的 api 目录）
    if [[ "$scope" == */src/* ]]; then
      case "$rel" in
        "$scope"/*) printf '%s\n' "$file" >> "$MATCH_FILE"; break ;;
      esac
    else
      sub="${scope#src/}"
      case "$rel" in
        "src/$sub"/*|*/"src/$sub"/*) printf '%s\n' "$file" >> "$MATCH_FILE"; break ;;
      esac
    fi
  done < "$SCOPE_FILE"
done < "$SOURCE_MANIFEST"

if [ ! -s "$MATCH_FILE" ]; then
  echo "NO_PYTHON_SOURCE_FILES_AFTER_SCOPE=$REVIEW_SCOPE" >&2
  exit 1
fi

awk '!seen[$0]++' "$MATCH_FILE"
