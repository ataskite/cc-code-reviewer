#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 正式生产源码口径（两层）：
# 1) src/（及适配器确认的应用源码目录）内的生产 .ts/.tsx/.js/.jsx/.vue/.mjs/.cjs；
# 2) BFF server-root 层（v1.7.0）：受支持 package 中位于项目根与一级子目录的
#    Node 服务端 .js/.mjs/.cjs。老式 BFF 脚手架（express/superagent 时代）的
#    服务端代码不在 src/ 下，src-only 口径会静默漏掉中继/鉴权/会话等漏洞主体文件。
#    server 层按信号门控发现，不做根级 JS 全收：
#    - 包级合格：package.json main / scripts.{start,dev} 入口指向 src 外真实 JS 文件，
#      或包根（剪枝噪声目录与配置 basename 后）存在强服务端信号文件；
#    - 收集范围：根级 .js/.mjs/.cjs（排除构建/测试配置 basename）+ 一级非噪声目录
#      （全深度）内带模块信号（require(/module.exports/exports.）的 .js/.mjs/.cjs；
#    - .ts 不入 server 层（现代 TS BFF 位于 src，由 src 管线覆盖），
#      根级配置脚本（vite.config.ts/jest.config.ts/.eslintrc.js 等）与 scripts/、
#      tools/ 等非服务端目录仍一律排除；.d.ts 仍不计入正式源码。
#    上限 CC_CODE_REVIEWER_SERVER_ROOT_LIMIT（默认 200，0=禁用），并入数以 stderr
#    的 SERVER_ROOTS_ADDED=N 披露。
#
# 伴随文件层例外：受支持 package 本地的 package.json 会并入清单（见文件末尾），
# 用于支撑 scripts/core/filetype-rule-map.json 的 npm-package 模式；根级配置脚本
# 与其他非服务端文件仍一律排除。实际并入数以 stderr 的 COMPANION_FILES_ADDED=N 披露。
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
  find "$1" -mindepth 1 \
    \( \
      -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name 'coverage' \
        -o -name '__snapshots__' -o -name 'testdata' -o -name 'fixtures' \
        -o -name '.git' -o -name '.next' -o -name '.nuxt' \) \
    \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.vue' -o -name '*.mjs' -o -name '*.cjs' \) \
    -not -name '*.d.ts' \
    -not -name '*.test.ts' -not -name '*.test.tsx' -not -name '*.test.js' -not -name '*.test.jsx' -not -name '*.test.vue' \
    -not -name '*.spec.ts' -not -name '*.spec.tsx' -not -name '*.spec.js' -not -name '*.spec.jsx' -not -name '*.spec.vue' \
    -not -path '*/__tests__/*' -not -path '*/__snapshots__/*' -not -path '*/testdata/*' -not -path '*/fixtures/*' -not -path '*/e2e/*' -not -path '*/cypress/*' \
    -not -name '*.generated.*' \
    -not -name '*.min.js' -not -name '*.bundle.js' \
    -print -quit 2>/dev/null | grep -q .
}
source_root_has_react_code() {
  [ -d "$1" ] || return 1
  find "$1" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name 'coverage' -o -name '__snapshots__' -o -name 'testdata' -o -name 'fixtures' \) \) -prune -o \
    \( -name '*.tsx' -o -name '*.jsx' \) -type f -print -quit 2>/dev/null | grep -q . && return 0
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "from ['\"]react['\"]|require\\(['\"]react['\"]\\)|React\\.createElement|createElement\\(" "$f" 2>/dev/null && return 0
  done < <(find "$1" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name 'coverage' -o -name '__snapshots__' -o -name 'testdata' -o -name 'fixtures' \) \) -prune -o \
    \( -name '*.ts' -o -name '*.js' \) -type f -print 2>/dev/null)
  return 1
}
source_root_has_vue_code() {
  [ -d "$1" ] || return 1
  find "$1" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name 'coverage' -o -name '__snapshots__' -o -name 'testdata' -o -name 'fixtures' \) \) -prune -o \
    -name '*.vue' -type f -print -quit 2>/dev/null | grep -q . && return 0
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "from ['\"]vue['\"]|require\s*\(\s*['\"]vue['\"]|<script[[:space:]][^>]*setup" "$f" 2>/dev/null && return 0
  done < <(find "$1" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name 'coverage' -o -name '__snapshots__' -o -name 'testdata' -o -name 'fixtures' \) \) -prune -o \
    \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.vue' \) -type f -print 2>/dev/null)
  return 1
}
source_root_has_node_code() {
  [ -d "$1" ] || return 1
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -Eq "from ['\"](express|koa|fastify|@nestjs/core|hapi|@hapi/hapi|egg)['\"]|require\\(['\"](express|koa|fastify|@nestjs/core|hapi|@hapi/hapi|egg)['\"]\\)" "$f" 2>/dev/null && return 0
  done < <(find "$1" -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name 'coverage' \) \) -prune -o \
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

# ===== BFF server-root 层（信号门控发现，见文件头注释）=====

# 一级噪声目录：按目录名排除与「包根服务端代码」无关的目录。
# *mock* 涵盖 devMock；test*/*shell 涵盖 testshell/onlineshell 等环境脚本目录；
# vite*/webpack*/static* 为构建工具与 gulp 插件目录（实测含 require( 弱信号）。
# src 在此名单中：server 层专指 src 之外的服务端代码，且避免与 src 管线重复收集。
server_is_noise_dir() {
  case "$(basename "$1")" in
    node_modules|dist|build|coverage|.git|src|\
    *mock*|test*|*shell|sdk*|tpl*|doc*|static*|assets|public|data*|vite*|webpack*)
      return 0
      ;;
  esac
  return 1
}

