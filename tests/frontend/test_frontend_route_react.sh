#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-route.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

D="$TMP_DIR/react"; mkdir -p "$D/src"
cat > "$D/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}
JSON
echo 'export default function App(){return <div/>}' > "$D/src/App.tsx"

# 1. detect-language 报 frontend 不报 java
LOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$D")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$LOUT"
! grep -q "CANDIDATE_LANGUAGE:java" <<< "$LOUT"

# 2. 前端 scan-project 产出 PROFILE_SCHEMA v1
SOUT="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D")"
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$SOUT"
grep -q "LANGUAGE_ID=frontend" <<< "$SOUT"
grep -q "PROJECT_TYPE=frontend-react" <<< "$SOUT"

# 3. 混合仓库两者都报
JDIR="$TMP_DIR/mixed"; mkdir -p "$JDIR/src/main/java/com/x" "$JDIR/fe/src"
cat > "$JDIR/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion><groupId>com.x</groupId><artifactId>j</artifactId><version>1</version></project>
XML
echo 'package com.x; public class A {}' > "$JDIR/src/main/java/com/x/A.java"
cat > "$JDIR/fe/package.json" <<'JSON'
{"name":"fe","dependencies":{"react":"^18.0.0"}}
JSON
echo 'export const P=()=><div/>' > "$JDIR/fe/src/P.tsx"
MOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$JDIR")"
grep -q "CANDIDATE_LANGUAGE:java" <<< "$MOUT"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$MOUT"

echo "PASS: frontend route react"
