#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-route-vue2.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# 场景 1：vue-template-compiler + vue@2 + .vue SFC → frontend-vue2
D1="$TMP_DIR/vue2_compiler"; mkdir -p "$D1/src"
cat > "$D1/package.json" <<'JSON'
{"name":"legacy","dependencies":{"vue":"^2.7.0","vue-template-compiler":"^2.7.0"}}
JSON
printf '<template><div/></template>\n' > "$D1/src/App.vue"
LOUT1="$(bash "$ROOT_DIR/scripts/core/detect-language.sh" "$D1")"
grep -q "CANDIDATE_LANGUAGE:frontend" <<< "$LOUT1"
! grep -q "CANDIDATE_LANGUAGE:java" <<< "$LOUT1"
POUT1="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D1")"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$POUT1"
! grep -q "PROJECT_TYPE=frontend-react" <<< "$POUT1"
SOUT1="$(bash "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" "$D1")"
grep -q "PROFILE_SCHEMA_VERSION=1" <<< "$SOUT1"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$SOUT1"
grep -q "TECH_STACK:Vue 2" <<< "$SOUT1"

# 场景 2：@vue/cli-service + vue@2 + .vue → frontend-vue2
D2="$TMP_DIR/vue2_cli"; mkdir -p "$D2/src"
cat > "$D2/package.json" <<'JSON'
{"name":"cli-app","dependencies":{"vue":"^2.6.14","@vue/cli-service":"^5.0.0"}}
JSON
printf '<template><span/></template>\n' > "$D2/src/App.vue"
POUT2="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D2")"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$POUT2"

# 场景 3：vite-plugin-vue2 + vue@2 → frontend-vue2
D3="$TMP_DIR/vue2_vite"; mkdir -p "$D3/src"
cat > "$D3/package.json" <<'JSON'
{"name":"vite2","dependencies":{"vue":"^2.7.0","vite-plugin-vue2":"^2.3.0"}}
JSON
printf '<template><p/></template>\n' > "$D3/src/App.vue"
POUT3="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D3")"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$POUT3"

echo "PASS: frontend route vue2"
