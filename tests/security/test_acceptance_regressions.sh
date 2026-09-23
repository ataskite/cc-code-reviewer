#!/bin/bash
set -euo pipefail

# 验收回归（/tmp/ccr-acceptance-20260922/REVIEW.md R1-R4）：
# - R1：封装调用（改名/跨文件/仅入口增量）不得把 BFFHEADER/SSRF 提前排除；
#       信号只导航与确认适用，不构成排除；纯浏览器项目不进 Node 控制
# - R2：批次缺台账/缺行/重复/非法状态时不得聚合出全量 checked_no_finding
# - R3：带引号键、成员/括号赋值、连接串 userinfo 的敏感值必须脱敏
# - R4：无 Node profile 的纯浏览器项目不得执行 Node 步骤（planner 不报错、surface 为 null）
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec-accept.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL(acceptance): $*" >&2; exit 1; }

make_input() { # <out> <file...> 相对路径（在当前 fixture 目录内执行）
  local out="$1"; shift
  perl -MJSON::PP -e '
    my ($out, @rel) = @ARGV;
    my @items = map { +{ path => $_, change => "added", old_path => "", selected => "true", exclude_reason => "", insertions => 1, deletions => 0, fingerprint => "" } } @rel;
    open my $fh, ">", $out or die; print {$fh} JSON::PP->new->canonical->utf8->encode({ schema_version => 1, language_id => "frontend", items => \@items }), "\n"; close $fh;
  ' "$out" "$@"
}

ids_of() { perl -MJSON::PP -0777 -e 'my $d=decode_json(do{local $/;open my $f,"<",$ARGV[0] or die;<$f>}); print join("\n", map { $_->{id} } @{$d->{controls}})' "$1"; }

# ================= R1：封装调用不提前排除 =================

# 场景 A：事故形态——入口文件里 Http.request（改名封装）+ req 透传，封装实现未选入
WA="$TMP/wrapper-a"; mkdir -p "$WA/src"
cat > "$WA/package.json" <<'JSON'
{"name":"wrapper-a","main":"server.js","dependencies":{"vue":"^2.6.10","express":"^4.16.0"}}
JSON
echo '<template><div/></template>' > "$WA/src/Home.vue"
cat > "$WA/server.js" <<'JS'
const router = require('express').Router();
module.exports.relay = function (req, res) {
  const rb = req.body;
  return Http.request(Config.app.apiHost + rb.url, rb.data, rb.method, req, rb.header);
};
router.post('/gateway', function (req, res) { /* 调 relay */ });
JS
( cd "$WA" && make_input "$TMP/in-a.json" package.json src/Home.vue server.js )
bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$WA" frontend-vue2 "$TMP/in-a.json" "$TMP/ctrl-a.json" >/dev/null 2>&1 || fail "R1A resolver failed"
IDS_A="$(ids_of "$TMP/ctrl-a.json")"
printf '%s\n' "$IDS_A" | grep -qx 'CCR-NODE-BFFHEADER-001' || fail "R1A: BFFHEADER 被提前排除（封装 Http.request 未命中词表）"
printf '%s\n' "$IDS_A" | grep -qx 'CCR-NODE-SSRF-001' || fail "R1A: SSRF 被提前排除"

# 场景 A2：真正的增量范围只含 Node 入口文件；已检测项目类型仍是 frontend-vue2。
# Profile 必须依赖项目类型，不要求本轮所选文件重复带入 .vue/package.json。
( cd "$WA" && make_input "$TMP/in-a2.json" server.js )
bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$WA" frontend-vue2 "$TMP/in-a2.json" "$TMP/ctrl-a2.json" >/dev/null 2>&1 || fail "R1A2 resolver failed"
IDS_A2="$(ids_of "$TMP/ctrl-a2.json")"
printf '%s\n' "$IDS_A2" | grep -qx 'CCR-NODE-BFFHEADER-001' || fail "R1A2: server-only 增量审查丢失 BFFHEADER profile"
printf '%s\n' "$IDS_A2" | grep -qx 'CCR-NODE-SSRF-001' || fail "R1A2: server-only 增量审查丢失 SSRF 控制"

