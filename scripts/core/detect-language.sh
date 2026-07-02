#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "CANDIDATE_LANGUAGE:none"; exit 0; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 统一的排除目录（不使用 eval：直接作为 find 的位置参数）
PRUNE_PATHS=(
  -path '*/node_modules/*' -o
  -path '*/target/*' -o
  -path '*/build/*' -o
  -path '*/dist/*' -o
  -path '*/.git/*'
)

has_java() {
  [ -f "$PROJECT_DIR/pom.xml" ] && return 0
  find "$PROJECT_DIR" -maxdepth 1 -name 'build.gradle*' -type f -print -quit 2>/dev/null | grep -q . && return 0
  find "$PROJECT_DIR" \( "${PRUNE_PATHS[@]}" \) -prune -o -name '*.java' -print -quit 2>/dev/null | grep -q .
}

# 复用 frontend adapter 的项目类型识别，避免 React/Vue/Node 支持边界在两处漂移。
has_frontend() {
  local out ptype
  out="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$PROJECT_DIR" 2>/dev/null || true)"
  ptype="$(printf '%s\n' "$out" | sed -n 's/^PROJECT_TYPE=//p' | cut -d'|' -f1 | head -1)"
  case "$ptype" in
    frontend-react|frontend-vue2|frontend-vue3|node) return 0 ;;
  esac
  return 1
}

emit() { printf 'CANDIDATE_LANGUAGE:%s|evidence=%s\n' "$1" "$2"; }

found=0
if has_java; then emit java "maven/gradle-or-java-source"; found=1; fi
if has_frontend; then emit frontend "react-vue-node-supported-project"; found=1; fi
if [ "$found" -eq 0 ]; then echo "CANDIDATE_LANGUAGE:none"; fi
exit 0
