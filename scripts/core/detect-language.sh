#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "CANDIDATE_LANGUAGE:none"; exit 0; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

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

# 仅 package.json 不算前端；必须有 react 依赖 + .tsx/.jsx 或 React JS/TS 入口证据
has_frontend() {
  local pkgs
  pkgs="$(find "$PROJECT_DIR" -maxdepth 3 \( "${PRUNE_PATHS[@]}" \) -prune -o -name 'package.json' -type f -print 2>/dev/null)"
  [ -n "$pkgs" ] || return 1
  local has_react=0 pkg
  while IFS= read -r pkg; do
    if grep -Eq '"react"\s*:\s*"[^"]+' "$pkg" 2>/dev/null; then
      has_react=1; break
    fi
  done <<< "$pkgs"
  [ "$has_react" -eq 1 ] || return 1
  # React 入口证据：TSX/JSX 直接成立；纯 JS/TS 项目需出现 React import/createElement 证据。
  find "$PROJECT_DIR" \( "${PRUNE_PATHS[@]}" \) -prune -o \( -name '*.tsx' -o -name '*.jsx' \) -print -quit 2>/dev/null | grep -q . && return 0
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    grep -Eq "from ['\"]react['\"]|require\\(['\"]react['\"]\\)|React\\.createElement|createElement\\(" "$src" 2>/dev/null && return 0
  done < <(find "$PROJECT_DIR" \( "${PRUNE_PATHS[@]}" \) -prune -o \( -name '*.ts' -o -name '*.js' \) -type f -print 2>/dev/null)
  return 1
}

emit() { printf 'CANDIDATE_LANGUAGE:%s|evidence=%s\n' "$1" "$2"; }

found=0
if has_java; then emit java "maven/gradle-or-java-source"; found=1; fi
if has_frontend; then emit frontend "react-dependency+tsx-jsx-or-js-ts-entry"; found=1; fi
if [ "$found" -eq 0 ]; then echo "CANDIDATE_LANGUAGE:none"; fi
exit 0
