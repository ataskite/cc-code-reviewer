#!/bin/bash
# 前端项目类型识别器：frontend-react / frontend-vue2 / frontend-vue3 / node / frontend-unsupported。
#
# 可被 collect-source-files.sh source 以复用 Vue 依赖信号纯函数，避免两处信号漂移：
#   FE_DETECT_SOURCED=1 . "$SCRIPT_DIR/detect-project.sh"
# 被 source 时（FE_DETECT_SOURCED=1）只定义顶部纯函数，整体跳过主判定流程，
# 防止本脚本的 exit / set -euo pipefail 影响调用方。
#
# 判定优先级（Vue 优先策略，与 AGENTS.md「Vue2 legacy 重点支持」声明一致）：
#   next/nuxt 拒绝 → Vue2 → Vue3 → Vue 兜底(版本不明确) → Vue 纯内容回退
#   → React → Node → generic-tsjs 拒绝
# React 与 Vue 信号共存时，按实际 Vue 制品（.vue SFC / Vue API / Vue import）判 Vue，
# 避免公司 monorepo 中 react + vue 共存时 Vue 项目被 React 抢占。

# ====== sourceable 纯函数（参数为单个 package.json 路径，不依赖 PROJECT_DIR 全局）======

has_dep_in_pkg() {
  # $1 = package.json 路径, $2 = 依赖名（精确匹配 JSON key）
  grep -Eq "\"${2}\"\s*:\s*\"[^\"]+\"" "$1" 2>/dev/null
}

# Vue 2 依赖信号：vue@2 / vue-template-compiler / @vue/cli-service / vuex@3 / vue-router@3
#                 / vue-loader@15 / vite-plugin-vue2 / @vue/composition-api / class component decorators
has_vue2_dep_signals() {
  local pkg="$1"
  has_dep_in_pkg "$pkg" "vue-template-compiler" && return 0
  has_dep_in_pkg "$pkg" "@vue/cli-service" && return 0
  has_dep_in_pkg "$pkg" "vite-plugin-vue2" && return 0
  has_dep_in_pkg "$pkg" "@vue/composition-api" && return 0
  has_dep_in_pkg "$pkg" "vue-class-component" && return 0
  has_dep_in_pkg "$pkg" "vue-property-decorator" && return 0
  has_dep_in_pkg "$pkg" "vuex" && grep -Eq '"vuex"\s*:\s*"[~^<>= ]*3\.' "$pkg" 2>/dev/null && return 0
  has_dep_in_pkg "$pkg" "vue-router" && grep -Eq '"vue-router"\s*:\s*"[~^<>= ]*3\.' "$pkg" 2>/dev/null && return 0
  has_dep_in_pkg "$pkg" "vue-loader" && grep -Eq '"vue-loader"\s*:\s*"[~^<>= ]*15\.' "$pkg" 2>/dev/null && return 0
  grep -Eq '"vue"\s*:\s*"[~^<>= ]*2\.' "$pkg" 2>/dev/null
}

# Vue 3 依赖信号：vue@3 / @vitejs/plugin-vue / @vue/compiler-sfc / pinia / vue-router@4
#                 / vue-loader@16|17 / @vue/language-server
has_vue3_dep_signals() {
  local pkg="$1"
  has_dep_in_pkg "$pkg" "@vitejs/plugin-vue" && return 0
  has_dep_in_pkg "$pkg" "@vue/compiler-sfc" && return 0
  has_dep_in_pkg "$pkg" "pinia" && return 0
  has_dep_in_pkg "$pkg" "@vue/language-server" && return 0
  has_dep_in_pkg "$pkg" "vue-router" && grep -Eq '"vue-router"\s*:\s*"[~^<>= ]*4\.' "$pkg" 2>/dev/null && return 0
  has_dep_in_pkg "$pkg" "vue-loader" && grep -Eq '"vue-loader"\s*:\s*"[~^<>= ]*1[67]\.' "$pkg" 2>/dev/null && return 0
  grep -Eq '"vue"\s*:\s*"[~^<>= ]*3\.' "$pkg" 2>/dev/null
}

