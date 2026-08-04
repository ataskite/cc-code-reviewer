#!/bin/bash
set -euo pipefail

# 输出 Java 正式源码的绝对路径清单。可选 scope 使用 Maven 模块相对路径，
# 用于单 agent 存量审查同样冻结正式范围；测试和 target 仅作只读上下文。
PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_SCOPE="${2:-全量代码}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

is_full_scope() {
  case "$REVIEW_SCOPE" in ""|"全量代码"|"全量审查"|all|ALL) return 0 ;; esac
  return 1
}

collect_from_root() {
  find "$1" -path '*/src/main/java/*' -name '*.java' -not -path '*/target/*' \
    -not -path '*/__snapshots__/*' -not -path '*/testdata/*' -not -path '*/fixtures/*' \
    -not -name '*.generated.*' -not -name '*.gen.java' -type f -print 2>/dev/null
}

if is_full_scope; then
  collect_from_root "$PROJECT_DIR" | LC_ALL=C sort -u
  exit 0
fi

NORMALIZED="$(printf '%s' "$REVIEW_SCOPE" | perl -CS -Mutf8 -pe 's/[，、\s]+/,/g; s/^,+//; s/,+$//')"
IFS=',' read -r -a SELECTED_PATHS <<< "$NORMALIZED"
for selected in "${SELECTED_PATHS[@]}"; do
  selected="$(printf '%s' "$selected" | sed 's#^\./##; s#//*#/#g; s#/$##')"
  case "$selected" in ""|/*|..|../*|*/../*|*/..) echo "INVALID_SCOPE_PATH=$selected" >&2; exit 1 ;; esac
  candidate="$PROJECT_DIR/$selected"
  [ -d "$candidate" ] || { echo "SCOPE_PATH_NOT_FOUND=$selected" >&2; exit 1; }
  candidate="$(cd "$candidate" && pwd -P)"
  case "$candidate" in "$PROJECT_DIR"/*) ;; *) echo "SCOPE_PATH_OUTSIDE_PROJECT=$selected" >&2; exit 1 ;; esac
  collect_from_root "$candidate"
done | LC_ALL=C sort -u