# 场景 B：任意改名封装 + 完全无已知外发关键词
WB="$TMP/wrapper-b"; mkdir -p "$WB/src"
cat > "$WB/package.json" <<'JSON'
{"name":"wrapper-b","main":"app.js","dependencies":{"vue":"^2.6.10","express":"^4.16.0"}}
JSON
echo '<template><div/></template>' > "$WB/src/Home.vue"
cat > "$WB/app.js" <<'JS'
const app = require('express')();
app.post('/forward', function (req, res) {
  coreTransport.req(Config.app.apiHost + req.body.url, req.body.data, req, req.header);
});
app.listen(8080);
JS
( cd "$WB" && make_input "$TMP/in-b.json" package.json src/Home.vue app.js )
bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$WB" frontend-vue2 "$TMP/in-b.json" "$TMP/ctrl-b.json" >/dev/null 2>&1
IDS_B="$(ids_of "$TMP/ctrl-b.json")"
printf '%s\n' "$IDS_B" | grep -qx 'CCR-NODE-BFFHEADER-001' || fail "R1B: 任意改名封装仍排除 BFFHEADER"
printf '%s\n' "$IDS_B" | grep -qx 'CCR-NODE-SSRF-001' || fail "R1B: 任意改名封装仍排除 SSRF"

# 场景 C：跨文件封装（入口 + 封装实现都选入，但封装用未知名）
WC="$TMP/wrapper-c"; mkdir -p "$WC/src" "$WC/lib"
cat > "$WC/package.json" <<'JSON'
{"name":"wrapper-c","main":"server.js","dependencies":{"vue":"^2.6.10","express":"^4.16.0"}}
JSON
echo '<template><div/></template>' > "$WC/src/Home.vue"
cat > "$WC/lib/transport.js" <<'JS'
var https = require('https2fake');
module.exports = function send(upstreamUrl, payload, req, headerBag) {
  return https2fake.request(upstreamUrl, { headers: Object.assign({}, headerBag) });
};
JS
cat > "$WC/server.js" <<'JS'
const app = require('express')();
const send = require('./lib/transport');
app.post('/gateway', function (req, res) {
  send(Config.app.apiHost + req.body.url, req.body, req, req.header);
});
app.listen(8080);
JS
( cd "$WC" && make_input "$TMP/in-c.json" package.json src/Home.vue server.js lib/transport.js )
bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$WC" frontend-vue2 "$TMP/in-c.json" "$TMP/ctrl-c.json" >/dev/null 2>&1
IDS_C="$(ids_of "$TMP/ctrl-c.json")"
printf '%s\n' "$IDS_C" | grep -qx 'CCR-NODE-SSRF-001' || fail "R1C: 跨文件封装仍排除 SSRF"

# 场景 D：纯浏览器项目不受影响
WD="$TMP/pure-browser"; mkdir -p "$WD/src"
cat > "$WD/package.json" <<'JSON'
{"name":"pure-browser","dependencies":{"react":"^18.2.0"}}
JSON
printf 'import { useState } from "react";\nexport function App() { return 1; }\n' > "$WD/src/App.tsx"
( cd "$WD" && make_input "$TMP/in-d.json" package.json src/App.tsx )
OUT_D="$(bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$WD" frontend-react "$TMP/in-d.json" "$TMP/ctrl-d.json" 2>/dev/null)" || fail "R1D resolver failed"
printf '%s\n' "$OUT_D" | grep -q 'SECURITY_PROFILES= CONTROLS=0 ' || fail "R1D: 纯浏览器项目被误纳入 Node 控制"

# ================= R4：纯浏览器分批链路不进 Node 步骤 =================
MANIFEST="$TMP/browser-manifest.txt"
bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$WD" 2>/dev/null > "$MANIFEST"
CC_CODE_REVIEWER_RUNS_ROOT="$TMP/runs" CC_CODE_REVIEWER_RUN_TIMESTAMP=20260922-160000 \
  bash "$ROOT_DIR/scripts/core/plan-file-batches.sh" "$WD" security main frontend "$MANIFEST" \
  > "$TMP/r4-plan.out" 2>"$TMP/r4-plan.err" || { cat "$TMP/r4-plan.err" >&2; fail "R4: 纯浏览器 security 分批失败"; }