# 任意 Vue 依赖信号（collect-source-files.sh 源码根闸门用：版本无关，含 vue 相关包即视为受支持 package）
has_vue_dep_signals() {
  local pkg="$1"
  has_vue2_dep_signals "$pkg" && return 0
  has_vue3_dep_signals "$pkg" && return 0
  has_dep_in_pkg "$pkg" "vue" && return 0
  has_dep_in_pkg "$pkg" "vue-router" && return 0
  has_dep_in_pkg "$pkg" "vuex" && return 0
  return 1
}

# ====== 主判定流程（仅直接执行时运行；被 source 时整体跳过）======
if [ "${FE_DETECT_SOURCED:-0}" != "1" ]; then
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 收集所有候选 package.json（根 + maxdepth 3，排除 node_modules/dist/build/.git）
PKGS="$(find "$PROJECT_DIR" -maxdepth 3 -mindepth 1 \
  \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
  -o -name 'package.json' -type f -print 2>/dev/null)"

has_dep_anywhere() {
  local dep="$1" p
  [ -n "${PKGS:-}" ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    has_dep_in_pkg "$p" "$dep" && return 0
  done <<< "$PKGS"
  return 1
}

has_node_pkg() {
  local pkg="$1"
  grep -Eq '"engines"\s*:\s*\{[^}]*"node"\s*:' "$pkg" 2>/dev/null && return 0
  grep -Eq '"type"\s*:\s*"(module|commonjs)"' "$pkg" 2>/dev/null && return 0
  grep -Eq '"(main|exports)"\s*:' "$pkg" 2>/dev/null && return 0
  grep -Eq '"(express|koa|fastify|@nestjs/core|hapi|@hapi/hapi|egg|prisma|mongoose|sequelize)"\s*:\s*"' "$pkg" 2>/dev/null
}

has_node_source() {
  find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
    -o \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) -type f -print -quit 2>/dev/null | grep -q .
}

# --- Vue 目录级辅助函数（依赖 PROJECT_DIR）---

# .vue SFC 存在
has_vue_sfc_anywhere() {
  find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
    -o -name '*.vue' -type f -print -quit 2>/dev/null | grep -q .
}

# Vue import 内容信号（from 'vue' / require('vue')）：证明项目实际使用 vue，不区分版本
has_vue_import_anywhere() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "from ['\"]vue['\"]|require\s*\(\s*['\"]vue['\"]" "$f" 2>/dev/null && return 0
  done < <(find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
    -o \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue' \) -type f -print 2>/dev/null)
  return 1
}

# Vue3 内容信号（createApp / defineAsyncComponent / <script setup>）：用于无版本依赖时的版本判定。
# 该函数本身不单独证明项目是 Vue；调用方必须同时要求 Vue 制品证据，避免普通 helper
# 函数名（如 defineComponent）把通用 TS/Node 项目误判为 Vue。
has_vue3_content_anywhere() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "createApp\s*\(|createSSRApp\s*\(|defineComponent\s*\(|defineAsyncComponent\s*\(|<script[[:space:]][^>]*setup" "$f" 2>/dev/null && return 0
  done < <(find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
    -o \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue' \) -type f -print 2>/dev/null)
  return 1
}

# Vue2 内容信号（new Vue( / Vue.extend( / Vue.component(）：纯 Vue2 API
has_vue2_content_anywhere() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "new[[:space:]]+Vue\s*\(|Vue\.extend\s*\(|Vue\.component\s*\(" "$f" 2>/dev/null && return 0
  done < <(find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
    -o \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue' \) -type f -print 2>/dev/null)
  return 1
}

# Vue 制品证据：.vue SFC 或 Vue import 内容（用于确认项目确有 Vue 代码，不仅是有依赖）
has_vue_artifact_anywhere() {
  has_vue_sfc_anywhere && return 0
  has_vue_import_anywhere && return 0
  return 1
}

