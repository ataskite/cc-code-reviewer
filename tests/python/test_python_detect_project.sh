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

# ── 测试 3：Flask 项目 ──
FLASK_DIR="$TMP_DIR/flask-app"; mkdir -p "$FLASK_DIR/myapp"
cat > "$FLASK_DIR/requirements.txt" <<'EOF'
flask>=3.0
EOF
echo "from flask import Flask" > "$FLASK_DIR/myapp/app.py"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$FLASK_DIR")"
test "$OUT" = "PROJECT_TYPE=python-flask"

# ── 测试 4：通用 Python 项目 ──
GENERIC_DIR="$TMP_DIR/generic-py"; mkdir -p "$GENERIC_DIR/mypkg"
echo "" > "$GENERIC_DIR/mypkg/__init__.py"
echo "print('hello')" > "$GENERIC_DIR/mypkg/main.py"
cat > "$GENERIC_DIR/pyproject.toml" <<'EOF'
[project]
name = "mypkg"
EOF

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$GENERIC_DIR")"
test "$OUT" = "PROJECT_TYPE=python-generic"

# ── 测试 5：非 Python 项目 ──
NOPY_DIR="$TMP_DIR/no-python"; mkdir -p "$NOPY_DIR"
echo '{"name":"test"}' > "$NOPY_DIR/package.json"

OUT="$(bash "$ROOT_DIR/scripts/languages/python/detect-project.sh" "$NOPY_DIR")"
test "$OUT" = "PROJECT_TYPE=python-unsupported"

echo "PASS: python detect-project"
