#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# 正式生产源码口径：
#   - src layout：src/ 下的 .py
#   - flat layout：项目根下顶层目录（含 __init__.py 的常规包，或不含 __init__.py 但有生产 .py 的 namespace package）下的 .py
#   - 根级单文件应用：项目根下的 app.py / main.py / wsgi.py / asgi.py / server.py / manage.py（Python 单文件应用常见入口形态）
# 排除：tests/、test_*.py、*_test.py、conftest.py、setup.py、venv/、.venv/、__pycache__/、build/、dist/、migrations/（Django 生成代码，作只读上下文）、site-packages/、.git/。
#
# 信号复用 detect-project.sh（避免两处框架信号漂移）：collect 仅需确认项目是 Python，不需要框架类型，
# 但 source 同一 detect-project.sh 保证未来扩展时不漂移。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_DETECT_SOURCED=1 . "$SCRIPT_DIR/detect-project.sh"

# 查找生产源码时只按 PROJECT_DIR 之下的目录名剪枝。`-mindepth 1` 保证项目根
# 本身即使叫 test/build/dist 也不会被误剪；嵌套 tests/test/migrations 则始终排除。
find_production_py() {
  local root="$1"
  find "$root" -mindepth 1 \
    \( -type d \( \
      -name venv -o -name .venv -o -name __pycache__ -o -name site-packages -o \
      -name node_modules -o -name .git -o -name build -o -name dist -o \
      -name .eggs -o -name .tox -o -name .pytest_cache -o -name .mypy_cache -o \
      -name .ruff_cache -o -name tests -o -name test -o -name migrations \
    \) -prune \) -o \
    -type f -name '*.py' \
    -not -name 'test_*.py' -not -name '*_test.py' -not -name 'conftest.py' \
    -print 2>/dev/null
}

# 根级单文件应用白名单（FastAPI/Django 等单文件入口；setup.py/conftest.py 不在此列）
ROOT_SINGLE_FILE_ENTRY_NAMES=(
  app.py
  main.py
  wsgi.py
  asgi.py
  server.py
  manage.py
)

# 判断目录是否含生产 .py 文件（用于 namespace package 识别）
dir_has_production_py() {
  [ -d "$1" ] || return 1
  find_production_py "$1" | awk 'NR == 1 { found = 1 } END { exit(found ? 0 : 1) }'
}

# 判断目录是否为非源码目录（tests/venv/build 等）
is_non_source_dir() {
  case "$(basename "$1")" in
    tests|test|venv|.venv|__pycache__|build|dist|migrations|node_modules|.git|.tox|.eggs|.pytest_cache|.mypy_cache|.ruff_cache) return 0 ;;
    *) return 1 ;;
  esac
}

SOURCE_ROOTS=()

# 1. src layout: src/ 下的 .py
if [ -d "$PROJECT_DIR/src" ]; then
  # 确认 src 下有 .py 生产文件
  if dir_has_production_py "$PROJECT_DIR/src"; then
    SOURCE_ROOTS+=("$PROJECT_DIR/src")
  fi
fi

# 2. flat layout: 项目根下顶层目录（maxdepth 1，避免顶层包与其子包同时进入 SOURCE_ROOTS 造成重复扫描）。
#    仅在没有 src/ 时扫描 flat 包，避免 src layout 下重复扫描 src 内的包。
#    同时支持：
#    - 常规包（含 __init__.py）
#    - namespace package（PEP 420，不含 __init__.py 但目录下有生产 .py 文件）
if [ "${#SOURCE_ROOTS[@]}" -eq 0 ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    is_non_source_dir "$d" && continue
    # 常规包（含 __init__.py）或 namespace package（不含 __init__.py 但有生产 .py）
    if dir_has_production_py "$d"; then
      SOURCE_ROOTS+=("$d")
    fi
  done < <(find "$PROJECT_DIR" -maxdepth 1 -mindepth 1 -type d -print 2>/dev/null | sort)
fi

# 3. 根级生产入口：白名单入口与 src/flat 包可以共存。
#    这是 FastAPI `main.py + app/`、Django `manage.py + project/` 等常见布局的必要边界。
ROOT_ENTRY_FOUND=0
for entry in "${ROOT_SINGLE_FILE_ENTRY_NAMES[@]}"; do
  if [ -f "$PROJECT_DIR/$entry" ]; then
    ROOT_ENTRY_FOUND=1
    break
  fi
done

# 4. 通用根级脚本项目：当既无 src/flat 包也无白名单入口时，
#    收集项目根下的 .py（如 cli.py / worker.py），但排除测试与打包配置。
ROOT_GENERIC_MODE=0
if [ "${#SOURCE_ROOTS[@]}" -eq 0 ] && [ "$ROOT_ENTRY_FOUND" -eq 0 ]; then
  if find "$PROJECT_DIR" -maxdepth 1 -type f -name '*.py' \
    -not -name 'setup.py' -not -name 'conftest.py' \
    -not -name 'test_*.py' -not -name '*_test.py' -print -quit 2>/dev/null | grep -q .; then
    ROOT_GENERIC_MODE=1
  fi
fi

# 无任何源码根时退出（exit 0，让上层脚本判断空 manifest）
if [ "${#SOURCE_ROOTS[@]}" -eq 0 ] && [ "$ROOT_ENTRY_FOUND" -eq 0 ] && [ "$ROOT_GENERIC_MODE" -eq 0 ]; then
  exit 0
fi

# 输出生产 .py 绝对路径清单（每行一个，排序去重）
# - src/flat 包：递归收集 SOURCE_ROOTS 下的 .py
# - 根级入口：始终合并白名单生产入口（不递归）
# - 通用根级脚本：仅在没有 src/flat 包和白名单入口时收集
# 注意：{ } 块内每个分支必须以 exit 0 的命令结尾，否则 pipefail 会使 sort 管道返回非 0。
{
  for root in "${SOURCE_ROOTS[@]+"${SOURCE_ROOTS[@]}"}"; do
    [ -n "$root" ] || continue
    find_production_py "$root" || true
  done
  for entry in "${ROOT_SINGLE_FILE_ENTRY_NAMES[@]}"; do
    [ -f "$PROJECT_DIR/$entry" ] && printf '%s\n' "$PROJECT_DIR/$entry" || true
  done
  if [ "$ROOT_GENERIC_MODE" -eq 1 ]; then
    find "$PROJECT_DIR" -maxdepth 1 -type f -name '*.py' \
      -not -name 'setup.py' -not -name 'conftest.py' \
      -not -name 'test_*.py' -not -name '*_test.py' -print 2>/dev/null || true
  fi
} | sort -u
