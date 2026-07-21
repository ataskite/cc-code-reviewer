#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_TYPE=python-unsupported"; exit 0; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# dual-mode：被 collect-source-files.sh / scan-project.sh source 时只定义纯信号函数，不执行判定。
# 防止两处框架信号漂移（学前端 Vue hoisting 回归教训）。
if [ "${PY_DETECT_SOURCED:-0}" = "1" ]; then
  return 0 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 依赖指纹读取 ──
# 收集 pyproject.toml / setup.py / setup.cfg / requirements.txt / requirements*.txt / Pipfile 中的依赖文本
collect_dep_text() {
  local f
  # pyproject.toml [project] dependencies / [tool.poetry] dependencies
  for f in "$PROJECT_DIR/pyproject.toml"; do
    [ -f "$f" ] && cat "$f"
  done
  # setup.py install_requires
  for f in "$PROJECT_DIR/setup.py"; do
    [ -f "$f" ] && cat "$f"
  done
  # setup.cfg install_requires
  for f in "$PROJECT_DIR/setup.cfg"; do
    [ -f "$f" ] && cat "$f"
  done
  # requirements*.txt
  find "$PROJECT_DIR" -maxdepth 2 \
    \( -path '*/venv/*' -o -path '*/.venv/*' -o -path '*/__pycache__/*' -o -path '*/site-packages/*' -o -path '*/.git/*' \) -prune -o \
    -name 'requirements*.txt' -type f -print 2>/dev/null | sort | while IFS= read -r rf; do cat "$rf"; done
  # Pipfile
  [ -f "$PROJECT_DIR/Pipfile" ] && cat "$PROJECT_DIR/Pipfile"
}

DEP_TEXT="$(collect_dep_text || true)"

# 信号函数（纯函数，可被 sourced 复用）
has_django_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eq 'django([><=!~ "[:space:]]|$)|Django([><=!~ "[:space:]]|$)'
}
has_fastapi_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eq 'fastapi([><=!~ "[:space:]]|$)'
}
has_flask_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eq 'flask([><=!~ "[:space:]]|$)|Flask([><=!~ "[:space:]]|$)'
}
has_sqlalchemy_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eq 'sqlalchemy([><=!~ "[:space:]]|$)|SQLAlchemy([><=!~ "[:space:]]|$)'
}
has_celery_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eq 'celery([><=!~ "[:space:]]|$)'
}
has_redis_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eq 'redis([><=!~ "[:space:]]|$)|redis-py'
}
has_pydantic_signal() {
  printf '%s' "$DEP_TEXT" | grep -Eq 'pydantic([><=!~ "[:space:]]|$)'
}

# 是否为 Python 项目（有 pyproject.toml/setup.py/requirements.txt/Pipfile 或 .py 文件）
has_python_marker() {
  [ -f "$PROJECT_DIR/pyproject.toml" ] && return 0
  [ -f "$PROJECT_DIR/setup.py" ] && return 0
  [ -f "$PROJECT_DIR/setup.cfg" ] && return 0
  [ -f "$PROJECT_DIR/requirements.txt" ] && return 0
  [ -f "$PROJECT_DIR/Pipfile" ] && return 0
  find "$PROJECT_DIR" -maxdepth 3 \
    \( -path '*/venv/*' -o -path '*/.venv/*' -o -path '*/__pycache__/*' -o -path '*/site-packages/*' \
       -o -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/build/*' -o -path '*/dist/*' \) -prune -o \
    -name '*.py' -type f -print -quit 2>/dev/null | grep -q .
}

if ! has_python_marker; then
  echo "PROJECT_TYPE=python-unsupported"
  exit 0
fi

# 优先级：Django > FastAPI > Flask > generic
if has_django_signal; then
  echo "PROJECT_TYPE=python-django"
elif has_fastapi_signal; then
  echo "PROJECT_TYPE=python-fastapi"
elif has_flask_signal; then
  echo "PROJECT_TYPE=python-flask"
else
  echo "PROJECT_TYPE=python-generic"
fi
exit 0
