#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 正式生产源码口径：src/ 下的 .py（src layout），或项目根下顶层包目录的 .py（flat layout）。
# 排除：tests/、test_*.py、*_test.py、venv/、.venv/、__pycache__/、build/、dist/、migrations/（Django 生成代码，作只读上下文）、site-packages/、.git/。
#
# 信号复用 detect-project.sh（避免两处框架信号漂移）：collect 仅需确认项目是 Python，不需要框架类型，
# 但 source 同一 detect-project.sh 保证未来扩展时不漂移。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_DETECT_SOURCED=1 . "$SCRIPT_DIR/detect-project.sh"

# 统一排除路径（find -prune）
PRUNE_PATHS=(
  -path '*/venv/*' -o
  -path '*/.venv/*' -o
  -path '*/__pycache__/*' -o
  -path '*/site-packages/*' -o
  -path '*/node_modules/*' -o
  -path '*/.git/*' -o
  -path '*/build/*' -o
  -path '*/dist/*' -o
  -path '*/.eggs/*' -o
  -path '*/.tox/*' -o
  -path '*/.pytest_cache/*' -o
  -path '*/.mypy_cache/*' -o
  -path '*/.ruff_cache/*'
)

# 生产源码排除模式（在已进入 src/ 或包目录后，进一步排除测试/生成代码）
PRODUCTION_EXCLUDE=(
  -not -path '*/tests/*'
  -not -path '*/test/*'
  -not -name 'test_*.py'
  -not -name '*_test.py'
  -not -name 'conftest.py'
  -not -path '*/migrations/*'
  -not -path '*/__pycache__/*'
)

SOURCE_ROOTS=()

# 1. src layout: src/ 下的 .py
if [ -d "$PROJECT_DIR/src" ]; then
  # 确认 src 下有 .py 生产文件
  if find "$PROJECT_DIR/src" \( "${PRUNE_PATHS[@]}" \) -prune -o \
    -type f -name '*.py' \( "${PRODUCTION_EXCLUDE[@]}" \) -print -quit 2>/dev/null | grep -q .; then
    SOURCE_ROOTS+=("$PROJECT_DIR/src")
  fi
fi

# 2. flat layout: 项目根下顶层目录（含 __init__.py 视为包），其下的 .py
#    避免把根级散文件（manage.py/conftest.py/setup.py）当生产源码
#    仅在没有 src/ 时扫描 flat 包，避免 src layout 下重复扫描 src 内的包
if [ "${#SOURCE_ROOTS[@]}" -eq 0 ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -f "$d/__init__.py" ] || continue
    # 排除明显的非源码目录
    case "$(basename "$d")" in
      tests|test|venv|.venv|__pycache__|build|dist|migrations|node_modules|.git|.tox|.eggs) continue ;;
    esac
    if find "$d" \( "${PRUNE_PATHS[@]}" \) -prune -o \
      -type f -name '*.py' \( "${PRODUCTION_EXCLUDE[@]}" \) -print -quit 2>/dev/null | grep -q .; then
      SOURCE_ROOTS+=("$d")
    fi
  done < <(find "$PROJECT_DIR" -maxdepth 2 -mindepth 1 -type d \
    \( "${PRUNE_PATHS[@]}" \) -prune -o -type d -print 2>/dev/null | sort)
fi

[ "${#SOURCE_ROOTS[@]}" -gt 0 ] || exit 0

# 输出生产 .py 绝对路径清单（每行一个，排序）
for root in "${SOURCE_ROOTS[@]}"; do
  find "$root" \
    \( "${PRUNE_PATHS[@]}" \) -prune -o \
    -type f -name '*.py' \
    \( "${PRODUCTION_EXCLUDE[@]}" \) \
    -print 2>/dev/null
done | sort
