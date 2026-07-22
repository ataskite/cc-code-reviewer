#!/bin/bash
set -euo pipefail
PROJECT_DIR="${1:?请输入项目路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 复用 detect-project.sh 的信号函数，避免 TECH_STACK 信号与 detect 判定漂移
# detect-project.sh sourced 模式下已收集 DEP_TEXT 并定义 has_*_signal 函数，此处直接复用。
PY_DETECT_SOURCED=1 . "$SCRIPT_DIR/detect-project.sh"
rel_path() { printf '%s\n' "${1#$PROJECT_DIR/}"; }

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

# 正式配置文件：可产生正式发现，但不进入 Python 源码覆盖率分母。
collect_formal_config_files() {
  find "$PROJECT_DIR" -mindepth 1 -maxdepth 2 \
    \( -type d \( -name venv -o -name .venv -o -name __pycache__ -o -name .git -o -name node_modules \) -prune \) -o \
    -type f \( -name 'pyproject.toml' -o -name 'setup.py' -o -name 'setup.cfg' \
      -o -name 'tox.ini' -o -name 'ruff.toml' -o -name '.ruff.toml' \
      -o -name '.flake8' -o -name 'mypy.ini' -o -name '.mypy.ini' \
      -o -name 'pytest.ini' -o -name 'requirements*.txt' -o -name 'Pipfile' \
      -o -name 'uv.lock' -o -name 'poetry.lock' -o -name 'Pipfile.lock' \) -print 2>/dev/null | sort
}

# 正式配置文件计数
CONFIG_COUNT=0
while IFS= read -r cfg; do
  [ -n "$cfg" ] && CONFIG_COUNT=$((CONFIG_COUNT+1))
done < <(collect_formal_config_files)

# 组件维度：完全由正式 source manifest 派生，保证与 collect-source-files.sh 的
# namespace package / 排除规则一致；组件之间不重叠，避免父包与子包重复计数。
#
# Monorepo 分解：当仓库内有 ≥2 个子项目根（含 pyproject.toml/setup.py/setup.cfg/
# requirements*.txt/Pipfile 的目录）时，每个子项目根各成独立 COMPONENT，
# 使 services/api、services/worker 等真实业务模块可被单独选择扫描。
# 单项目（0 或 1 个子项目根）保持原有行为：按项目根顶层目录分区。
emit_components() {
  local component_file rel rest component f comp
  local subproj_file subproj leaf_count matched fcount lcount

  # 收集子项目根（排除项目根本身，mindepth 2）
  subproj_file="$(mktemp "${TMPDIR:-/tmp}/cc-python-subproj.XXXXXX")"
  find "$PROJECT_DIR" -mindepth 2 -maxdepth 4 \
    \( -type d \( -name venv -o -name .venv -o -name __pycache__ -o -name .git \
       -o -name node_modules -o -name site-packages -o -name build -o -name dist \) -prune \) -o \
    \( -name 'pyproject.toml' -o -name 'setup.py' -o -name 'setup.cfg' \
       -o -name 'requirements*.txt' -o -name 'Pipfile' \) -type f -print 2>/dev/null \
    | while IFS= read -r marker; do
      rel_path "$marker"
    done | sed 's#/[^/]*$##' | sort -u > "$subproj_file"
  leaf_count="$(grep -c . "$subproj_file" 2>/dev/null | tr -d '[:space:]' || printf '0')"
  [ -n "$leaf_count" ] || leaf_count=0

  # Phase 1：构建文件→组件映射（每个文件恰好归入一个组件，避免重叠计数）
  component_file="$(mktemp "${TMPDIR:-/tmp}/cc-python-components.XXXXXX")"
  local map_file
  map_file="$(mktemp "${TMPDIR:-/tmp}/cc-python-map.XXXXXX")"

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="$(rel_path "$f")"
    component=""

    # Monorepo（≥2 子项目根）：匹配最深子项目根作为组件
    if [ "$leaf_count" -ge 2 ]; then
      matched=""
      while IFS= read -r subproj; do
        [ -n "$subproj" ] || continue
        case "$rel" in
          "$subproj"/*)
            # 取最长匹配（最深子项目根），避免父级标记吞并子级文件
            if [ -z "$matched" ] || [ "${#subproj}" -gt "${#matched}" ]; then
              matched="$subproj"
            fi
            ;;
        esac
      done < "$subproj_file"
      [ -n "$matched" ] && component="$matched"
    fi

    # 未命中子项目根 → 现有分组规则（src/<top>、flat <top>）
    if [ -z "$component" ]; then
      case "$rel" in
        src/*/*)
          rest="${rel#src/}"
          component="src/${rest%%/*}"
          ;;
        src/*)
          component="src"
          ;;
        */*)
          component="${rel%%/*}"
          ;;
      esac
    fi

    if [ -n "$component" ]; then
      printf '%s\t%s\n' "$component" "$f" >> "$map_file"
      printf '%s\n' "$component" >> "$component_file"
    fi
  done <<< "$MANIFEST"

  # Phase 2：按组件聚合输出（从 map_file 读取，保证不重复计数）
  while IFS= read -r component; do
    [ -n "$component" ] || continue
    fcount=0
    lcount=0
    while IFS=$'\t' read -r comp f; do
      [ "$comp" = "$component" ] || continue
      fcount=$((fcount + 1))
      lcount=$((lcount + $(wc -l < "$f" | tr -d ' ')))
    done < "$map_file"
    [ "$fcount" -gt 0 ] && printf 'COMPONENT:%s|%s|%d|%d\n' "$(basename "$component")" "$component" "$fcount" "$lcount" || true
  done < <(sort -u "$component_file")

  rm -f "$component_file" "$subproj_file" "$map_file"
}

