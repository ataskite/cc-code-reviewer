#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PTYPE="$(bash "$SCRIPT_DIR/detect-project.sh" "$PROJECT_DIR" | sed -n 's/^PROJECT_TYPE=//p' | head -1)"
# 复用 detect-project.sh 的 Vue 信号纯函数，避免 TECH_STACK 信号与 detect 判定漂移
FE_DETECT_SOURCED=1 . "$SCRIPT_DIR/detect-project.sh"
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
done < <(find "$PROJECT_DIR" -maxdepth 3 -mindepth 1 \
  \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune -o \
  -name 'package.json' -type f -print 2>/dev/null | sort)

# 统计生产源码
FILE_COUNT="$(printf '%s\n' "$MANIFEST" | grep -c . || true)"
LINE_COUNT=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  LINE_COUNT=$((LINE_COUNT + $(wc -l < "$f" | tr -d ' ')))
done <<< "$MANIFEST"

# 正式配置 manifest（支持 package 边界内 package.json/tsconfig/vite/vue/webpack/babel 等配置）。
# 路径与计数必须来自同一份不可变清单，供 agent 按 FORMAL_CONFIG_FILE 精确读取。
collect_formal_config_files() {
  local root pkg_root
  for root in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
    pkg_root="${root%/src}"
    find "$pkg_root" -maxdepth 1 \
      -type f \( -name 'package.json' -o -name 'tsconfig.json' -o -name 'tsconfig.*.json' \
        -o -name 'vite.config.*' -o -name 'webpack.config.*' -o -name 'vue.config.*' \
        -o -name 'babel.config.*' \) -print 2>/dev/null
  done | sort -u
}

CONFIG_MANIFEST="$(collect_formal_config_files)"
CONFIG_COUNT="$(printf '%s\n' "$CONFIG_MANIFEST" | grep -c . || true)"

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

has_vue2_anywhere() {
  local pkg
  for pkg in "${PKGS[@]+"${PKGS[@]}"}"; do
    has_vue2_dep_signals "$pkg" && return 0
  done
  return 1
}

has_vue3_anywhere() {
  local pkg
  for pkg in "${PKGS[@]+"${PKGS[@]}"}"; do
    has_vue3_dep_signals "$pkg" && return 0
  done
  return 1
}

