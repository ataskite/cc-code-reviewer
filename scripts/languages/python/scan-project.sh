#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 复用 detect-project.sh 的信号函数，避免 TECH_STACK 信号与 detect 判定漂移
PY_DETECT_SOURCED=1 . "$SCRIPT_DIR/detect-project.sh"
rel_path() { printf '%s\n' "${1#$PROJECT_DIR/}"; }

# 重新收集 DEP_TEXT（detect-project.sh sourced 模式下不执行收集，需在此重新构建）
collect_dep_text() {
  local f
  for f in "$PROJECT_DIR/pyproject.toml"; do [ -f "$f" ] && cat "$f"; done
  for f in "$PROJECT_DIR/setup.py"; do [ -f "$f" ] && cat "$f"; done
  for f in "$PROJECT_DIR/setup.cfg"; do [ -f "$f" ] && cat "$f"; done
  find "$PROJECT_DIR" -maxdepth 2 \
    \( -path '*/venv/*' -o -path '*/.venv/*' -o -path '*/__pycache__/*' -o -path '*/site-packages/*' -o -path '*/.git/*' \) -prune -o \
    -name 'requirements*.txt' -type f -print 2>/dev/null | sort | while IFS= read -r rf; do cat "$rf"; done
  [ -f "$PROJECT_DIR/Pipfile" ] && cat "$PROJECT_DIR/Pipfile"
}
DEP_TEXT="$(collect_dep_text || true)"

# 重新定义信号函数（sourced 模式下 detect-project 的信号函数依赖其自身 DEP_TEXT，此处独立）
has_django_signal() { printf '%s' "$DEP_TEXT" | grep -Eq 'django([><=!~ "[:space:]]|$)|Django([><=!~ "[:space:]]|$)'; }
has_fastapi_signal() { printf '%s' "$DEP_TEXT" | grep -Eq 'fastapi([><=!~ "[:space:]]|$)'; }
has_flask_signal() { printf '%s' "$DEP_TEXT" | grep -Eq 'flask([><=!~ "[:space:]]|$)|Flask([><=!~ "[:space:]]|$)'; }
has_sqlalchemy_signal() { printf '%s' "$DEP_TEXT" | grep -Eq 'sqlalchemy([><=!~ "[:space:]]|$)|SQLAlchemy([><=!~ "[:space:]]|$)'; }
has_celery_signal() { printf '%s' "$DEP_TEXT" | grep -Eq 'celery([><=!~ "[:space:]]|$)'; }
has_redis_signal() { printf '%s' "$DEP_TEXT" | grep -Eq 'redis([><=!~ "[:space:]]|$)|redis-py'; }
has_pydantic_signal() { printf '%s' "$DEP_TEXT" | grep -Eq 'pydantic([><=!~ "[:space:]]|$)'; }

# 项目类型
PTYPE="$(bash "$SCRIPT_DIR/detect-project.sh" "$PROJECT_DIR" | sed -n 's/^PROJECT_TYPE=//p' | head -1)"

# 统计生产源码
MANIFEST="$(bash "$SCRIPT_DIR/collect-source-files.sh" "$PROJECT_DIR" 2>/dev/null || true)"
FILE_COUNT="$(printf '%s\n' "$MANIFEST" | grep -c . || true)"
LINE_COUNT=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  LINE_COUNT=$((LINE_COUNT + $(wc -l < "$f" | tr -d ' ')))
done <<< "$MANIFEST"

# 正式配置文件计数
CONFIG_COUNT=0
while IFS= read -r cfg; do
  [ -n "$cfg" ] && CONFIG_COUNT=$((CONFIG_COUNT+1))
done < <(find "$PROJECT_DIR" -maxdepth 2 \
  \( -path '*/venv/*' -o -path '*/.venv/*' -o -path '*/__pycache__/*' -o -path '*/.git/*' \) -prune -o \
  -type f \( -name 'pyproject.toml' -o -name 'setup.py' -o -name 'setup.cfg' \
    -o -name 'tox.ini' -o -name 'ruff.toml' -o -name '.ruff.toml' \
    -o -name '.flake8' -o -name 'mypy.ini' -o -name '.mypy.ini' \
    -o -name 'pytest.ini' -o -name 'requirements.txt' \) -print 2>/dev/null)