# RUNTIME_SIGNAL：从 pyproject.toml 提取 requires-python
emit_runtime_signals() {
  local pyfile="$PROJECT_DIR/pyproject.toml"
  [ -f "$pyfile" ] || return 0
  local pyver
  pyver="$(grep -Eo 'requires-python[[:space:]]*=[[:space:]]*"[^"]*"' "$pyfile" 2>/dev/null | head -1 | sed -E 's/requires-python[[:space:]]*=[[:space:]]*"//; s/"$//' || true)"
  [ -n "$pyver" ] && printf 'RUNTIME_SIGNAL:requires-python|%s\n' "$pyver" || true
}

# 正式配置文件与只读上下文入口：供子 agent 可靠定位，无需自行 find。
# 正式配置可以产生发现，但不计入 Python 源码覆盖率；测试/迁移只作上下文。
emit_project_files() {
  local cfg
  while IFS= read -r cfg; do
    [ -n "$cfg" ] || continue
    printf 'FORMAL_CONFIG_FILE:%s\n' "$cfg"
  done < <(collect_formal_config_files)

  local td
  while IFS= read -r td; do
    [ -n "$td" ] || continue
    printf 'CONTEXT_ROOT:tests|%s\n' "$td"
  done < <(find "$PROJECT_DIR" -mindepth 1 -maxdepth 4 \
    \( -type d \( -name venv -o -name .venv -o -name __pycache__ -o -name .git -o -name node_modules -o -name site-packages \) -prune \) -o \
    -type d \( -name tests -o -name test \) -print 2>/dev/null | sort)

  # 迁移目录（migrations/，Django/Alembic 生成代码）
  while IFS= read -r md; do
    [ -n "$md" ] || continue
    printf 'CONTEXT_ROOT:migrations|%s\n' "$md"
  done < <(find "$PROJECT_DIR" -mindepth 1 -maxdepth 4 \
    \( -type d \( -name venv -o -name .venv -o -name __pycache__ -o -name .git -o -name node_modules -o -name site-packages \) -prune \) -o \
    -type d -name 'migrations' -print 2>/dev/null | sort)
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

emit_project_files

# TECH_STACK
has_django_signal  && echo "TECH_STACK:Django|dependency:django|rules:django|dimensions:1,4,5,6,7,10,12" || true
has_fastapi_signal && echo "TECH_STACK:FastAPI|dependency:fastapi|rules:fastapi|dimensions:1,4,5,6,8,12" || true
has_sqlalchemy_signal && echo "TECH_STACK:SQLAlchemy|dependency:sqlalchemy|rules:orm-sqlalchemy|dimensions:5,6,7" || true
has_celery_signal  && echo "TECH_STACK:Celery|dependency:celery|rules:celery|dimensions:8,10" || true
has_redis_signal   && echo "TECH_STACK:Redis|dependency:redis|rules:redis|dimensions:5,7" || true
has_pydantic_signal && echo "TECH_STACK:Pydantic|dependency:pydantic|rules:pydantic|dimensions:2,12" || true

emit_runtime_signals

# SOURCE_SCOPE
echo "SOURCE_SCOPE:formal|src/**/*.py"
echo "SOURCE_SCOPE:formal|<package>/**/*.py"
echo "SOURCE_SCOPE:formal|<root-entry>.py"
echo "SOURCE_SCOPE:formal-config|pyproject.toml,setup.py,setup.cfg,requirements*.txt,Pipfile,uv.lock,poetry.lock,Pipfile.lock,tox.ini,ruff,mypy,pytest"
echo "SOURCE_SCOPE:context|**/tests/**/*.py"
echo "SOURCE_SCOPE:context|**/migrations/**/*.py"
echo "SOURCE_SCOPE:excluded|**/venv/**"
echo "SOURCE_SCOPE:excluded|**/.venv/**"
echo "SOURCE_SCOPE:excluded|**/__pycache__/**"
echo "SOURCE_SCOPE:excluded|**/site-packages/**"

exit 0
