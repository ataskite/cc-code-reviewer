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

mk_nextjs() {
  local d="$TMP_DIR/$1"; mkdir -p "$d/src/app"
  cat > "$d/package.json" <<'JSON'
{"name":"next","dependencies":{"next":"^14.0.0","react":"^18.2.0"}}
JSON
  echo 'export default function P(){return <div/>}' > "$d/src/app/page.tsx"
}

# React + Vite → frontend-react
mk_react_vite react_vite
grep -q "PROJECT_TYPE=frontend-react" < <(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/react_vite")

# Next.js → 不支持
mk_nextjs nx
OUT="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$TMP_DIR/nx")"
grep -q "PROJECT_TYPE=frontend-unsupported" <<< "$OUT"
grep -q "reason=nextjs" <<< "$OUT"

echo "PASS: frontend detect-project"
