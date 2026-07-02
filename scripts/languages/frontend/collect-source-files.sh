#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 正式生产源码口径：仅 src/（及适配器确认的应用源码目录）内的生产 .ts/.tsx/.js/.jsx/.vue/.mjs/.cjs。
# 不遍历项目根：根级配置脚本（vite.config.ts/jest.config.ts/.eslintrc.js 等）、
# 非 src 目录（scripts/ tools/）、生成代码、测试、node_modules、dist/build 均不计入正式源码。
# .d.ts 是类型声明（只读上下文，spec 7.2），不计入正式源码。
#
# Vue 信号复用 detect-project.sh 的纯函数（避免两处信号漂移）：
# 之前只认字面 "vue" key，会漏掉 vue 依赖被 hoist 的 monorepo package
# （该 package 顶层无 "vue" 但有 @vitejs/plugin-vue/pinia），导致 source manifest 为空、静默零覆盖。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FE_DETECT_SOURCED=1 . "$SCRIPT_DIR/detect-project.sh"

has_react_dep() {
  grep -Eq '"react"\s*:\s*"[^"]+' "$1" 2>/dev/null
}
has_vue_dep() {
  # 与 detect-project.sh 的 Vue 依赖信号一致：版本无关，含任意 vue 相关包即视为受支持 package
  has_vue_dep_signals "$1"
}
has_node_signal() {
  grep -Eq '"engines"\s*:\s*\{[^}]*"node"\s*:' "$1" 2>/dev/null && return 0
  grep -Eq '"type"\s*:\s*"(module|commonjs)"' "$1" 2>/dev/null && return 0
  grep -Eq '"(main|exports)"\s*:' "$1" 2>/dev/null && return 0
  grep -Eq '"(express|koa|fastify|@nestjs/core|hapi|@hapi/hapi|egg|prisma|mongoose|sequelize)"\s*:\s*"' "$1" 2>/dev/null
}
has_supported_package() {
  has_react_dep "$1" && return 0
  has_vue_dep "$1" && return 0
  has_node_signal "$1"
}
has_unsupported_meta_framework() {
  grep -Eq '"(next|nuxt)"\s*:\s*"[^"]+' "$1" 2>/dev/null
}
source_root_has_production_files() {
  [ -d "$1" ] || return 1
  find "$1" \
    \( \
      -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \
      -o -path '*/.git/*' -o -path '*/.next/*' -o -path '*/.nuxt/*' \
    \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.vue' -o -name '*.mjs' -o -name '*.cjs' \) \
    -not -name '*.d.ts' \
    -not -name '*.test.ts' -not -name '*.test.tsx' -not -name '*.test.js' -not -name '*.test.jsx' -not -name '*.test.vue' \
    -not -name '*.spec.ts' -not -name '*.spec.tsx' -not -name '*.spec.js' -not -name '*.spec.jsx' -not -name '*.spec.vue' \
    -not -path '*/__tests__/*' -not -path '*/e2e/*' -not -path '*/cypress/*' \
    -not -name '*.min.js' -not -name '*.bundle.js' \
    -print -quit 2>/dev/null | grep -q .
}
source_root_has_react_code() {
  [ -d "$1" ] || return 1
  find "$1" \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \) -prune -o \
    \( -name '*.tsx' -o -name '*.jsx' \) -type f -print -quit 2>/dev/null | grep -q . && return 0
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "from ['\"]react['\"]|require\\(['\"]react['\"]\\)|React\\.createElement|createElement\\(" "$f" 2>/dev/null && return 0
  done < <(find "$1" \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \) -prune -o \
    \( -name '*.ts' -o -name '*.js' \) -type f -print 2>/dev/null)
  return 1
}
source_root_has_vue_code() {
  [ -d "$1" ] || return 1
  find "$1" \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \) -prune -o \
    -name '*.vue' -type f -print -quit 2>/dev/null | grep -q . && return 0
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "from ['\"]vue['\"]|require\s*\(\s*['\"]vue['\"]|<script[[:space:]][^>]*setup" "$f" 2>/dev/null && return 0
  done < <(find "$1" \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \) -prune -o \
    \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue' \) -type f -print 2>/dev/null)
  return 1
}
source_root_has_node_code() {
  [ -d "$1" ] || return 1
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "from ['\"](express|koa|fastify|@nestjs/core|hapi|@hapi/hapi|egg)['\"]|require\\(['\"](express|koa|fastify|@nestjs/core|hapi|@hapi/hapi|egg)['\"]\\)" "$f" 2>/dev/null && return 0
  done < <(find "$1" \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \) -prune -o \
    \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -type f -print 2>/dev/null)
  return 1
}
source_root_has_supported_code() {
  source_root_has_react_code "$1" && return 0
  source_root_has_vue_code "$1" && return 0
  source_root_has_node_code "$1"
}
add_source_root() {
  local root="$1" existing exists
  [ -d "$root" ] || return 0
  source_root_has_production_files "$root" || return 0
  root="$(cd "$root" && pwd -P)"
  exists=0
  for existing in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
    [ "$existing" = "$root" ] && { exists=1; break; }
  done
  if [ "$exists" -eq 0 ]; then
    SOURCE_ROOTS+=("$root")
  fi
}

SOURCE_ROOTS=()
ROOT_HAS_SUPPORTED_PACKAGE=0
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  if has_unsupported_meta_framework "$pkg"; then
    continue
  fi
  pkg_root="$(cd "$(dirname "$pkg")" && pwd -P)"
  if has_supported_package "$pkg"; then
    [ "$pkg_root" = "$PROJECT_DIR" ] && ROOT_HAS_SUPPORTED_PACKAGE=1
    add_source_root "$pkg_root/src"
    continue
  fi
  if source_root_has_supported_code "$pkg_root/src"; then
    [ "$pkg_root" = "$PROJECT_DIR" ] && ROOT_HAS_SUPPORTED_PACKAGE=1
    add_source_root "$pkg_root/src"
  fi
done < <(find "$PROJECT_DIR" -maxdepth 3 \
  \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune -o \
  -name 'package.json' -type f -print 2>/dev/null | sort)

if [ "$ROOT_HAS_SUPPORTED_PACKAGE" -eq 1 ]; then
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    if has_unsupported_meta_framework "$pkg"; then
      continue
    fi
    pkg_root="$(cd "$(dirname "$pkg")" && pwd -P)"
    if has_supported_package "$pkg" || source_root_has_supported_code "$pkg_root/src"; then
      add_source_root "$pkg_root/src"
    fi
  done < <(find "$PROJECT_DIR" -maxdepth 3 \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune -o \
    -name 'package.json' -type f -print 2>/dev/null | sort)
fi

[ "${#SOURCE_ROOTS[@]}" -gt 0 ] || exit 0

for root in "${SOURCE_ROOTS[@]}"; do
  find "$root" \
    \( \
      -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \
      -o -path '*/.git/*' -o -path '*/.next/*' -o -path '*/.nuxt/*' \
    \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.vue' -o -name '*.mjs' -o -name '*.cjs' \) \
    -not -name '*.d.ts' \
    -not -name '*.test.ts' -not -name '*.test.tsx' -not -name '*.test.js' -not -name '*.test.jsx' -not -name '*.test.vue' \
    -not -name '*.spec.ts' -not -name '*.spec.tsx' -not -name '*.spec.js' -not -name '*.spec.jsx' -not -name '*.spec.vue' \
    -not -path '*/__tests__/*' -not -path '*/e2e/*' -not -path '*/cypress/*' \
    -not -name '*.min.js' -not -name '*.bundle.js' \
    -print 2>/dev/null
done | sort