# 根级构建/测试配置 basename 黑名单（仅作用于包根 maxdepth-1 文件）。
# 实测补充：dev.webpack.js 含 require('express')（webpack dev server）、
# babel.js 是 gulp babel 插件、archive.js 是 zip 打包脚本——均属构建工具而非服务端代码。
server_is_config_basename() {
  case "$(basename "$1")" in
    gulpfile*|*.config.js|*.config.mjs|*.config.cjs|\
    webpack*|*.webpack.js|jest*|vitest*|karma*|rollup*|\
    .eslintrc*|.babelrc*|babel*|postcss*|eslint*|prettier*|archive*)
      return 0
      ;;
  esac
  return 1
}

# 强服务端信号：express/koa/fastify 依赖、服务启动、路由声明、框架路由注解
# （[Rr]equestMapping 覆盖 thinkJS 的 this.RequestMapping 大写变体）。
server_has_strong_signal() {
  grep -Eqi "require\\(['\"](express|koa|fastify|@nestjs/core|hapi|@hapi/hapi|egg)['\"]\\)|express\\(\\)|\\.listen\\(|createServer|router\\.(get|post|put|delete|all|use)\\(|requestMapping" "$1" 2>/dev/null
}

# 弱模块信号：Node 模块形态（require / module.exports / exports.）。
server_has_weak_signal() {
  grep -Eq "require\\(|module\\.exports|exports\\." "$1" 2>/dev/null
}

# package.json 入口信号：main 与 scripts.{start,dev} 中「node 后首个非 flag 参数」
# （或 main 直值）指向 src 外真实存在的 JS 文件（含无扩展名的 ./bin/www 形态，
# 依次回退 +.js/+.mjs/+.cjs）。解析失败即不命中，向强信号兜底（fail-closed）。
pkg_entry_hits_server() {
  local pkg="$1" entry cand
  [ -f "$pkg/package.json" ] || return 1
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      /*|../*|src/*|./src/*|*/src/*) continue ;;
    esac
    case "$entry" in
      ./*) entry="${entry#./}" ;;
    esac
    for cand in "$entry" "${entry}.js" "${entry}.mjs" "${entry}.cjs"; do
      [ -f "$pkg/$cand" ] && return 0
    done
  done < <(perl -ne '
    if (/"main"\s*:\s*"([^"]+)"/) { print "$1\n" }
    while (/"(start|dev)"\s*:\s*"([^"]+)"/g) {
      my @t = split /\s+|&&/, $2;
      for (my $i = 0; $i < @t; $i++) {
        next unless $t[$i] =~ /^(node|nodemon)$/;
        for (my $j = $i + 1; $j < @t; $j++) {
          next if $t[$j] =~ /^-+/;
          print "$t[$j]\n";
          last;
        }
      }
    }
  ' "$pkg/package.json" 2>/dev/null)
  return 1
}

# 包级合格：入口信号命中，或包根（剪枝噪声目录与配置 basename 后，一级目录全深度）
# 存在强服务端信号的 .js/.mjs/.cjs。
pkg_qualifies_server() {
  local pkg="$1" f
  pkg_entry_hits_server "$pkg" && return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    server_has_strong_signal "$f" && return 0
  done < <(server_layer_candidates "$pkg")
  return 1
}

# server 层候选文件枚举：包根 maxdepth 1（排除配置 basename）+
# 一级非噪声目录全深度。测试/产物排除口径与 src 管线一致。
server_layer_candidates() {
  local pkg="$1" d f
  find "$pkg" -maxdepth 1 -type f \
    \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) \
    -not -name '*.min.js' -not -name '*.bundle.js' -not -name '*.generated.*' \
    -not -name '*.test.js' -not -name '*.spec.js' \
    -print 2>/dev/null | while IFS= read -r f; do
    server_is_config_basename "$f" || printf '%s\n' "$f"
  done
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    server_is_noise_dir "$d" && continue
    find "$d" \
      \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \
        -o -name 'coverage' -o -name '__snapshots__' -o -name 'testdata' -o -name 'fixtures' \) \) -prune -o \
      -type f \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' \) \
      -not -name '*.min.js' -not -name '*.bundle.js' -not -name '*.generated.*' \
      -not -name '*.test.js' -not -name '*.spec.js' \
      -not -path '*/__tests__/*' -not -path '*/__snapshots__/*' -not -path '*/testdata/*' -not -path '*/fixtures/*' \
      -print 2>/dev/null
  done < <(find "$pkg" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)
}

# 收集合格包的 server 层文件：候选中根级文件全收（已过配置黑名单），
# 一级目录内文件需带弱模块信号（拦截纯数据/纯文本文件）。
collect_pkg_server_files() {
  local pkg="$1" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      "$pkg"/*/*)
        server_has_weak_signal "$f" || continue
        ;;
    esac
    printf '%s\n' "$f"
  done < <(server_layer_candidates "$pkg")
}

