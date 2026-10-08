#!/bin/bash
set -euo pipefail

# resolve-security-controls.sh 契约：
# - 纯浏览器 React：不启用 Node profile（所有控制排除）
# - Express Node API：启用 node-api
# - Vue + 根级 BFF：启用 node-bff（含 node-api）
# - MQ worker：启用 node-worker
# - 同输入两次运行字节一致；输出控制全部来自 catalog 且无重复
# - 输入 JSON 非法 / 输出目录不存在 / catalog 被篡改 → fail closed
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESOLVER="$ROOT_DIR/scripts/core/resolve-security-controls.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec-resolve.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL(resolve): $*" >&2; exit 1; }

# 由文件列表生成最小 review-input.json（绝对路径 + selected=true）
make_review_input() { # <out.json> <language> <file...>
  local out="$1" lang="$2"; shift 2
  perl -MJSON::PP -e '
    my ($out, $lang, @files) = @ARGV;
    my @items = map { +{ path => $_, change => "added", old_path => "", selected => "true", exclude_reason => "", insertions => 1, deletions => 0, fingerprint => "" } } @files;
    my $d = { schema_version => 1, language_id => $lang, items => \@items };
    open my $fh, ">", $out or die; print {$fh} JSON::PP->new->canonical->utf8->encode($d), "\n"; close $fh;
  ' "$out" "$lang" "$@"
}

# ---- fixture 1：纯浏览器 React（无任何服务端信号）----
D1="$TMP/pure-react"; mkdir -p "$D1/src"
cat > "$D1/package.json" <<'JSON'
{"name":"pure-react","dependencies":{"react":"^18.2.0"}}
JSON
printf 'import { useState } from "react";\nexport function App() { return <div/>; }\n' > "$D1/src/App.tsx"
make_review_input "$TMP/in1.json" frontend "$D1/package.json" "$D1/src/App.tsx"
OUT1="$("$RESOLVER" "$D1" frontend-react "$TMP/in1.json" "$TMP/out1.json" || fail "resolver failed on pure react")"
printf '%s\n' "$OUT1" | grep -q 'SECURITY_PROFILES= CONTROLS=0 ' || fail "pure react must enable no node profile: $OUT1"
grep -q '"security_profile":\[\]' "$TMP/out1.json" || fail "pure react profiles must be empty array"
grep -q 'CCR-NODE-BFFHEADER-001' "$TMP/out1.json" || fail "excluded controls must still be disclosed"

# ---- fixture 2：Express Node API（mongoose，无外发客户端）----
D2="$TMP/express-api"; mkdir -p "$D2"
cat > "$D2/package.json" <<'JSON'
{"name":"express-api","main":"server.js","dependencies":{"express":"^4.18.0","mongoose":"^7.0.0"}}
JSON
cat > "$D2/server.js" <<'JS'
const express = require('express');
const mongoose = require('mongoose');
const app = express();
app.post('/orders', function (req, res) {
  db.collection('orders').findOne({ userId: req.body.userId });
});
app.listen(3000);
JS
make_review_input "$TMP/in2.json" frontend "$D2/package.json" "$D2/server.js"
OUT2="$(bash "$RESOLVER" "$D2" node "$TMP/in2.json" "$TMP/out2.json" || fail "resolver failed on express api")"
printf '%s\n' "$OUT2" | grep -q 'SECURITY_PROFILES=node-api CONTROLS=15 ' || fail "express api must enable node-api with all 15 profile controls: $OUT2"
ids2="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f> }); print join("\n", map { $_->{id} } @{$d->{controls}})' "$TMP/out2.json")"
printf '%s\n' "$ids2" | grep -qx 'CCR-NODE-NOSQL-001' || fail "nosql control must be applicable for mongoose fixture"
printf '%s\n' "$ids2" | grep -qx 'CCR-NODE-SESSION-001' || fail "session control must stay applicable (profile-default; signals never exclude)"
basis2="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f>}); my ($c) = grep { $_->{id} eq "CCR-NODE-NOSQL-001" } @{$d->{controls}}; print $c->{basis}' "$TMP/out2.json")"
[ "$basis2" = "signal-confirmed" ] || fail "nosql basis must be signal-confirmed"
basis2b="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f>}); my ($c) = grep { $_->{id} eq "CCR-NODE-SESSION-001" } @{$d->{controls}}; print $c->{basis}' "$TMP/out2.json")"
[ "$basis2b" = "profile-default" ] || fail "session basis must be profile-default"
excl2="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f> }); print join("\n", map { $_->{id} } @{$d->{excluded_controls}})' "$TMP/out2.json")"
printf '%s\n' "$excl2" | grep -qx 'CCR-NODE-BFFHEADER-001' || fail "pure node api excludes bff-only control (profile-level)"
! printf '%s\n' "$excl2" | grep -q 'CCR-NODE-SSRF-001' || fail "signals must never exclude a control from an enabled profile"

