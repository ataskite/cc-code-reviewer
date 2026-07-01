#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 收集所有候选 package.json（根 + maxdepth 3，排除 node_modules/dist/build/.git）
PKGS="$(find "$PROJECT_DIR" -maxdepth 3 \
  \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune \
  -o -name 'package.json' -type f -print 2>/dev/null)"

# 任一 package.json 命中给定依赖名（key 形如 "next"）
has_dep_anywhere() {
  local dep="$1"
  [ -n "$PKGS" ] || return 1
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if grep -Eq "\"${dep}\"\s*:\s*\"[^\"]+\"" "$p" 2>/dev/null; then return 0; fi
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

# 需要 react 依赖 + tsx/jsx 或 React JS/TS 入口证据
has_react=0
if has_dep_anywhere "react"; then has_react=1; fi

if [ "$has_react" -eq 1 ]; then
  if find "$PROJECT_DIR" \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune \
    -o \( -name '*.tsx' -o -name '*.jsx' \) -print -quit 2>/dev/null | grep -q .; then
    echo "PROJECT_TYPE=frontend-react"; exit 0
  fi
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    if grep -Eq "from ['\"]react['\"]|require\\(['\"]react['\"]\\)|React\\.createElement|createElement\\(" "$src" 2>/dev/null; then
      echo "PROJECT_TYPE=frontend-react"; exit 0
    fi
  done < <(find "$PROJECT_DIR" \
    \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune \
    -o \( -name '*.ts' -o -name '*.js' \) -type f -print 2>/dev/null)
fi

# 有 TS/JS 但无 React → 通用 TS/JS，首期不支持
if find "$PROJECT_DIR" \
  \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/.git/*' \) -prune \
  -o \( -name '*.ts' -o -name '*.js' \) -print -quit 2>/dev/null | grep -q .; then
  echo "PROJECT_TYPE=frontend-unsupported|reason=generic-tsjs"; exit 0
fi

echo "PROJECT_TYPE=frontend-unsupported|reason=no-frontend-evidence"
exit 0