RUN4="$(sed -n 's/^RUN_DIR=//p' "$TMP/r4-plan.out")"
if grep -q 'ERROR_SECURITY_SURFACE_NO_NODE_PROFILE' "$TMP/r4-plan.err"; then fail "R4: 纯浏览器项目仍触发了 surface 生成"; fi
grep -q '"security_surface_path": null' "$RUN4/plan.json" || fail "R4: surface 字段应为 null"
[ -f "$RUN4/security-controls.json" ] || fail "R4: controls 冻结文件缺失"
bash "$ROOT_DIR/scripts/core/validate-resume-input.sh" "$RUN4" "$WD" --rules --security >/dev/null 2>&1 || fail "R4: 纯浏览器 security 门禁失败"

# 零 Node profile 仍需通过统一 Security 报告校验：控制全数明确标记不适用，
# 避免在单 Agent 路径因 CONTROLS_EMPTY 阻断普通浏览器前端审查。
EXCLUDED_D="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do{local $/;open my $f,"<",$ARGV[0] or die;<$f>}); print join("\n",map {$_->{id}} @{$d->{excluded_controls}})' "$TMP/ctrl-d.json")"
EXCLUDED_COUNT_D="$(printf '%s\n' "$EXCLUDED_D" | awk 'NF{n++} END{print n+0}')"
{
  cat <<MD
# 纯浏览器 Security 报告

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：0
- 已发现问题：0
- 已检查无发现：0
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：$EXCLUDED_COUNT_D
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
MD
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    printf '| %s | 无 Node 服务端代码 | - | config | not_applicable | 本轮项目无 Node profile |\n' "$id"
  done <<< "$EXCLUDED_D"
} > "$TMP/no-node-report.md"
bash "$ROOT_DIR/scripts/core/validate-security-report.sh" "$TMP/no-node-report.md" "$TMP/ctrl-d.json" >/dev/null 2>&1 \
  || fail "R4: 零适用 Node 控制的显式 not_applicable 报告被拒绝"

# ================= R3：脱敏泄漏 =================
SE="$TMP/secrets"; mkdir -p "$SE"
cat > "$SE/package.json" <<'JSON'
{"name":"secrets-fixture","main":"app.js","dependencies":{"express":"^4.18.0"}}
JSON
cat > "$SE/app.js" <<'JS'
const express = require('express');
const app = express();
const db = require('./db');
app.post('/login', function (req, res) {
  const headers = { "Authorization": "short-example-key-123", "X-Ticket": 'tiny-tok-9' };
  db.connect('mongodb://example-user:example-pass@localhost/db');
  headers["Api-Key"] = "abc123def456ghi789";
  headers['Api-Token'] = "tok_1a2b3c4d5e6f7a8b9c0d";
  fetch(req.body.url, { headers: { Authorization: req.headers.authorization } });
});
app.listen(3000);
JS
( cd "$SE" && make_input "$TMP/in-se.json" package.json app.js )
bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$SE" node "$TMP/in-se.json" "$TMP/ctrl-se.json" >/dev/null 2>&1
bash "$ROOT_DIR/scripts/languages/frontend/prepare-security-surface.sh" "$SE" "$TMP/in-se.json" "$TMP/ctrl-se.json" "$TMP/surface-se.json" >/dev/null 2>&1 || fail "R3: surface 生成失败"
for secret in 'short-example-key-123' 'tiny-tok-9' 'example-pass' 'abc123def456ghi789' 'tok_1a2b3c4d5e6f7a8b9c0d'; do
  if grep -q "$secret" "$TMP/surface-se.json"; then fail "R3: 敏感值 [$secret] 原样进入 surface 索引"; fi
done
grep -q 'MASKED' "$TMP/surface-se.json" || fail "R3: 未产生任何掩码标记"

