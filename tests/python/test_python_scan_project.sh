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

# SOURCE_FILE_COUNT 必须只统计生产源码（排除 tests/migrations）
FC="$(grep '^SOURCE_FILE_COUNT=' <<< "$OUT" | cut -d= -f2)"
test "$FC" -eq 4  # __init__.py + models.py + views.py + settings.py

echo "PASS: python scan-project"