# 组件维度（src/ 下顶层目录或顶层包目录）
emit_components() {
  local dirs=()
  if [ -d "$PROJECT_DIR/src" ]; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      dirs+=("$d")
    done < <(find "$PROJECT_DIR/src" -maxdepth 1 -mindepth 1 -type d \
      -not -path '*/__pycache__/*' -print 2>/dev/null | sort)
  fi
  if [ "${#dirs[@]}" -eq 0 ]; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      [ -f "$d/__init__.py" ] || continue
      case "$(basename "$d")" in
        tests|test|venv|.venv|__pycache__|build|dist|migrations|node_modules|.git) continue ;;
      esac
      dirs+=("$d")
    done < <(find "$PROJECT_DIR" -maxdepth 2 -mindepth 1 -type d \
      -not -path '*/venv/*' -not -path '*/.venv/*' -not -path '*/__pycache__/*' \
      -print 2>/dev/null | sort)
  fi

  local d rel fcount lcount
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    rel="$(rel_path "$d")"
    fcount=0; lcount=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      fcount=$((fcount+1))
      lcount=$((lcount + $(wc -l < "$f" | tr -d ' ')))
    done < <(find "$d" \( -path '*/venv/*' -o -path '*/.venv/*' -o -path '*/__pycache__/*' -o -path '*/tests/*' \) -prune -o \
      -type f -name '*.py' -not -name 'test_*.py' -not -name '*_test.py' -not -path '*/migrations/*' -print 2>/dev/null)
    [ "$fcount" -gt 0 ] && printf 'COMPONENT:%s|%s|%d|%d\n' "$(basename "$d")" "$rel" "$fcount" "$lcount"
  done
}

# RUNTIME_SIGNAL：从 pyproject.toml 提取 requires-python
emit_runtime_signals() {
  local pyfile="$PROJECT_DIR/pyproject.toml"
  [ -f "$pyfile" ] || return 0
  local pyver
  pyver="$(grep -Eo 'requires-python[[:space:]]*=[[:space:]]*"[^"]*"' "$pyfile" 2>/dev/null | head -1 | sed -E 's/requires-python[[:space:]]*=[[:space:]]*"//; s/"$//')"
  [ -n "$pyver" ] && printf 'RUNTIME_SIGNAL:requires-python|%s\n' "$pyver"
}

# ── 输出 PROFILE_SCHEMA v1 ──
echo "PROFILE_SCHEMA_VERSION=1"
echo "LANGUAGE_ID=python"
echo "PROJECT_TYPE=$PTYPE"
echo "SOURCE_FILE_COUNT=$FILE_COUNT"
echo "SOURCE_LINE_COUNT=$LINE_COUNT"
echo "FORMAL_CONFIG_FILE_COUNT=$CONFIG_COUNT"
echo "CODE_INTELLIGENCE_PROVIDER=none"
echo "CODE_INTELLIGENCE_AVAILABLE=false"
echo "CODE_INTELLIGENCE_REASON=pyright-pylsp-jedi-detection-pending"

emit_components

# TECH_STACK
has_django_signal  && echo "TECH_STACK:Django|dependency:django|rules:django|dimensions:1,4,5,6,7,10,12"
has_fastapi_signal && echo "TECH_STACK:FastAPI|dependency:fastapi|rules:fastapi|dimensions:1,4,5,6,8,12"
has_flask_signal   && echo "TECH_STACK:Flask|dependency:flask|rules:flask|dimensions:1,4,6,10,12"
has_sqlalchemy_signal && echo "TECH_STACK:SQLAlchemy|dependency:sqlalchemy|rules:orm-sqlalchemy|dimensions:5,6,7"
has_celery_signal  && echo "TECH_STACK:Celery|dependency:celery|rules:celery|dimensions:8,10"
has_redis_signal   && echo "TECH_STACK:Redis|dependency:redis|rules:redis|dimensions:5,7"
has_pydantic_signal && echo "TECH_STACK:Pydantic|dependency:pydantic|rules:pydantic|dimensions:2,12"

emit_runtime_signals

# SOURCE_SCOPE
echo "SOURCE_SCOPE:formal|src/**/*.py"
echo "SOURCE_SCOPE:formal|<package>/**/*.py"
echo "SOURCE_SCOPE:context|**/tests/**/*.py"
echo "SOURCE_SCOPE:context|**/migrations/**/*.py"
echo "SOURCE_SCOPE:excluded|**/venv/**"
echo "SOURCE_SCOPE:excluded|**/.venv/**"
echo "SOURCE_SCOPE:excluded|**/__pycache__/**"
echo "SOURCE_SCOPE:excluded|**/site-packages/**"

exit 0
