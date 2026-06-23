#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 正式生产源码口径：仅 src/（及适配器确认的应用源码目录）内的生产 .ts/.tsx/.js/.jsx。
# 不遍历项目根：根级配置脚本（vite.config.ts/jest.config.ts/.eslintrc.js 等）、
# 非 src 目录（scripts/ tools/）、生成代码、测试、node_modules、dist/build 均不计入正式源码。
# .d.ts 是类型声明（只读上下文，spec 7.2），不计入正式源码。
SOURCE_ROOTS=()
for root in "$PROJECT_DIR/src"; do
  [ -d "$root" ] && SOURCE_ROOTS+=("$root")
done
[ "${#SOURCE_ROOTS[@]}" -gt 0 ] || exit 0

for root in "${SOURCE_ROOTS[@]}"; do
  find "$root" \
    \( \
      -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/build/*' -o -path '*/coverage/*' \
      -o -path '*/.git/*' -o -path '*/.next/*' -o -path '*/.nuxt/*' \
    \) -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) \
    -not -name '*.d.ts' \
    -not -name '*.test.ts' -not -name '*.test.tsx' -not -name '*.test.js' -not -name '*.test.jsx' \
    -not -name '*.spec.ts' -not -name '*.spec.tsx' -not -name '*.spec.js' -not -name '*.spec.jsx' \
    -not -path '*/__tests__/*' -not -path '*/e2e/*' -not -path '*/cypress/*' \
    -not -name '*.min.js' -not -name '*.bundle.js' \
    -print 2>/dev/null
done | sort
