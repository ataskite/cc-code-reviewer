#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 测试 1：Django 项目 ──
DJANGO_DIR="$TMP_DIR/django-app"; mkdir -p "$DJANGO_DIR/myapp" "$DJANGO_DIR/tests"
cat > "$DJANGO_DIR/pyproject.toml" <<'EOF'
[project]
name = "django-app"
dependencies = ["django>=4.2", "djangorestframework"]
requires-python = ">=3.10"
EOF
echo "" > "$DJANGO_DIR/myapp/__init__.py"
echo "from django.db import models" > "$DJANGO_DIR/myapp/models.py"
echo "DEBUG = True" > "$DJANGO_DIR/myapp/settings.py"
echo "def test_x(): pass" > "$DJANGO_DIR/tests/test_models.py"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$DJANGO_DIR")"
test "$OUT" = "PROJECT_TYPE=python-django"

# ── 测试 2：FastAPI 项目 ──
FASTAPI_DIR="$TMP_DIR/fastapi-app"; mkdir -p "$FASTAPI_DIR/src/app"
cat > "$FASTAPI_DIR/pyproject.toml" <<'EOF'
[project]
dependencies = ["fastapi>=0.100", "uvicorn", "pydantic>=2"]
EOF
echo "" > "$FASTAPI_DIR/src/app/__init__.py"
echo "from fastapi import FastAPI" > "$FASTAPI_DIR/src/app/main.py"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$FASTAPI_DIR")"
test "$OUT" = "PROJECT_TYPE=python-fastapi"

# ── 测试 3：通用 Python 项目 ──
GENERIC_DIR="$TMP_DIR/generic-py"; mkdir -p "$GENERIC_DIR/mypkg"
echo "" > "$GENERIC_DIR/mypkg/__init__.py"
echo "print('hello')" > "$GENERIC_DIR/mypkg/main.py"
cat > "$GENERIC_DIR/pyproject.toml" <<'EOF'
[project]
name = "mypkg"
EOF

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$GENERIC_DIR")"
test "$OUT" = "PROJECT_TYPE=python-generic"

# ── 测试 4：flask 依赖应归入 python-generic（Flask 专项检测已移除，回归保护）──
FLASK_DIR="$TMP_DIR/flask-regression"; mkdir -p "$FLASK_DIR/myapp"
cat > "$FLASK_DIR/requirements.txt" <<'EOF'
flask>=3.0
EOF
echo "from flask import Flask" > "$FLASK_DIR/myapp/app.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$FLASK_DIR")"
test "$OUT" = "PROJECT_TYPE=python-generic"

# ── 测试 5：非 Python 项目 ──
NOPY_DIR="$TMP_DIR/no-python"; mkdir -p "$NOPY_DIR"
echo '{"name":"test"}' > "$NOPY_DIR/package.json"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$NOPY_DIR")"
test "$OUT" = "PROJECT_TYPE=python-unsupported"

# ── 测试 6：djangorestframework 触发 django 信号（DRF 依赖 Django）──
DRF_DIR="$TMP_DIR/drf-only"; mkdir -p "$DRF_DIR/myapp"
cat > "$DRF_DIR/requirements.txt" <<'EOF'
djangorestframework
EOF
echo "" > "$DRF_DIR/myapp/__init__.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$DRF_DIR")"
test "$OUT" = "PROJECT_TYPE=python-django"

# ── 测试 7：django-allauth 触发 django 信号（django-xxx 包名）──
ALLAUTH_DIR="$TMP_DIR/allauth"; mkdir -p "$ALLAUTH_DIR/myapp"
cat > "$ALLAUTH_DIR/requirements.txt" <<'EOF'
django-allauth
EOF
echo "" > "$ALLAUTH_DIR/myapp/__init__.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$ALLAUTH_DIR")"
test "$OUT" = "PROJECT_TYPE=python-django"

# ── 测试 8：项目名含 django 但依赖不含，不应误判 ──
NAMEONLY_DIR="$TMP_DIR/name-django"; mkdir -p "$NAMEONLY_DIR/myapp"
cat > "$NAMEONLY_DIR/pyproject.toml" <<'EOF'
[project]
name = "django-portal-migration-tool"
dependencies = ["requests"]
EOF
echo "" > "$NAMEONLY_DIR/myapp/__init__.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$NAMEONLY_DIR")"
test "$OUT" = "PROJECT_TYPE=python-generic"

# ── 测试 9：pyproject.toml [tool.poetry.dependencies] django = "^4.2" ──
POETRY_DIR="$TMP_DIR/poetry-dj"; mkdir -p "$POETRY_DIR/myapp"
cat > "$POETRY_DIR/pyproject.toml" <<'EOF'
[tool.poetry]
name = "my-app"

[tool.poetry.dependencies]
python = "^3.11"
django = "^4.2"
EOF
echo "" > "$POETRY_DIR/myapp/__init__.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$POETRY_DIR")"
test "$OUT" = "PROJECT_TYPE=python-django"

# ── 测试 10：pyproject.toml dependencies 数组带版本号（fastapi>=0.100）──
ARRVER_DIR="$TMP_DIR/arr-ver"; mkdir -p "$ARRVER_DIR/src/app"
cat > "$ARRVER_DIR/pyproject.toml" <<'EOF'
[project]
dependencies = ["fastapi>=0.100", "uvicorn[standard]>=0.20", "pydantic>=2"]
EOF
echo "" > "$ARRVER_DIR/src/app/__init__.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$ARRVER_DIR")"
test "$OUT" = "PROJECT_TYPE=python-fastapi"

# ── 测试 11：Python 分发包名大小写不敏感 ──
CASE_DIR="$TMP_DIR/case-insensitive"; mkdir -p "$CASE_DIR/src/app"
cat > "$CASE_DIR/requirements.txt" <<'EOF'
FastAPI==0.115
Pydantic>=2
EOF
echo "" > "$CASE_DIR/src/app/__init__.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$CASE_DIR")"
test "$OUT" = "PROJECT_TYPE=python-fastapi"

# ── 测试 12：项目祖先目录叫 build 时仍能通过纯源码识别 Python ──
BUILD_DIR="$TMP_DIR/workspace/build/backend"; mkdir -p "$BUILD_DIR/src/app"
echo "x = 1" > "$BUILD_DIR/src/app/main.py"
OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$BUILD_DIR")"
test "$OUT" = "PROJECT_TYPE=python-generic"

echo "PASS: python detect-project"