# ---- fixture 3：Vue + 根级 BFF（express + axios 头透传）----
D3="$TMP/vue-bff"; mkdir -p "$D3/src/views"
cat > "$D3/package.json" <<'JSON'
{"name":"vue-bff","main":"app.js","dependencies":{"vue":"^2.6.10","express":"^4.16.0","axios":"^0.27.0"}}
JSON
echo '<template><div/></template>' > "$D3/src/views/Home.vue"
cat > "$D3/app.js" <<'JS'
const express = require('express');
const axios = require('axios');
const app = express();
app.post('/gateway', function (req, res) {
  axios.post('http://upstream.internal/api', req.body, { headers: req.headers });
});
app.listen(8080);
JS
make_review_input "$TMP/in3.json" frontend "$D3/package.json" "$D3/src/views/Home.vue" "$D3/app.js"
OUT3="$("$RESOLVER" "$D3" frontend-vue2 "$TMP/in3.json" "$TMP/out3.json" || fail "resolver failed on vue bff")"
printf '%s\n' "$OUT3" | grep -q 'SECURITY_PROFILES=node-api,node-bff CONTROLS=16 ' || fail "vue bff must enable node-api+node-bff with all 16 controls: $OUT3"
grep -q ^CCR-NODE-BFFHEADER-001$ <(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $fh, q[<], $ARGV[0] or die; <$fh> }); print join("\n", map { $_->{id} } @{$d->{controls}})' "$TMP/out3.json") \
  || fail "bffheader control must be applicable for vue bff fixture"

# ---- fixture 4：MQ worker（bullmq 消费 + child_process）----
D4="$TMP/mq-worker"; mkdir -p "$D4"
cat > "$D4/package.json" <<'JSON'
{"name":"mq-worker","dependencies":{"bullmq":"^4.0.0"}}
JSON
cat > "$D4/worker.js" <<'JS'
const { Queue, Worker } = require('bullmq');
const { exec } = require('child_process');
new Worker('jobs', async (job) => {
  exec(`convert ${job.data.payload.file}`);
});
JS
make_review_input "$TMP/in4.json" frontend "$D4/package.json" "$D4/worker.js"
OUT4="$("$RESOLVER" "$D4" node "$TMP/in4.json" "$TMP/out4.json" || fail "resolver failed on mq worker")"
printf '%s\n' "$OUT4" | grep -q 'SECURITY_PROFILES=node-api,node-worker CONTROLS=15 ' || fail "mq worker must enable node-worker with node-api union: $OUT4"
grep -q ^CCR-NODE-CMD-001$ <(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $fh, q[<], $ARGV[0] or die; <$fh> }); print join("\n", map { $_->{id} } @{$d->{controls}})' "$TMP/out4.json") \
  || fail "cmd control must be applicable for worker fixture"

# ---- 确定性：同输入两次运行字节一致 ----
"$RESOLVER" "$D3" frontend-vue2 "$TMP/in3.json" "$TMP/out3b.json" >/dev/null 2>&1
cmp -s "$TMP/out3.json" "$TMP/out3b.json" || fail "resolver output not byte-stable across runs"