# ================= R2：批次缺台账不得聚合出 checked_no_finding =================
# 批次 001 固定：SSRF checked_no_finding（有效台账）；变化的是批次 002 的形态。
setup_merge_case() { # <name>
  SR="$TMP/merge-$1"; mkdir -p "$SR/batches" "$SR/results"
  cat > "$SR/plan.json" <<JSON
{"schema_version":1,"run_id":"m-$1","project_name":"demo","review_mode":"security","review_scope":"全量代码","language_id":"frontend","total_source_loc":500,"total_source_file_count":2,"batch_count":2,"security_controls_path":"$SR/security-controls.json","security_catalog_path":"$ROOT_DIR/references/security/catalog/node-security-controls.json"}
JSON
  printf '{"controls":[{"id":"CCR-NODE-SSRF-001"}],"excluded_controls":[]}' > "$SR/security-controls.json"
  local b
  for b in 001 002; do
    printf '{"batch_id":"batch-%s","planned_source_loc":250,"planned_source_file_count":1,"scan_roots":["src/x"],"modules":[{"name":"x"}]}' "$b" > "$SR/batches/batch-$b.json"
    printf '{"batch_id":"batch-%s","status":"completed","planned_source_loc":250,"planned_source_file_count":1,"result_path":"%s","finding_count":0}' "$b" "$SR/results/batch-$b.md" > "$SR/results/batch-$b.status.json"
  done
  cat > "$SR/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
（无正式发现）
## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：0
- 已检查无发现：1
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：0
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-SSRF-001 | t | m | taint | checked_no_finding | 批次1无发现 |
MD
}
merge_run() {
  MERGE_WAIT_TIMEOUT_SECONDS=0 RUN_BATCH_IDS=batch-001,batch-002 \
    bash "$ROOT_DIR/scripts/core/merge-batch-results.sh" "$SR" 2>&1 || true
}
report_of() { sed -n 's/^FINAL_REPORT_PATH=//p'; }

# 2a. batch-002 完全没有台账
setup_merge_case no-section
cat > "$SR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
MD
R2A="$(merge_run | report_of)"
if grep -q '| CCR-NODE-SSRF-001 |.*| checked_no_finding |' "$R2A"; then fail "R2a: 缺整节仍聚合为 checked_no_finding"; fi
grep -q '| CCR-NODE-SSRF-001 |.*| external_evidence_missing |' "$R2A" || fail "R2a: 缺整节应降级为 external_evidence_missing"
grep -q 'batch-002' "$R2A" || fail "R2a: 应点名缺失台账的批次"
bash "$ROOT_DIR/scripts/core/validate-security-report.sh" "$R2A" "$SR/security-controls.json" >/dev/null 2>&1 \
  || fail "R2a: 有明确批次证据的 external_evidence_missing 台账应可校验（不等同于漏洞发现）"

# 2b. batch-002 台账缺该控制行（含其他控制的行）
setup_merge_case missing-row
cat > "$SR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：0
- 已检查无发现：0
- 外部证据缺失：1
- 静态不可验证：0
- 不适用：0
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-OTHER-000 | t | m | taint | external_evidence_missing | x |
MD
R2B="$(merge_run | report_of)"
if grep -q '| CCR-NODE-SSRF-001 |.*| checked_no_finding |' "$R2B"; then fail "R2b: 缺行仍聚合为 checked_no_finding"; fi

# 2c. batch-002 台账该控制重复行
setup_merge_case dup-row
cat > "$SR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：0
- 已检查无发现：1
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：0
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-SSRF-001 | t | m | taint | checked_no_finding | a |
| CCR-NODE-SSRF-001 | t | m | taint | checked_no_finding | b |
MD
R2C="$(merge_run | report_of)"
if grep -q '| CCR-NODE-SSRF-001 |.*| checked_no_finding |' "$R2C"; then fail "R2c: 批内重复行仍聚合为 checked_no_finding"; fi

# 2d. batch-002 台账非法状态
setup_merge_case bad-status
cat > "$SR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：0
- 已检查无发现：1
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：0
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-SSRF-001 | t | m | taint | probably-fine | x |
MD
R2D="$(merge_run | report_of)"
if grep -q '| CCR-NODE-SSRF-001 |.*| checked_no_finding |' "$R2D"; then fail "R2d: 非法状态仍聚合为 checked_no_finding"; fi

# 2e. 两批都有效且均 checked_no_finding → 允许全量 checked_no_finding
setup_merge_case both-ok
cat > "$SR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：0
- 已检查无发现：1
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：0
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-SSRF-001 | t | m | taint | checked_no_finding | 批次2无发现 |
MD
R2E="$(merge_run | report_of)"
grep -q '| CCR-NODE-SSRF-001 |.*| checked_no_finding |' "$R2E" || fail "R2e: 两批均有效时应有全量 checked_no_finding"

