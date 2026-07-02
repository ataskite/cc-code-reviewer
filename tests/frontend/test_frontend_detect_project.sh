#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-detect.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mk_react_vite() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"},
 "devDependencies":{"vite":"^5.0.0","typescript":"^5.0.0"}}
JSON
  echo 'export default function App(){return <h1/>}' > "$d/src/App.tsx"
  cat > "$d/vite.config.ts" <<'TS'
import { defineConfig } from 'vite'; export default defineConfig({})
TS
}

mk_react_js() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"app","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}
JSON
  cat > "$d/src/App.js" <<'JS'
import React from 'react';
export default function App(){ return React.createElement('h1', null, 'hi'); }
JS
}

mk_nextjs() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src/app"
  cat > "$d/package.json" <<'JSON'
{"name":"next","dependencies":{"next":"^14.0.0","react":"^18.2.0"}}
JSON
  echo 'export default function P(){return <div/>}' > "$d/src/app/page.tsx"
}

mk_vue2() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"legacy-vue","dependencies":{"vue":"^2.6.14","vue-router":"^3.6.5","vuex":"^3.6.2"},
 "devDependencies":{"vue-template-compiler":"^2.6.14","webpack":"^4.46.0"}}
JSON
  cat > "$d/src/App.vue" <<'VUE'
<template><div>{{ title }}</div></template>
<script>
export default { data() { return { title: 'legacy' } } }
</script>
VUE
}

mk_vue3() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"modern-vue","dependencies":{"vue":"^3.4.0","vue-router":"^4.2.0","pinia":"^2.1.0"},
 "devDependencies":{"@vitejs/plugin-vue":"^5.0.0","vite":"^5.0.0"}}
JSON
  cat > "$d/src/App.vue" <<'VUE'
<script setup>
import { ref } from 'vue'
const title = ref('modern')
</script>
<template><div>{{ title }}</div></template>
VUE
}

mk_node_service() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src"
  cat > "$d/package.json" <<'JSON'
{"name":"api","type":"module","main":"src/server.js","engines":{"node":">=18"},
 "dependencies":{"express":"^4.18.0"}}
JSON
  echo "import express from 'express'; export const app = express();" > "$d/src/server.js"
}

# React + Vite → frontend-react
mk_react_vite react_vite
grep -q "PROJECT_TYPE=frontend-react" < <(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/react_vite")

# React + plain JS → frontend-react（首期承诺支持 React/JS，不要求必须 .tsx/.jsx）
mk_react_js react_js
grep -q "PROJECT_TYPE=frontend-react" < <(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/react_js")

# Vue 2 legacy → frontend-vue2（公司内 legacy 主力）
mk_vue2 vue2
grep -q "PROJECT_TYPE=frontend-vue2" < <(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/vue2")

# Vue 3 → frontend-vue3
mk_vue3 vue3
grep -q "PROJECT_TYPE=frontend-vue3" < <(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/vue3")

# Node 服务 → node
mk_node_service node_api
grep -q "PROJECT_TYPE=node" < <(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/node_api")

# Next.js → 不支持
mk_nextjs nx
OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/nx")"
grep -q "PROJECT_TYPE=frontend-unsupported" <<< "$OUT"
grep -q "reason=nextjs" <<< "$OUT"

echo "PASS: frontend detect-project"
