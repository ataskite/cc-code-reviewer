#!/bin/bash
set -euo pipefail

# prepare-security-surface.sh 契约：
# - 识别 Express 路由、req.body、axios、child_process、fs、session 候选位置
# - secure 与 vulnerable 代码都产生候选索引，但输出绝不出现 finding/severity 字段
# - 疑似密钥值不进入 JSON（键名 + *** 掩码）
# - selected=false 文件完全不出现；.vue/.json 等非服务端扩展名不扫描
# - 同输入两次运行字节一致；无 Node profile 的 controls.json 拒绝生成（fail closed）
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SURFACE="$ROOT_DIR/scripts/languages/frontend/prepare-security-surface.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec-surface.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL(surface): $*" >&2; exit 1; }

# ---- fixture：express BFF（含危险与安全写法 + 密钥行 + 非 selected 文件）----
D="$TMP/bff"; mkdir -p "$D/src" "$D/secret-dir"
cat > "$D/app.js" <<'JS'
const express = require('express');
const axios = require('axios');
const { exec } = require('child_process');
const fs = require('fs');
const app = express();
const API_TOKEN = 'sk-live-abcdef1234567890abcdef1234567890';
app.post('/proxy', function (req, res) {
  axios.post('http://upstream.internal/v1', req.body, { headers: req.headers });
  axios.get('http://upstream.internal/v1', { headers: { Authorization: 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' } });
});
app.post('/export', function (req, res) {
  exec('convert ' + req.query.file);
  fs.readFile('/data/' + req.params.name, function (e, buf) { res.send(buf); });
});
app.get('/safe', function (req, res) {
  req.session.lastView = 'home';
  res.send('ok');
});
app.listen(3000);
JS
# selected=false 的文件：绝不能出现在 surface 中
printf 'const { exec } = require("child_process");\nexec("rm -rf /" + req.body.x);\n' > "$D/hidden.js"
# 非服务端扩展名：不扫描
echo '<template><div/></template>' > "$D/src/Home.vue"

perl -MJSON::PP -e '
  my ($out, @files) = @ARGV;
  my @items = map {
    my $sel = ($_ =~ /hidden\.js$/) ? "false" : "true";
    +{ path => $_, change => "added", old_path => "", selected => $sel, exclude_reason => ($sel eq "true" ? "" : "outside-source-manifest"), insertions => 1, deletions => 0, fingerprint => "" }
  } @files;
  open my $fh, ">", $out or die;
  print {$fh} JSON::PP->new->canonical->utf8->encode({ schema_version => 1, language_id => "frontend", items => \@items }), "\n";
  close $fh;
' "$TMP/in.json" "$D/app.js" "$D/hidden.js" "$D/src/Home.vue"

# controls fixture：启用 node-bff profile
printf '{"schema_version":1,"security_profile":["node-api","node-bff"],"controls":[]}' > "$TMP/controls.json"

OUT="$(bash "$SURFACE" "$D" "$TMP/in.json" "$TMP/controls.json" "$TMP/surface.json")" || fail "surface generator failed: $OUT"
printf '%s\n' "$OUT" | grep -Eq '^SECURITY_SURFACE_PATH=.*/surface\.json FILES=1 ENTRIES=[0-9]+ SOURCES=[0-9]+ SINKS=[0-9]+ LIMITATIONS=[0-9]+$' \
  || fail "stdout contract violated: $OUT"

# ---- 候选识别断言（kind 级别）----
KINDS="$(perl -MJSON::PP -0777 -e '
  my $d = decode_json(do { local $/; open my $fh, "<", $ARGV[0] or die; <$fh> });
  my %k; for my $b (qw(entries identity_sources request_sources sensitive_sinks outbound_clients config_signals)) {
    $k{"$b:" . $_->{kind}} = 1 for @{ $d->{$b} };
  }
  print join("\n", sort keys %k);
' "$TMP/surface.json")"
for want in \
  "entries:http-route" \
  "entries:server-listen" \
  "identity_sources:session-identity" \
  "request_sources:request-body" \
  "request_sources:request-query" \
  "request_sources:request-params" \
  "request_sources:request-headers" \
  "sensitive_sinks:outbound-http" \
  "outbound_clients:outbound-http" \
  "sensitive_sinks:child-process-exec" \
  "sensitive_sinks:fs-access" \
  "sensitive_sinks:session-write"
do
  printf '%s\n' "$KINDS" | grep -qx "$want" || fail "missing candidate kind: $want"
done

# ---- secure/vulnerable 都只是候选：输出绝不出现 finding/severity 字段 ----
if grep -qE '"(finding|severity|priority|level)"' "$TMP/surface.json"; then
  fail "surface output must not contain finding/severity fields"
fi

# ---- 密钥值脱敏：sk-live-... 原值不出现，掩码出现 ----
! grep -q 'sk-live-abcdef1234567890' "$TMP/surface.json" || fail "raw secret leaked into surface json"
grep -q 'MASKED' "$TMP/surface.json" || fail "masking marker expected in surface json"

# ---- selected=false 文件与 .vue 完全不出现 ----
! grep -q 'hidden\.js' "$TMP/surface.json" || fail "selected=false file must not appear"
! grep -q 'Home\.vue' "$TMP/surface.json" || fail "non-server extension must not appear"

# ---- 确定性：同输入两次运行字节一致 ----
bash "$SURFACE" "$D" "$TMP/in.json" "$TMP/controls.json" "$TMP/surface2.json" >/dev/null 2>&1
cmp -s "$TMP/surface.json" "$TMP/surface2.json" || fail "surface output not byte-stable"

# ---- 大文件 limitation ----
BIG="$D/big.js"
perl -e 'print "const x = 1; // padding\n" x 1 for 1..1; for (1..21000) { print "const y = $_;\n" }' > "$BIG"
perl -MJSON::PP -e '
  my ($out, @files) = @ARGV;
  my @items = map { +{ path => $_, change => "added", old_path => "", selected => "true", exclude_reason => "", insertions => 1, deletions => 0, fingerprint => "" } } @files;
  open my $fh, ">", $out or die; print {$fh} JSON::PP->new->canonical->utf8->encode({ schema_version => 1, language_id => "frontend", items => \@items }), "\n"; close $fh;
' "$TMP/in-big.json" "$BIG"
bash "$SURFACE" "$D" "$TMP/in-big.json" "$TMP/controls.json" "$TMP/surface-big.json" >/dev/null 2>&1
grep -q '"line cap reached (20000): big.js"' "$TMP/surface-big.json" || fail "line-cap limitation missing"

# ---- fail closed：无 Node profile ----
printf '{"schema_version":1,"security_profile":[],"controls":[]}' > "$TMP/controls-empty.json"
if bash "$SURFACE" "$D" "$TMP/in.json" "$TMP/controls-empty.json" "$TMP/surface-x.json" >/dev/null 2>"$TMP/err1.txt"; then
  fail "surface generator must refuse when no node profile enabled"
fi
grep -q 'ERROR_SECURITY_SURFACE_NO_NODE_PROFILE' "$TMP/err1.txt" || fail "no-profile refusal tag missing"

# ---- fail closed：输入 JSON 非法 ----
echo 'garbage' > "$TMP/in-bad.json"
if bash "$SURFACE" "$D" "$TMP/in-bad.json" "$TMP/controls.json" "$TMP/surface-y.json" >/dev/null 2>"$TMP/err2.txt"; then
  fail "surface generator accepted invalid input json"
fi
grep -q 'ERROR_SECURITY_SURFACE_INPUT_INVALID' "$TMP/err2.txt" || fail "invalid-input tag missing"

echo "PASS: security surface contract"
