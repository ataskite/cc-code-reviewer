#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-route-vue3.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# 场景 1：@vitejs/plugin-vue + vue@3 + .vue → frontend-vue3
D1="$TMP_DIR/vue3_vite"; mkdir -p "$D1/src"
cat > "$D1/package.json" <<'JSON'
{"name":"vite3","dependencies":{"vue":"^3.4.0","@vitejs/plugin-vue":"^5.0.0"}}
JSON
printf '<template><div/></template>\n' > "$D1/src/App.vue"
LOUT1="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$D1")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$LOUT1"
POUT1="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D1")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT1"
! grep -q "PROJECT_TYPE=frontend-react" <<< "$POUT1"
SOUT1="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D1")"
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$SOUT1"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$SOUT1"
grep -q "TECH_STACK:Vue 3" <<< "$SOUT1"

# 场景 2：pinia + vue@3 + .vue → frontend-vue3
D2="$TMP_DIR/vue3_pinia"; mkdir -p "$D2/src"
cat > "$D2/package.json" <<'JSON'
{"name":"pinia-app","dependencies":{"vue":"^3.3.0","pinia":"^2.1.0"}}
JSON
printf '<template><span/></template>\n' > "$D2/src/App.vue"
POUT2="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D2")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT2"

# 场景 3：vue-router@4 + vue@3 → frontend-vue3
D3="$TMP_DIR/vue3_router"; mkdir -p "$D3/src"
cat > "$D3/package.json" <<'JSON'
{"name":"router-app","dependencies":{"vue":"^3.4.0","vue-router":"^4.2.0"}}
JSON
printf '<template><p/></template>\n' > "$D3/src/App.vue"
POUT3="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D3")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT3"

echo "PASS: frontend route vue3"