add_server_pkg() {
  local pkg="$1" existing exists
  [ -d "$pkg" ] || return 0
  pkg="$(cd "$pkg" && pwd -P)"
  pkg_qualifies_server "$pkg" || return 0
  exists=0
  for existing in "${SERVER_PKGS[@]+"${SERVER_PKGS[@]}"}"; do
    [ "$existing" = "$pkg" ] && { exists=1; break; }
  done
  if [ "$exists" -eq 0 ]; then
    SERVER_PKGS+=("$pkg")
  fi
}

SOURCE_ROOTS=()
SERVER_PKGS=()
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
    add_server_pkg "$pkg_root"
    continue
  fi
  if source_root_has_supported_code "$pkg_root/src"; then
    [ "$pkg_root" = "$PROJECT_DIR" ] && ROOT_HAS_SUPPORTED_PACKAGE=1
    add_source_root "$pkg_root/src"
    add_server_pkg "$pkg_root"
  fi
done < <(find "$PROJECT_DIR" -maxdepth 3 -mindepth 1 \
  \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune -o \
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
      add_server_pkg "$pkg_root"
    fi
  done < <(find "$PROJECT_DIR" -maxdepth 3 -mindepth 1 \
    \( -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name '.git' \) \) -prune -o \
    -name 'package.json' -type f -print 2>/dev/null | sort)
fi

[ "${#SOURCE_ROOTS[@]}" -gt 0 ] || [ "${#SERVER_PKGS[@]}" -gt 0 ] || exit 0

# 伴随文件层（白名单最小集）：仅把已进入正式范围的 package 本地的
# package.json 并入清单，让 scripts/core/filetype-rule-map.json 的 npm-package
# 模式始终可触达。根级配置脚本（vite/jest/eslint/postcss 等）维持排除口径，
# 不因伴随层扩入。硬上限与去重、COMPANION_FILES_ADDED=N 口径同 Java 采集器。
#
# BFF server-root 层：合格包的根级与一级目录服务端 JS 走独立 SERVER_TMP，
# LC_ALL=C 序截断上限后并入主清单（生产代码语义，不走伴随 comm 管线；
# 与 src 文件无重叠——server 层剪枝 src），并入数以 stderr SERVER_ROOTS_ADDED=N 披露。
COMPANION_FILE_LIMIT="${CC_CODE_REVIEWER_COMPANION_LIMIT:-200}"
SERVER_ROOT_LIMIT="${CC_CODE_REVIEWER_SERVER_ROOT_LIMIT:-200}"
MAIN_TMP="$(mktemp "${TMPDIR:-/tmp}/fecf-main.XXXXXX")"
COMP_TMP="$(mktemp "${TMPDIR:-/tmp}/fecf-comp.XXXXXX")"
SERVER_TMP="$(mktemp "${TMPDIR:-/tmp}/fecf-server.XXXXXX")"
trap 'rm -f "$MAIN_TMP" "$MAIN_TMP.s" "$COMP_TMP" "$COMP_TMP.s" "$COMP_TMP.new" "$COMP_TMP.add" "$SERVER_TMP" "$SERVER_TMP.s" "$SERVER_TMP.add"' EXIT