# ---- 输出控制全部来自 catalog 且无重复 ----
perl -MJSON::PP -0777 -e '
  my $out = decode_json(do { local $/; open my $fh, "<", $ARGV[0] or die; <$fh> });
  my %dup; my @bad;
  for my $c (@{$out->{controls}}) {
    $dup{$c->{id}}++ and push @bad, $c->{id};
    push @bad, $c->{id} unless $c->{id} =~ /^CCR-NODE-[A-Z0-9]+-[0-9]{3}$/;
    push @bad, "$c->{id}:applicability" unless ($c->{applicability} // "") eq "applicable";
  }
  die "BAD_CONTROLS=@bad\n" if @bad;
  die "profile order must be node-api,node-bff,node-worker subset\n"
    unless join(",", @{$out->{security_profile}}) =~ /^(node-api)?(,node-bff)?(,node-worker)?$/;
' "$TMP/out3.json" || fail "output controls violate catalog membership/duplication contract"

# ---- fail closed：输入 JSON 非法 ----
echo 'not-json' > "$TMP/bad.json"
if "$RESOLVER" "$D2" node "$TMP/bad.json" "$TMP/bad-out.json" >/dev/null 2>"$TMP/err1.txt"; then
  fail "resolver accepted invalid input json"
fi
grep -q 'ERROR_SECURITY_RESOLVE_INPUT_INVALID' "$TMP/err1.txt" || fail "invalid input must emit ERROR_SECURITY_RESOLVE_INPUT_INVALID"

# ---- fail closed：输出目录不存在 ----
if "$RESOLVER" "$D2" node "$TMP/in2.json" "$TMP/no-such-dir/out.json" >/dev/null 2>"$TMP/err2.txt"; then
  fail "resolver accepted missing output dir"
fi
grep -q 'ERROR_SECURITY_RESOLVE_OUTPUT_DIR' "$TMP/err2.txt" || fail "missing output dir must emit ERROR_SECURITY_RESOLVE_OUTPUT_DIR"

# ---- fail closed：selected 路径越出 PROJECT_DIR ----
make_review_input "$TMP/in-escape.json" frontend "$D2/server.js" "/etc/hosts"
if "$RESOLVER" "$D2" node "$TMP/in-escape.json" "$TMP/escape-out.json" >/dev/null 2>"$TMP/err3.txt"; then
  fail "resolver accepted selected path outside project dir"
fi
grep -q 'ERROR_SECURITY_RESOLVE_INPUT_SCOPE' "$TMP/err3.txt" || fail "outside path must emit ERROR_SECURITY_RESOLVE_INPUT_SCOPE"

# ---- 运行时 fail closed：本地上游任一快照字节与 manifest 不符时拒绝解析 ----
TAMPER_BASE="$TMP/plugin/references/security"
mkdir -p "$TAMPER_BASE/catalog" "$TAMPER_BASE/upstream"
cp -R "$ROOT_DIR/references/security/catalog/." "$TAMPER_BASE/catalog/"
cp -R "$ROOT_DIR/references/security/upstream/." "$TAMPER_BASE/upstream/"
CS_FILE="$(find "$TAMPER_BASE/upstream/nodejs-cheat-sheet" -type f -name Nodejs_Security_Cheat_Sheet.md -print -quit)"
printf '\n<!-- tampered bytes -->\n' >> "$CS_FILE"
if CC_CODE_REVIEWER_SECURITY_CATALOG="$TAMPER_BASE/catalog/node-security-controls.json" \
  "$RESOLVER" "$D3" frontend-vue2 "$TMP/in3.json" "$TMP/tampered-upstream-out.json" >/dev/null 2>"$TMP/err-upstream.txt"; then
  fail "resolver accepted an upstream snapshot whose bytes differ from manifest hashes"
fi
grep -q 'ERROR_SECURITY_UPSTREAM_' "$TMP/err-upstream.txt" || fail "tampered upstream must surface ERROR_SECURITY_UPSTREAM_*"

# ---- fail closed：catalog 被篡改 ----
# perl 必须读 ARGV 文件而非 <STDIN>：本测试作为 run_all.sh 循环体执行时，宿主
# 循环经 stdin 向后传 find 文件流，读 <STDIN> 会吃掉剩余清单使套件静默截断、
# 假报全绿（实际事故：其后的 31 个测试被跳过）。
BAD_CAT="$TMP/bad-catalog.json"
perl -MJSON::PP -0777 -e 'my $t = do { local $/; open my $f, q[<], $ARGV[0] or die; <$f> }; $t =~ s/"catalog_id":\s*"[^"]*"/"catalog_id":"x"/; print $t' \
  "$ROOT_DIR/references/security/catalog/node-security-controls.json" > "$BAD_CAT"
if CC_CODE_REVIEWER_SECURITY_CATALOG="$BAD_CAT" "$RESOLVER" "$D2" node "$TMP/in2.json" "$TMP/badcat-out.json" >/dev/null 2>"$TMP/err4.txt"; then
  fail "resolver accepted tampered catalog"
fi
grep -q 'ERROR_SECURITY_CATALOG_INVALID' "$TMP/err4.txt" || fail "tampered catalog must surface ERROR_SECURITY_CATALOG_INVALID"

echo "PASS: security resolve-controls contract"
