#!/bin/bash
set -euo pipefail
# Vue 内容信号回退：无版本锁定的 vue 依赖或漏写依赖时，靠 Vue API 内容判版本。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fe-route-content.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# 场景 1：vue@*（无版本锁定）+ createApp( 内容 → frontend-vue3
D1="$TMP_DIR/content_v3"; mkdir -p "$D1/src"
cat > "$D1/package.json" <<'JSON'
{"name":"noversion","dependencies":{"vue":"*"}}
JSON
cat > "$D1/src/main.ts" <<'TS'
import { createApp } from 'vue';
createApp({}).mount('#app');
TS
POUT1="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D1")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT1"

# 场景 2：vue@* + defineComponent( 内容 → frontend-vue3
D1B="$TMP_DIR/content_v3_define_component"; mkdir -p "$D1B/src"
cat > "$D1B/package.json" <<'JSON'
{"name":"noversion-define","dependencies":{"vue":"*"}}
JSON
cat > "$D1B/src/App.ts" <<'TS'
import { defineComponent } from 'vue';
export default defineComponent({ name: 'App' });
TS
POUT1B="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D1B")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT1B"

# 场景 3：vue@* + createSSRApp( 内容 → frontend-vue3
D1C="$TMP_DIR/content_v3_ssr"; mkdir -p "$D1C/src"
cat > "$D1C/package.json" <<'JSON'
{"name":"noversion-ssr","dependencies":{"vue":"*"}}
JSON
cat > "$D1C/src/entry-server.ts" <<'TS'
import { createSSRApp } from 'vue';
export function createApp() { return createSSRApp({}); }
TS
POUT1C="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D1C")"
grep -q "PROJECT_TYPE=frontend-vue3" <<< "$POUT1C"

# 场景 4：vue@* + new Vue( 内容 → frontend-vue2
D2="$TMP_DIR/content_v2"; mkdir -p "$D2/src"
cat > "$D2/package.json" <<'JSON'
{"name":"noversion2","dependencies":{"vue":"*"}}
JSON
cat > "$D2/src/main.js" <<'JS'
import Vue from 'vue';
new Vue({ render: h => h('div') }).$mount('#app');
JS
POUT2="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D2")"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$POUT2"

# 场景 5：Vue2 class-component / decorator 依赖被 hoist，package 内无 vue key → frontend-vue2
D3="$TMP_DIR/content_v2_class"; mkdir -p "$D3/src"
cat > "$D3/package.json" <<'JSON'
{"name":"legacy-class","dependencies":{"vue-class-component":"^7.2.0","vue-property-decorator":"^9.1.2","@vue/composition-api":"^1.7.2"}}
JSON
cat > "$D3/src/App.vue" <<'VUE'
<template><div>{{ title }}</div></template>
<script lang="ts">
import Vue from 'vue';
import Component from 'vue-class-component';

@Component
export default class App extends Vue {
  title = 'legacy';
}
</script>
VUE
POUT3="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D3")"
grep -q "PROJECT_TYPE=frontend-vue2" <<< "$POUT3"

# 场景 6：普通 TS/Node helper 仅同名 defineComponent，不得误判 Vue
D4="$TMP_DIR/plain_helper"; mkdir -p "$D4/src"
cat > "$D4/package.json" <<'JSON'
{"name":"plain-helper","type":"module"}
JSON
cat > "$D4/src/plain.ts" <<'TS'
export function defineComponent(input: unknown) { return input; }
export const config = defineComponent({ name: 'not-vue' });
TS
POUT4="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D4")"
! grep -q "PROJECT_TYPE=frontend-vue" <<< "$POUT4"
grep -q "PROJECT_TYPE=node" <<< "$POUT4"

# 场景 7：普通 JS 仅同名 new Vue，不得误判 Vue
D5="$TMP_DIR/plain_new_vue"; mkdir -p "$D5/src"
cat > "$D5/package.json" <<'JSON'
{"name":"plain-new-vue"}
JSON
cat > "$D5/src/plain.js" <<'JS'
class Vue {}
new Vue();
JS
POUT5="$(bash "$ROOT_DIR/scripts/languages/frontend/detect-project.sh" "$D5")"
! grep -q "PROJECT_TYPE=frontend-vue" <<< "$POUT5"
grep -q "PROJECT_TYPE=frontend-unsupported|reason=generic-tsjs" <<< "$POUT5"

echo "PASS: frontend route vue content signal fallback"
