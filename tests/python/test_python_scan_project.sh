#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── Django + DRF + Pydantic 混合项目 ──
D="$TMP_DIR/django-app"; mkdir -p "$D/myapp" "$D/tests" "$D/myapp/migrations"
cat > "$D/pyproject.toml" <<'EOF'
[project]
name = "django-app"
dependencies = ["django>=4.2", "djangorestframework", "celery", "redis", "pydantic>=2"]
requires-python = ">=3.11"

[tool.ruff]
line-length = 88

[tool.mypy]
strict = true
EOF
echo 'version = 1' > "$D/uv.lock"
echo '[[package]]' > "$D/poetry.lock"
echo '{"_meta":{}}' > "$D/Pipfile.lock"
echo "" > "$D/myapp/__init__.py"
cat > "$D/myapp/models.py" <<'EOF'
from django.db import models
class User(models.Model):
    name = models.CharField(max_length=100)
EOF
cat > "$D/myapp/views.py" <<'EOF'
from django.http import JsonResponse
from .models import User
def list_users(request):
    users = User.objects.all()
    return JsonResponse({"users": list(users.values())})
EOF
cat > "$D/myapp/settings.py" <<'EOF'
DEBUG = True
SECRET_KEY = "hardcoded"
EOF
echo "# migration" > "$D/myapp/migrations/0001_initial.py"
echo "def test_x(): pass" > "$D/tests/test_models.py"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D")"

# PROFILE_SCHEMA v1 契约断言
grep -q 'PROFILE_SCHEMA_VERSION=1' <<< "$OUT"
grep -q 'LANGUAGE_ID=python' <<< "$OUT"
grep -q 'PROJECT_TYPE=python-django' <<< "$OUT"
grep -Eq 'SOURCE_FILE_COUNT=[0-9]+' <<< "$OUT"
grep -Eq 'SOURCE_LINE_COUNT=[0-9]+' <<< "$OUT"
grep -Eq 'FORMAL_CONFIG_FILE_COUNT=[0-9]+' <<< "$OUT"
grep -q 'CODE_INTELLIGENCE_PROVIDER=' <<< "$OUT"
grep -q 'CODE_INTELLIGENCE_AVAILABLE=' <<< "$OUT"

# TECH_STACK 断言
grep -q 'TECH_STACK:Django|dependency:django|rules:django' <<< "$OUT"
grep -q 'TECH_STACK:Celery|dependency:celery' <<< "$OUT"
grep -q 'TECH_STACK:Redis|dependency:redis' <<< "$OUT"
grep -q 'TECH_STACK:Pydantic|dependency:pydantic' <<< "$OUT"

# COMPONENT 断言
grep -q 'COMPONENT:myapp|myapp|' <<< "$OUT"

# RUNTIME_SIGNAL 断言
grep -Eq 'RUNTIME_SIGNAL:requires-python\|>=3\.11' <<< "$OUT"

# SOURCE_SCOPE 断言
grep -qF 'SOURCE_SCOPE:formal|src/**/*.py' <<< "$OUT"
grep -qF 'SOURCE_SCOPE:context|**/tests/**/*.py' <<< "$OUT"
grep -qF 'SOURCE_SCOPE:context|**/migrations/**/*.py' <<< "$OUT"
grep -qF 'SOURCE_SCOPE:excluded|**/venv/**' <<< "$OUT"
grep -qF 'SOURCE_SCOPE:excluded|**/__pycache__/**' <<< "$OUT"

# SOURCE_FILE_COUNT 只统计生产源码（tests/migrations 始终排除）；根级
# pyproject.toml 属依赖描述符伴随层（filetype-rule-map 可达性），一并计入。
FC="$(grep '^SOURCE_FILE_COUNT=' <<< "$OUT" | cut -d= -f2)"
test "$FC" -eq 5  # __init__.py + models.py + views.py + settings.py + pyproject.toml

# FORMAL_CONFIG_FILE / CONTEXT_ROOT 断言：配置可正式发现，测试/迁移只读
# 注意：scan-project.sh 用 pwd -P 规范化 PROJECT_DIR，macOS 上 /var -> /private/var，需同样规范化
D_REAL="$(cd "$D" && pwd -P)"
grep -qF "FORMAL_CONFIG_FILE:$D_REAL/pyproject.toml" <<< "$OUT"
grep -qF "FORMAL_CONFIG_FILE:$D_REAL/uv.lock" <<< "$OUT"
grep -qF "FORMAL_CONFIG_FILE:$D_REAL/poetry.lock" <<< "$OUT"
grep -qF "FORMAL_CONFIG_FILE:$D_REAL/Pipfile.lock" <<< "$OUT"
grep -qF "CONTEXT_ROOT:tests|$D_REAL/tests" <<< "$OUT"
grep -qF "CONTEXT_ROOT:migrations|$D_REAL/myapp/migrations" <<< "$OUT"