for root in "${SOURCE_ROOTS[@]}"; do
  find "$root" -mindepth 1 \
    \( \
      -type d \( -name 'node_modules' -o -name 'dist' -o -name 'build' -o -name 'coverage' \
        -o -name '__snapshots__' -o -name 'testdata' -o -name 'fixtures' \
        -o -name '.git' -o -name '.next' -o -name '.nuxt' \) \
    \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.vue' -o -name '*.mjs' -o -name '*.cjs' \) \
    -not -name '*.d.ts' \
    -not -name '*.test.ts' -not -name '*.test.tsx' -not -name '*.test.js' -not -name '*.test.jsx' -not -name '*.test.vue' \
    -not -name '*.spec.ts' -not -name '*.spec.tsx' -not -name '*.spec.js' -not -name '*.spec.jsx' -not -name '*.spec.vue' \
    -not -path '*/__tests__/*' -not -path '*/__snapshots__/*' -not -path '*/testdata/*' -not -path '*/fixtures/*' -not -path '*/e2e/*' -not -path '*/cypress/*' \
    -not -name '*.generated.*' \
    -not -name '*.min.js' -not -name '*.bundle.js' \
    -print 2>/dev/null >> "$MAIN_TMP"
done

# server 层收集：LIMIT<=0 整体跳过（灰度开关）；截断只作用于 server 子清单，
# src 文件永不被 server 上限挤掉。
SERVER_ADDED=0
SERVER_TRUNCATED_NOTE=""
if [ "$SERVER_ROOT_LIMIT" -gt 0 ] && [ "${#SERVER_PKGS[@]}" -gt 0 ]; then
  for pkg in "${SERVER_PKGS[@]}"; do
    collect_pkg_server_files "$pkg" >> "$SERVER_TMP"
  done
  LC_ALL=C sort -u "$SERVER_TMP" > "$SERVER_TMP.s" || true
  SERVER_TOTAL="$(grep -c . "$SERVER_TMP.s" || true)"
  if [ "$SERVER_TOTAL" -gt "$SERVER_ROOT_LIMIT" ]; then
    head -n "$SERVER_ROOT_LIMIT" "$SERVER_TMP.s" > "$SERVER_TMP.add"
    SERVER_TRUNCATED_NOTE="（server 层命中 ${SERVER_TOTAL} 个已达上限 ${SERVER_ROOT_LIMIT}，超出部分截断）"
    SERVER_ADDED="$SERVER_ROOT_LIMIT"
  else
    cp "$SERVER_TMP.s" "$SERVER_TMP.add"
    SERVER_ADDED="$SERVER_TOTAL"
  fi
  cat "$SERVER_TMP.add" >> "$MAIN_TMP"
fi

# package.json 候选：按 SOURCE_ROOT 的包根（src 的父目录）与 SERVER_PKGS 推导，
# 天然只覆盖受支持 package；同一包根多次出现时由最终 sort -u 收敛。
for root in "${SOURCE_ROOTS[@]}"; do
  pkg_root="$(dirname "$root")"
  [ -f "$pkg_root/package.json" ] && printf '%s\n' "$pkg_root/package.json" >> "$COMP_TMP"
done
for pkg in "${SERVER_PKGS[@]+"${SERVER_PKGS[@]}"}"; do
  [ -f "$pkg/package.json" ] && printf '%s\n' "$pkg/package.json" >> "$COMP_TMP"
done

LC_ALL=C sort -u "$MAIN_TMP" > "$MAIN_TMP.s" || true
LC_ALL=C sort -u "$COMP_TMP" > "$COMP_TMP.s" || true
# comm 必须与 sort 同用 C locale：输入按 LC_ALL=C 排序，而 comm 默认按当前
# locale collation 校验有序性，zh_CN.UTF-8 等环境下会误判无序退出 1，
# 在 set -euo pipefail 下直接终止脚本输出空清单。
LC_ALL=C comm -23 "$COMP_TMP.s" "$MAIN_TMP.s" > "$COMP_TMP.new"
ADDED="$(grep -c . "$COMP_TMP.new" || true)"
TRUNCATED_NOTE=""
if [ "$ADDED" -gt "$COMPANION_FILE_LIMIT" ]; then
  head -n "$COMPANION_FILE_LIMIT" "$COMP_TMP.new" > "$COMP_TMP.add"
  TRUNCATED_NOTE="（伴随白名单命中 ${ADDED} 个已达上限 ${COMPANION_FILE_LIMIT}，超出部分截断）"
  ADDED="$COMPANION_FILE_LIMIT"
else
  cp "$COMP_TMP.new" "$COMP_TMP.add"
fi

cat "$MAIN_TMP.s" "$COMP_TMP.add" | LC_ALL=C sort -u
if [ "$ADDED" -gt 0 ]; then
  echo "COMPANION_FILES_ADDED=${ADDED}${TRUNCATED_NOTE}" >&2
fi
if [ "$SERVER_ADDED" -gt 0 ]; then
  echo "SERVER_ROOTS_ADDED=${SERVER_ADDED}${SERVER_TRUNCATED_NOTE}" >&2
fi