emit_package_value() {
  local field="$1" label="$2" pkg value
  for pkg in "${PKGS[@]+"${PKGS[@]}"}"; do
    value="$(perl -0777 -ne 'BEGIN { $field = shift @ARGV } if (/"\Q$field\E"\s*:\s*"([^"]+)"/s) { print $1; exit }' "$field" "$pkg" 2>/dev/null || true)"
    if [ -n "$value" ]; then
      printf 'RUNTIME_SIGNAL:%s|%s\n' "$label" "$value"
      return 0
    fi
  done
  return 1
}

emit_engines_node() {
  local pkg value
  for pkg in "${PKGS[@]+"${PKGS[@]}"}"; do
    value="$(perl -0777 -ne 'if (/"engines"\s*:\s*\{[^}]*"node"\s*:\s*"([^"]+)"/s) { print $1; exit }' "$pkg" 2>/dev/null || true)"
    if [ -n "$value" ]; then
      printf 'RUNTIME_SIGNAL:engines.node|%s\n' "$value"
      return 0
    fi
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
# CODE_INTELLIGENCE 占位：当前仅探测 typescript-lsp（tsserver 无法解析 .vue SFC 模板块）。
# Vue 语义增强（Volar / @vue/language-server）接线为二期，未完成前主 skill 按静态降级处理。
echo "CODE_INTELLIGENCE_PROVIDER=none"
echo "CODE_INTELLIGENCE_AVAILABLE=false"
echo "CODE_INTELLIGENCE_REASON=typescript-lsp-detection-pending"

for root in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
  echo "SOURCE_ROOT:formal|$(rel_path "$root")"
done
while IFS= read -r cfg; do
  [ -n "$cfg" ] && printf 'FORMAL_CONFIG_FILE:%s\n' "$cfg"
done <<< "$CONFIG_MANIFEST"
emit_components

# 技术栈（依赖证据）
if has_dep_anywhere "react"; then
  echo "TECH_STACK:React|dependency:react|rules:react"
fi
if has_dep_anywhere "react-router-dom"; then
  echo "TECH_STACK:React Router|dependency:react-router-dom|rules:react-router"
fi
if has_vue2_anywhere; then
  echo "TECH_STACK:Vue 2|dependency:vue@2/vue-template-compiler|rules:vue2"
fi
if has_vue3_anywhere; then
  echo "TECH_STACK:Vue 3|dependency:vue@3/@vitejs/plugin-vue|rules:vue3"
fi
if has_dep_anywhere "vue-router"; then
  echo "TECH_STACK:Vue Router|dependency:vue-router|rules:vue-router"
fi
if has_dep_anywhere "vuex"; then
  echo "TECH_STACK:Vuex|dependency:vuex|rules:vue2-state"
fi
if has_dep_anywhere "pinia"; then
  echo "TECH_STACK:Pinia|dependency:pinia|rules:vue3-state"
fi
if has_dep_anywhere "@vue/composition-api"; then
  echo "TECH_STACK:Vue2 Composition API|dependency:@vue/composition-api|rules:vue2-composition-api"
fi
if has_dep_anywhere "vue-class-component" || has_dep_anywhere "vue-property-decorator"; then
  echo "TECH_STACK:Vue Class Component|dependency:vue-class-component/vue-property-decorator|rules:vue2-class-component"
fi
if has_dep_anywhere "element-ui"; then
  echo "TECH_STACK:Element UI|dependency:element-ui|rules:vue2-enterprise-ui"
fi
if has_dep_anywhere "ant-design-vue"; then
  echo "TECH_STACK:Ant Design Vue|dependency:ant-design-vue|rules:vue-enterprise-ui"
fi
if [ "$PTYPE" = "node" ]; then
  echo "TECH_STACK:Node.js|dependency:package.json|rules:node-runtime"
fi
if has_dep_anywhere "express"; then
  echo "TECH_STACK:Express|dependency:express|rules:node-http"
fi
if has_dep_anywhere "koa"; then
  echo "TECH_STACK:Koa|dependency:koa|rules:node-http"
fi
if has_dep_anywhere "fastify"; then
  echo "TECH_STACK:Fastify|dependency:fastify|rules:node-http"
fi
if has_dep_anywhere "vite"; then
  echo "TECH_STACK:Vite|dependency:file:vite.config|rules:build-config"
elif has_dep_anywhere "webpack"; then
  echo "TECH_STACK:Webpack|dependency:file:webpack.config|rules:build-config"
fi

emit_package_value "type" "package.type" || true
emit_package_value "main" "package.main" || true
emit_package_value "exports" "package.exports" || true
emit_engines_node || true

# 源码范围声明
echo "SOURCE_SCOPE:formal|src/**/*.ts"
echo "SOURCE_SCOPE:formal|src/**/*.tsx"
echo "SOURCE_SCOPE:formal|src/**/*.js"
echo "SOURCE_SCOPE:formal|src/**/*.jsx"
echo "SOURCE_SCOPE:formal|src/**/*.vue"
echo "SOURCE_SCOPE:formal|src/**/*.mjs"
echo "SOURCE_SCOPE:formal|src/**/*.cjs"
echo "SOURCE_SCOPE:context|**/*.test.tsx"
echo "SOURCE_SCOPE:context|**/*.test.vue"
echo "SOURCE_SCOPE:context|**/*.d.ts"
echo "SOURCE_SCOPE:excluded|node_modules/**"
echo "SOURCE_SCOPE:excluded|dist/**"
echo "SOURCE_SCOPE:excluded|build/**"
exit 0