# ── Bash 3.2 空数组兼容：无 src 无顶层包的项目不应崩溃（P1-4）──
D2="$TMP_DIR/empty-app"; mkdir -p "$D2"
cat > "$D2/pyproject.toml" <<'EOF'
[project]
name = "empty"
EOF
OUT2="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D2")"
# 空项目必须正常输出 PROFILE_SCHEMA，不报 dirs[@]: unbound variable
grep -q 'PROFILE_SCHEMA_VERSION=1' <<< "$OUT2"
grep -q 'PROJECT_TYPE=python-generic' <<< "$OUT2"
grep -q 'SOURCE_FILE_COUNT=0' <<< "$OUT2"

# ── sourced 模式信号函数复用（P2-3）：scan-project.sh 不应重定义信号函数 ──
# 验证 detect-project.sh sourced 后信号函数可用
D3="$TMP_DIR/sourced-app"; mkdir -p "$D3/myapp"
cat > "$D3/pyproject.toml" <<'EOF'
[project]
name = "sourced"
dependencies = ["fastapi", "sqlalchemy"]
EOF
echo "def x(): pass" > "$D3/myapp/__init__.py"
OUT3="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D3")"
# TECH_STACK 信号来自 detect-project.sh sourced 的函数，应正确识别
grep -q 'TECH_STACK:FastAPI|dependency:fastapi' <<< "$OUT3"
grep -q 'TECH_STACK:SQLAlchemy|dependency:sqlalchemy' <<< "$OUT3"

# ── COMPONENT 必须来自 manifest、支持 namespace package 且互不重叠 ──
D4="$TMP_DIR/components-app"; mkdir -p "$D4/myapp/api" "$D4/myapp/models"
echo "def route(): pass" > "$D4/myapp/api/routes.py"
echo "def model(): pass" > "$D4/myapp/models/user.py"
OUT4="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D4")"
grep -q 'COMPONENT:myapp|myapp|2|' <<< "$OUT4"
test "$(grep -c '^COMPONENT:' <<< "$OUT4")" -eq 1

# ── Monorepo：≥2 子项目根（pyproject.toml/setup.py/requirements.txt/Pipfile）时
#    每个子项目根各成独立 COMPONENT，使 services/api、services/worker 可被单独选择 ──
D5="$TMP_DIR/monorepo"
mkdir -p "$D5/services/api/src" "$D5/services/worker" "$D5/packages/shared"
# 每个子项目根放一个 pyproject.toml 标记独立项目边界
cat > "$D5/services/api/pyproject.toml" <<'EOF'
[project]
name = "api"
dependencies = ["fastapi"]
EOF
cat > "$D5/services/worker/pyproject.toml" <<'EOF'
[project]
name = "worker"
dependencies = ["celery"]
EOF
cat > "$D5/packages/shared/pyproject.toml" <<'EOF'
[project]
name = "shared"
dependencies = ["pydantic"]
EOF
# 生产源码
echo 'from fastapi import FastAPI; app = FastAPI()' > "$D5/services/api/src/main.py"
echo 'def route(): pass' > "$D5/services/api/src/routes.py"
echo 'from celery import Celery; app = Celery()' > "$D5/services/worker/tasks.py"
echo 'def util(): pass' > "$D5/packages/shared/helpers.py"

OUT5="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D5")"
# 三个子项目根各成独立 COMPONENT（而非塌缩成 services/packages 两个）
grep -q 'COMPONENT:api|services/api|2|' <<< "$OUT5"
grep -q 'COMPONENT:worker|services/worker|1|' <<< "$OUT5"
grep -q 'COMPONENT:shared|packages/shared|1|' <<< "$OUT5"
# 必须恰好 3 个 COMPONENT（无重复、无遗漏）
test "$(grep -c '^COMPONENT:' <<< "$OUT5")" -eq 3

# ── Monorepo + 单子项目根：保持现有单包行为（不触发 monorepo 分解）──
D6="$TMP_DIR/single-subproj"
mkdir -p "$D6/services/api/src" "$D6/services/worker"
cat > "$D6/services/api/pyproject.toml" <<'EOF'
[project]
name = "api"
dependencies = ["fastapi"]
EOF
# 只有 1 个子项目根 → 不触发 monorepo 分解，按现有规则分区
echo 'def route(): pass' > "$D6/services/api/src/routes.py"
echo 'def task(): pass' > "$D6/services/worker/tasks.py"
OUT6="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D6")"
# 单子项目根按项目根顶层目录分区：services 一个 COMPONENT（现有行为不变）
grep -q 'COMPONENT:services|services|' <<< "$OUT6"

# ── Monorepo：requirements.txt 作为子项目标记（不只有 pyproject.toml）──
D7="$TMP_DIR/reqtxt-monorepo"
mkdir -p "$D7/backend/api" "$D7/backend/worker"
echo "fastapi" > "$D7/backend/api/requirements.txt"
echo "celery" > "$D7/backend/worker/requirements.txt"
echo 'def route(): pass' > "$D7/backend/api/routes.py"
echo 'def task(): pass' > "$D7/backend/worker/tasks.py"
OUT7="$(bash "$ROOT_DIR/scripts/languages/python/scan-project.sh" "$D7")"
# requirements.txt 也识别为子项目标记
grep -q 'COMPONENT:api|backend/api|1|' <<< "$OUT7"
grep -q 'COMPONENT:worker|backend/worker|1|' <<< "$OUT7"

echo "PASS: python scan-project"
