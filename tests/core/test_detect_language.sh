#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/detect-lang.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mk_java() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src/main/java/com/x"
  cat > "$d/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion><groupId>com.x</groupId><artifactId>j</artifactId><version>1</version></project>
XML
  echo "package com.x; public class A {}" > "$d/src/main/java/com/x/A.java"
}

mk_react() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}
JSON
  echo 'export function App(){return <div/>}' > "$d/src/App.tsx"
}

mk_vue2() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"legacy","dependencies":{"vue":"^2.6.14"},"devDependencies":{"vue-template-compiler":"^2.6.14"}}
JSON
  echo '<template><div/></template><script>export default {}</script>' > "$d/src/App.vue"
}

mk_node() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"api","type":"module","main":"src/server.js","dependencies":{"express":"^4.18.0"}}
JSON
  echo "import express from 'express'; export const app = express();" > "$d/src/server.js"
}

# 纯 Java
mk_java java_only
JOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/java_only")"
grep -q "CANDIDATE_LANGUAGE:java" <<< "$JOUT"
! grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$JOUT"

# 纯前端（有 React 依赖 + tsx 证据）
mk_react react_only
FOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/react_only")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$FOUT"
! grep -q "CANDIDATE_LANGUAGE:java" <<< "$FOUT"

# 项目绝对路径包含 build 时，统一语言探测仍必须识别项目内容。
mk_react build/react_only
FOUT_BUILD="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/build/react_only")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$FOUT_BUILD"

# Vue 2 legacy 也应路由到 frontend
mk_vue2 vue2_only
VOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/vue2_only")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$VOUT"

# Node 服务应作为支持目标进入 frontend-family adapter
mk_node node_only
NOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/node_only")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$NOUT"

# 混合：两者都报
mk_java mixed; mk_react mixed
MOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/mixed")"
grep -q "CANDIDATE_LANGUAGE:java" <<< "$MOUT"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$MOUT"

# 仅有 package.json 但无 React 依赖 → 不报前端
mkdir -p "$TMP_DIR/no_react"
cat > "$TMP_DIR/no_react/package.json" <<'JSON'
{"name":"lib","dependencies":{"lodash":"^4.0.0"}}
JSON
NOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/no_react")"
! grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$NOUT"

# 空目录 → none
mkdir -p "$TMP_DIR/empty"
EOUT="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$TMP_DIR/empty")"
grep -q "CANDIDATE_LANGUAGE:none" <<< "$EOUT"

echo "PASS: detect-language"