# 任意 vue 依赖信号（跨所有 package.json）
has_any_vue_dep_anywhere() {
  local p
  [ -n "${PKGS:-}" ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    has_vue_dep_signals "$p" && return 0
  done <<< "$PKGS"
  return 1
}

# 不支持：next / nuxt（首期不支持 Next.js / Nuxt）
if has_dep_anywhere "next"; then
  echo "PROJECT_TYPE=frontend-unsupported|reason=nextjs"; exit 0
fi
if has_dep_anywhere "nuxt"; then
  echo "PROJECT_TYPE=frontend-unsupported|reason=nuxt"; exit 0
fi

# ===== Vue 优先判定（Vue2 legacy 优先 + Vue3）=====
# Vue 2：版本依赖信号 + Vue 制品证据（.vue SFC 或 Vue import 内容）
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  if has_vue2_dep_signals "$pkg" && has_vue_artifact_anywhere; then
    echo "PROJECT_TYPE=frontend-vue2"; exit 0
  fi
done <<< "$PKGS"

# Vue 3：版本依赖信号 + Vue 制品证据
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  if has_vue3_dep_signals "$pkg" && has_vue_artifact_anywhere; then
    echo "PROJECT_TYPE=frontend-vue3"; exit 0
  fi
done <<< "$PKGS"

# Vue 兜底：任意 vue 依赖 + Vue 制品，但版本信号不明确（如 vue@* 无版本锁）
# → 用 Vue3/Vue2 内容 API 定版本；内容也无法区分时按 legacy 优先判 Vue2。
if has_any_vue_dep_anywhere && has_vue_artifact_anywhere; then
  if has_vue3_content_anywhere; then
    echo "PROJECT_TYPE=frontend-vue3"; exit 0
  fi
  echo "PROJECT_TYPE=frontend-vue2"; exit 0
fi

# 纯内容回退：无 vue 依赖记录（可能 hoist 到 lockfile 或漏写依赖）但代码确实是 Vue。
# 必须同时存在 .vue SFC 或 Vue import/require 证据；不能仅凭同名 API 调用判 Vue。
if has_vue_artifact_anywhere; then
  if has_vue3_content_anywhere; then
    echo "PROJECT_TYPE=frontend-vue3"; exit 0
  fi
  if has_vue2_content_anywhere; then
    echo "PROJECT_TYPE=frontend-vue2"; exit 0
  fi
  if has_vue_sfc_anywhere; then
    echo "PROJECT_TYPE=frontend-vue2"; exit 0
  fi
fi

# ===== React（Vue 信号均不命中后再判 React）=====
has_react=0
if has_dep_anywhere "react"; then has_react=1; fi

if [ "$has_react" -eq 1 ]; then
if find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
    -o \( -name '*.tsx' -o -name '*.jsx' \) -print -quit 2>/dev/null | grep -q .; then
    echo "PROJECT_TYPE=frontend-react"; exit 0
  fi
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    if grep -Eq "from ['\"]react['\"]|require\\(['\"]react['\"]\\)|React\\.createElement|createElement\\(" "$src" 2>/dev/null; then
      echo "PROJECT_TYPE=frontend-react"; exit 0
    fi
  done < <(find "$PROJECT_DIR" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
    -o \( -name '*.ts' -o -name '*.js' \) -type f -print 2>/dev/null)
fi

# ===== Node =====
while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  if has_node_pkg "$pkg" && has_node_source; then
    echo "PROJECT_TYPE=node"; exit 0
  fi
done <<< "$PKGS"

# 有 TS/JS/Vue 但无受支持技术栈 → 通用 TS/JS，暂不套用专项规则
  if find "$PROJECT_DIR" -mindepth 1 \
  \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune \
  -o \( -name '*.ts' -o -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue' \) -print -quit 2>/dev/null | grep -q .; then
  echo "PROJECT_TYPE=frontend-unsupported|reason=generic-tsjs"; exit 0
fi

echo "PROJECT_TYPE=frontend-unsupported|reason=no-frontend-evidence"
exit 0
fi
# ====== 主判定流程结束（被 source 时从此处之后无内容）======
