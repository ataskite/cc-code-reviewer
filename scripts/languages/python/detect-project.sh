#!/bin/bash
set -euo pipefail
# 被 source 时（PY_DETECT_SOURCED=1）复用调用方已设置的 PROJECT_DIR，不要求 $1。
PROJECT_DIR="${1:-${PROJECT_DIR:-}}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_TYPE=python-unsupported"; exit 0; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# dual-mode：被 collect-source-files.sh / scan-project.sh source 时只定义纯信号函数和 DEP_TEXT，不执行判定。
# 防止两处框架信号漂移（学前端 Vue hoisting 回归教训）。
# guard 位于函数定义之后、主判定之前，确保 sourced 模式下信号函数可用。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 依赖指纹读取 ──
# 只收集「依赖声明」文本，不读项目名(name=)等其他字段，避免项目名含框架关键字时误判。
# - pyproject.toml: 只提取 [project] dependencies 和 [tool.poetry] dependencies 数组元素
# - setup.py: 只提取 install_requires 列表元素
# - setup.cfg: 只提取 install_requires 段
# - requirements*.txt / Pipfile: 整文件都是依赖声明，全读
collect_dep_text() {
  local f
  # pyproject.toml: 用 perl 提取 dependencies 数组内的字符串/裸名元素
  for f in "$PROJECT_DIR/pyproject.toml"; do
    [ -f "$f" ] || continue
    perl -0777 -ne '
      # [project] dependencies = ["...", ...]  或  [tool.poetry] dependencies 下的多行列表
      while (m/dependencies\s*=\s*\[([^\]]*)\]/gs) {
        my $block = $1;
        # 引号字符串：取引号内容，再截到包名边界（第一个非 [A-Za-z0-9_.-] 字符）
        while ($block =~ m/["'\'']([^"'\'']+)["'\'']/g) {
          my $s = $1;
          $s =~ s/^([A-Za-z0-9_.\-]+).*$/$1/s;
          print "$s\n" if $s =~ m/^[A-Za-z0-9_.\-]+$/;
        }
      }
      # [tool.poetry.dependencies] 段下的 key = "version" 形式（key 是包名）
      while (m/\[tool\.poetry\.dependencies\]\s*\n(.*?)(\n\[|\z)/gs) {
        my $block = $1;
        while ($block =~ m/^\s*([A-Za-z0-9_.\-]+)\s*=/mg) {
          my $pkg = $1;
          # 跳过 python 版本声明（不是包）
          next if lc($pkg) eq "python";
          print "$pkg\n";
        }
      }
    ' "$f"
  done
  # setup.py: install_requires=[...] 列表元素
  for f in "$PROJECT_DIR/setup.py"; do
    [ -f "$f" ] || continue
    perl -0777 -ne '
      while (m/install_requires\s*=\s*\[([^\]]*)\]/gs) {
        my $block = $1;
        while ($block =~ m/["'\'']([^"'\'']+)["'\'']/g) {
          my $s = $1;
          $s =~ s/^([A-Za-z0-9_.\-]+).*$/$1/s;
          print "$s\n" if $s =~ m/^[A-Za-z0-9_.\-]+$/;
        }
      }
    ' "$f"
  done
  # setup.cfg: [options] install_requires= 段（续行缩进）
  for f in "$PROJECT_DIR/setup.cfg"; do
    [ -f "$f" ] || continue
    perl -ne '
      if (/^install_requires\s*=\s*(.*)$/ .. /^\[[^\]]+\]$/) {
        my $line = $1 // $_;
        while ($line =~ m/([A-Za-z0-9_.\-]+)/g) { print "$1\n"; }
      }
    ' "$f"
  done
  # requirements*.txt: 每行一个依赖，全读（裸名取到第一个空格/比较符前）
  find "$PROJECT_DIR" -mindepth 1 -maxdepth 2 \
    \( -type d \( -name venv -o -name .venv -o -name __pycache__ -o -name site-packages -o -name .git \) -prune \) -o \
    -name 'requirements*.txt' -type f -print 2>/dev/null | sort | while IFS= read -r rf; do
      # 去注释、去环境标记，取包名（第一个 token，支持 name[extra]>=1.0 形式）
      sed -E 's/#.*$//; s/\[[^]]*\]//g; s/[<>=!~].*//; /^[[:space:]]*$/d' "$rf"
    done
  # Pipfile: [packages] 段下的 key = 版本
  [ -f "$PROJECT_DIR/Pipfile" ] && perl -0777 -ne '
    while (m/\[packages\]\s*\n(.*?)(\n\[|\z)/gs) {
      my $block = $1;
      while ($block =~ m/^\s*([A-Za-z0-9_.\-]+)\s*=/mg) { print "$1\n"; }
    }
  ' "$PROJECT_DIR/Pipfile"
}

DEP_TEXT="$(collect_dep_text || true)"

# 信号函数（纯函数，可被 sourced 复用）
# 正则字符类接受框架名后跟字母/连字符（如 djangorestframework、django-allauth、fastapi-cli），
# 因为 collect_dep_text 已收窄到只读依赖声明，不会读到项目 name 字段，可安全放宽匹配。
has_django_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eqi '(^|[[:space:]]|[<>=!~"\x27])django([><=!~ "[:space:]]|$|[a-z_-])'
}
has_fastapi_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eqi '(^|[[:space:]]|[<>=!~"\x27])fastapi([><=!~ "[:space:]]|$|[a-z_-])'
}
has_sqlalchemy_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eqi '(^|[[:space:]]|[<>=!~"\x27])sqlalchemy([><=!~ "[:space:]]|$|[a-z_-])'
}
has_celery_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eqi '(^|[[:space:]]|[<>=!~"\x27])celery([><=!~ "[:space:]]|$|[a-z_-])'
}
has_redis_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eqi '(^|[[:space:]]|[<>=!~"\x27])redis([><=!~ "[:space:]]|$|[a-z_-])'
}
has_pydantic_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eqi '(^|[[:space:]]|[<>=!~"\x27])pydantic([><=!~ "[:space:]]|$|[a-z_-])'
}

# 是否为 Python 项目（有 pyproject.toml/setup.py/requirements.txt/Pipfile 或 .py 文件）
has_python_marker() {
  [ -f "$PROJECT_DIR/pyproject.toml" ] && return 0
  [ -f "$PROJECT_DIR/setup.py" ] && return 0
  [ -f "$PROJECT_DIR/setup.cfg" ] && return 0
  [ -f "$PROJECT_DIR/requirements.txt" ] && return 0
  [ -f "$PROJECT_DIR/Pipfile" ] && return 0
  find "$PROJECT_DIR" -mindepth 1 -maxdepth 3 \
    \( -type d \( -name venv -o -name .venv -o -name __pycache__ -o -name site-packages \
       -o -name .git -o -name node_modules -o -name build -o -name dist \) -prune \) -o \
    -name '*.py' -type f -print -quit 2>/dev/null | grep -q .
}

# sourced 模式：到此为止，不执行主判定（信号函数已定义，可供调用方复用）
if [ "${PY_DETECT_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || true
fi

if ! has_python_marker; then
  echo "PROJECT_TYPE=python-unsupported"
  exit 0
fi

# 优先级：Django > FastAPI > generic
if has_django_signal; then
  echo "PROJECT_TYPE=python-django"
elif has_fastapi_signal; then
  echo "PROJECT_TYPE=python-fastapi"
else
  echo "PROJECT_TYPE=python-generic"
fi
exit 0