# 2f. 完成批次状态存在，但结果报告文件丢失：不能忽略此批次后给全量通过。
setup_merge_case missing-file
rm -f "$SR/results/batch-002.md"
R2F="$(merge_run | report_of)"
if grep -q '| CCR-NODE-SSRF-001 |.*| checked_no_finding |' "$R2F"; then fail "R2f: 缺失批次结果文件仍聚合为 checked_no_finding"; fi
grep -q '| CCR-NODE-SSRF-001 |.*| external_evidence_missing |' "$R2F" || fail "R2f: 缺失结果文件应降级为 external_evidence_missing"
grep -q 'batch-002' "$R2F" || fail "R2f: 缺结果文件应点名 batch-002"

# 2g. 被 profile 排除的控制经正式语义发现提升后，计数与校验器必须一致。
setup_merge_case elevation
printf '{"security_profile":["node-api"],"controls":[{"id":"CCR-NODE-BOLA-001"}],"excluded_controls":[{"id":"CCR-NODE-SSRF-001","reason":"profile only"}]}' > "$SR/security-controls.json"
cat > "$SR/results/batch-001.md" <<'MD'
# Batch 001
## 发现列表
### P1 | [维度6-安全] webhook 目标可访问内网地址

- 文件：server.js:10
- **安全规则 ID**：CCR-NODE-SSRF-001
- **标准映射**：OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918
- **检测方式**：taint
- 证据：用户可控 URL 进入服务端外发请求。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：0
- 已检查无发现：1
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：0
- 语义提升：1
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-BOLA-001 | t | m | semantic | checked_no_finding | 未发现 |
| CCR-NODE-SSRF-001 | t | m | taint | finding_confirmed | 用户输入到 fetch |
MD
cat > "$SR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
（无正式发现）
## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：0
- 已检查无发现：1
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-BOLA-001 | t | m | semantic | checked_no_finding | 未发现 |
| CCR-NODE-SSRF-001 | t | m | taint | not_applicable | profile only |
MD
R2G="$(merge_run | report_of)"
grep -q -- '- 语义提升：1' "$R2G" || fail "R2g: 被排除发现应单列一个语义提升"
grep -q '| CCR-NODE-SSRF-001 |.*| finding_confirmed |' "$R2G" || fail "R2g: 合并报告未保留被提升的正式发现"
bash "$ROOT_DIR/scripts/core/validate-security-report.sh" "$R2G" "$SR/security-controls.json" >/dev/null 2>&1 \
  || fail "R2g: 语义提升后的合并报告计数与校验不一致"

# 2h. partial 批次中的正式发现要保留；未完成只阻止 checked_no_finding 通过。
setup_merge_case partial-finding
perl -0pi -e 's/"status":"completed"/"status":"partial"/; s/"finding_count":0/"finding_count":1/' "$SR/results/batch-002.status.json"
cat > "$SR/results/batch-002.md" <<'MD'
# Batch 002
## 发现列表
### P1 | [维度6-安全] 用户可控 webhook 目标进入外发请求

- 文件：server.js:10
- **安全规则 ID**：CCR-NODE-SSRF-001
- **标准映射**：OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / CWE-918
- **检测方式**：taint
- 证据：请求 URL 进入服务端请求目标。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：1
- 已检查无发现：0
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：0
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-SSRF-001 | t | m | taint | finding_confirmed | 正式发现 |
MD
R2H="$(merge_run | report_of)"
grep -q '| CCR-NODE-SSRF-001 |.*| finding_confirmed |' "$R2H" || {
  grep 'CCR-NODE-SSRF-001' "$R2H" >&2 || true
  cat "$SR/summary.json" >&2
  cat "$SR/results/batch-002.status.json" >&2
  fail "R2h: partial 批次中的正式 finding_confirmed 未进入全局台账"
}
bash "$ROOT_DIR/scripts/core/validate-security-report.sh" "$R2H" "$SR/security-controls.json" >/dev/null 2>&1 \
  || fail "R2h: 保留 partial 批次正式发现后的报告校验失败"

echo "PASS: acceptance regressions R1-R4"
