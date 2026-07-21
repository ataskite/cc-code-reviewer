#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# detect-language.sh 必须对 Python 项目输出 CANDIDATE_LANGUAGE:python
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ── 测试 1：Django 项目 ──
D="$TMP_DIR/django-app"; mkdir -p "$D/myapp"
cat > "$D/pyproject.toml" <<'EOF'
[project]
dependencies = ["django>=4.2"]
EOF
echo "" > "$D/myapp/__init__.py"
echo "from django.db import models" > "$D/myapp/models.py"

OUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$D")"
echo "$OUT" | grep -q 'CANDIDATE_LANGUAGE:python|evidence='
# 不应误报 java/frontend
echo "$OUT" | grep -vq 'CANDIDATE_LANGUAGE:java'
echo "$OUT" | grep -vq 'CANDIDATE_LANGUAGE:frontend'

# ── 测试 2：通用 Python（仅有 .py 文件）──
D2="$TMP_DIR/generic-py"; mkdir -p "$D2/scripts"
echo "print('hello')" > "$D2/main.py"
echo "print('util')" > "$D2/scripts/util.py"

OUT2="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$D2")"
echo "$OUT2" | grep -q 'CANDIDATE_LANGUAGE:python'

# ── 测试 3：混合仓库（Java + Python）──
D3="$TMP_DIR/mixed"; mkdir -p "$D3/src/main/java/com/example" "$D3/myapp"
echo "<project><modelVersion>4.0.0</modelVersion></project>" > "$D3/pom.xml"
echo "" > "$D3/myapp/__init__.py"
echo "import django" > "$D3/myapp/views.py"
cat > "$D3/requirements.txt" <<'EOF'
django>=4.2
EOF

OUT3="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$D3")"
echo "$OUT3" | grep -q 'CANDIDATE_LANGUAGE:java'
echo "$OUT3" | grep -q 'CANDIDATE_LANGUAGE:python'

echo "PASS: python route via detect-language"
