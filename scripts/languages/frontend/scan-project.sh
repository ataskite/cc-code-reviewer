#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PTYPE="$(bash "$SCRIPT_DIR/detect-project.sh" "$PROJECT_DIR" | sed -n 's/^PROJECT_TYPE=//p' | head -1)"
rel_path() { printf '%s\n' "${1#$PROJECT_DIR/}"; }

SOURCE_ROOTS=()
MANIFEST="$(bash "$SCRIPT_DIR/collect-source-files.sh" "$PROJECT_DIR")"
while IFS= read -r file; do
  [ -n "$file" ] || continue
  root="${file%/src/*}/src"
  [ -d "$root" ] || continue
  root="$(cd "$root" && pwd -P)"
  found=0
  for existing in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
    [ "$existing" = "$root" ] && { found=1; break; }
  done
  [ "$found" -eq 0 ] && SOURCE_ROOTS+=("$root")
done <<< "$MANIFEST"

PKGS=()
while IFS= read -r pkg; do
  [ -n "$pkg" ] && PKGS+=("$pkg")
done < <(find "$PROJECT_DIR" -maxdepth 3 \
  \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune -o \
  -name 'package.json' -type f -print 2>/dev/null | sort)

# 统计生产源码
FILE_COUNT="$(printf '%s\n' "$MANIFEST" | grep -c . || true)"
LINE_COUNT=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  LINE_COUNT=$((LINE_COUNT + $(wc -l < "$f" | tr -d ' ')))
done <<< "$MANIFEST"

# 正式配置文件计数（React package 边界内 package.json/tsconfig/vite.config/webpack.config）
CONFIG_COUNT=0
for root in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
  pkg_root="${root%/src}"
  while IFS= read -r cfg; do
    [ -n "$cfg" ] && CONFIG_COUNT=$((CONFIG_COUNT+1))
  done < <(find "$pkg_root" -maxdepth 1 \
    -type f \( -name 'package.json' -o -name 'tsconfig.json' -o -name 'tsconfig.*.json' \
      -o -name 'vite.config.*' -o -name 'webpack.config.*' \) -print 2>/dev/null)
done

# 组件维度（每个 source root 下顶层目录作为粗粒度 COMPONENT）
# 复用 collect-source-files.sh 的同一口径：对项目根调用一次得到完整 manifest，
# 再按 src 下各顶层目录过滤计数，保证 COMPONENT 计数与 SOURCE_FILE_COUNT 一致
emit_components() {
  local full_manifest
  full_manifest="$(bash "$SCRIPT_DIR/collect-source-files.sh" "$PROJECT_DIR" 2>/dev/null)"
  local root d
  for root in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      local rel="${d#$PROJECT_DIR/}"
      local cnt=0 ln=0 f
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        # 仅统计位于该顶层组件目录内的文件（路径前缀匹配 + 边界）
        case "$f" in
          "$d"/*)
            cnt=$((cnt+1))
            ln=$((ln + $(wc -l < "$f" | tr -d ' ')))
            ;;
        esac
      done <<< "$full_manifest"
      if [ "$cnt" -gt 0 ]; then
        printf 'COMPONENT:%s|%s|%s|%s\n' "$(basename "$rel")" "$rel" "$cnt" "$ln"
      fi
    done < <(find "$root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  done
}

has_dep_anywhere() {
  local dep="$1" pkg
  for pkg in "${PKGS[@]+"${PKGS[@]}"}"; do
    grep -Eq "\"${dep}\"\s*:\s*\"[^\"]+\"" "$pkg" 2>/dev/null && return 0
  done
  return 1
}

# 输出 PROFILE_SCHEMA v1
echo "PROFILE_SCHEMA_VERSION=1"
echo "LANGUAGE_ID=frontend"
echo "PROJECT_TYPE=$PTYPE"
echo "SOURCE_FILE_COUNT=$FILE_COUNT"
echo "SOURCE_LINE_COUNT=$LINE_COUNT"
echo "FORMAL_CONFIG_FILE_COUNT=$CONFIG_COUNT"
# CODE_INTELLIGENCE 占位：detect-code-intelligence.sh 在 Task 4 接入后由主 skill 覆盖
echo "CODE_INTELLIGENCE_PROVIDER=none"
echo "CODE_INTELLIGENCE_AVAILABLE=false"
echo "CODE_INTELLIGENCE_REASON=typescript-lsp-detection-pending"

for root in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
  echo "SOURCE_ROOT:formal|$(rel_path "$root")"
done
emit_components

# 技术栈（依赖证据）
if has_dep_anywhere "react"; then
  echo "TECH_STACK:React|dependency:react|rules:react"
fi
if has_dep_anywhere "react-router-dom"; then
  echo "TECH_STACK:React Router|dependency:react-router-dom|rules:react-router"
fi
if has_dep_anywhere "vite"; then
  echo "TECH_STACK:Vite|dependency:file:vite.config|rules:build-config"
elif has_dep_anywhere "webpack"; then
  echo "TECH_STACK:Webpack|dependency:file:webpack.config|rules:build-config"
fi

# 源码范围声明
echo "SOURCE_SCOPE:formal|src/**/*.ts"
echo "SOURCE_SCOPE:formal|src/**/*.tsx"
echo "SOURCE_SCOPE:formal|src/**/*.js"
echo "SOURCE_SCOPE:formal|src/**/*.jsx"
echo "SOURCE_SCOPE:context|**/*.test.tsx"
echo "SOURCE_SCOPE:context|**/*.d.ts"
echo "SOURCE_SCOPE:excluded|node_modules/**"
echo "SOURCE_SCOPE:excluded|dist/**"
echo "SOURCE_SCOPE:excluded|build/**"
exit 0
