#!/bin/bash
set -euo pipefail

# Security 恢复门禁契约（plan-file-batches.sh 冻结 + validate-resume-input.sh --security）：
# - frontend+security 计划在 RUN_DIR 冻结 security-controls/security-surface，plan.json
#   记录 controls/surface/catalog/upstream 六元组路径与字节哈希
# - 正常 run → GATE_OK exit 0；controls/surface 篡改、catalog/upstream 哈希漂移、
#   路径越出 RUN_DIR、legacy security run 缺字段 → exit 5 SECURITY_SNAPSHOT_CHANGED
# - 非 Security 计划传 --security → 明确跳过（不适用）且保持 exit 0
# - 原有 exit 0/1/2/3/4 契约不回归
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT_DIR/scripts/core/validate-resume-input.sh"
PLANNER="$ROOT_DIR/scripts/core/plan-file-batches.sh"
COLLECTOR="$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL(resume-gate): $*" >&2; exit 1; }

# ---- fixture：Vue + 根级 express BFF（含 Node profile，会生成 surface）----
D="$TMP/vue-bff"; mkdir -p "$D/src/views"
cat > "$D/package.json" <<'JSON'
{"name":"gate-bff","main":"app.js","dependencies":{"vue":"^2.6.10","express":"^4.16.0","axios":"^0.27.0"}}
JSON
echo '<template><div/></template>' > "$D/src/views/Home.vue"
cat > "$D/app.js" <<'JS'
const express = require('express');
const axios = require('axios');
const app = express();
app.post('/gateway', function (req, res) {
  axios.post('http://upstream.internal/api', req.body, { headers: req.headers });
});
app.listen(8080);
JS
D="$(cd "$D" && pwd -P)"

MANIFEST="$TMP/manifest.txt"
bash "$COLLECTOR" "$D" > "$MANIFEST" 2>/dev/null

OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260921-010000 \
       bash "$PLANNER" "$D" "security" "main" "frontend" "$MANIFEST")" || fail "planner failed: $OUT"
RUN_DIR="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || fail "planner did not emit RUN_DIR"

# ---- plan.json 冻结六元组 + RUN_DIR 冻结文件 ----
for field in security_controls_path security_controls_sha256 security_surface_path \
             security_surface_sha256 security_catalog_path security_catalog_sha256 \
             security_upstream_manifest_sha256; do
  grep -q "\"$field\"" "$RUN_DIR/plan.json" || fail "plan.json lacks $field"
done
[ -f "$RUN_DIR/security-controls.json" ] || fail "frozen controls missing in RUN_DIR"
[ -f "$RUN_DIR/security-surface.json" ] || fail "frozen surface missing in RUN_DIR"
CONTROLS_SHA_RECORDED="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $f,"<",$ARGV[0] or die; <$f> }); print $d->{security_controls_sha256}' "$RUN_DIR/plan.json")"
[ "$(shasum -a 256 "$RUN_DIR/security-controls.json" | awk '{print $1}')" = "$CONTROLS_SHA_RECORDED" ] \
  || fail "frozen controls sha mismatch vs plan.json"

# ---- happy path：GATE_OK ----
GATE_OUT="$(bash "$GATE" "$RUN_DIR" "$D" --rules --security)" || fail "gate rejected a fresh security run: $GATE_OUT"
printf '%s\n' "$GATE_OUT" | grep -q '^GATE_OK=' || fail "gate stdout contract violated: $GATE_OUT"

# ---- controls 篡改 → exit 5 ----
cp "$RUN_DIR/security-controls.json" "$TMP/controls.bak"
printf '\n' >> "$RUN_DIR/security-controls.json"
if bash "$GATE" "$RUN_DIR" "$D" --rules --security >/dev/null 2>"$TMP/e1.txt"; then
  fail "tampered controls must fail the gate"
fi
grep -q 'SECURITY_SNAPSHOT_CHANGED' "$TMP/e1.txt" || fail "tampered controls tag missing"
cp "$TMP/controls.bak" "$RUN_DIR/security-controls.json"

# ---- surface 篡改 → exit 5 ----
cp "$RUN_DIR/security-surface.json" "$TMP/surface.bak"
printf ' ' >> "$RUN_DIR/security-surface.json"
if bash "$GATE" "$RUN_DIR" "$D" --rules --security >/dev/null 2>"$TMP/e2.txt"; then
  fail "tampered surface must fail the gate"
fi
cp "$TMP/surface.bak" "$RUN_DIR/security-surface.json"

# ---- catalog 哈希漂移（改 plan 记录值模拟插件基线变化）→ exit 5 ----
perl -MJSON::PP -0777 -e '
  my ($p) = @ARGV; local $/; open my $f, "<", $p or die; my $t = <$f>; close $f;
  my $d = decode_json($t); $d->{security_catalog_sha256} = "0" x 64;
  open my $o, ">", $p or die; print {$o} JSON::PP->new->canonical->pretty->indent_length(2)->encode($d), "\n"; close $o;
' "$RUN_DIR/plan.json"
if bash "$GATE" "$RUN_DIR" "$D" --rules --security >/dev/null 2>"$TMP/e3.txt"; then
  fail "catalog drift must fail the gate"
fi
grep -q 'SECURITY_SNAPSHOT_CHANGED' "$TMP/e3.txt" || fail "catalog drift tag missing"

# ---- upstream manifest 哈希漂移 → exit 5 ----
OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260921-010002 \
       bash "$PLANNER" "$D" "security" "main" "frontend" "$MANIFEST")"
RUN2="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
perl -MJSON::PP -0777 -e '
  my ($p) = @ARGV; local $/; open my $f, "<", $p or die; my $t = <$f>; close $f;
  my $d = decode_json($t); $d->{security_upstream_manifest_sha256} = "f" x 64;
  open my $o, ">", $p or die; print {$o} JSON::PP->new->canonical->pretty->indent_length(2)->encode($d), "\n"; close $o;
' "$RUN2/plan.json"
if bash "$GATE" "$RUN2" "$D" --rules --security >/dev/null 2>"$TMP/e4.txt"; then
  fail "upstream drift must fail the gate"
fi

# ---- 冻结文件路径越出 RUN_DIR → exit 5 ----
perl -MJSON::PP -0777 -e '
  my ($p) = @ARGV; local $/; open my $f, "<", $p or die; my $t = <$f>; close $f;
  my $d = decode_json($t); $d->{security_controls_path} = "/etc/passwd";
  open my $o, ">", $p or die; print {$o} JSON::PP->new->canonical->pretty->indent_length(2)->encode($d), "\n"; close $o;
' "$RUN2/plan.json"
if bash "$GATE" "$RUN2" "$D" --rules --security >/dev/null 2>"$TMP/e5.txt"; then
  fail "controls path escape must fail the gate"
fi

# ---- legacy security run（缺 security 字段）→ exit 5 ----
perl -MJSON::PP -0777 -e '
  my ($p) = @ARGV; local $/; open my $f, "<", $p or die; my $t = <$f>; close $f;
  my $d = decode_json($t);
  delete @$d{qw(security_controls_path security_controls_sha256 security_surface_path security_surface_sha256 security_catalog_path security_catalog_sha256 security_upstream_manifest_sha256)};
  open my $o, ">", $p or die; print {$o} JSON::PP->new->canonical->pretty->indent_length(2)->encode($d), "\n"; close $o;
' "$RUN2/plan.json"
if bash "$GATE" "$RUN2" "$D" --rules --security >/dev/null 2>"$TMP/e6.txt"; then
  fail "legacy security run must fail closed"
fi
grep -q 'legacy security run lacks security snapshot fields' "$TMP/e6.txt" || fail "legacy detail missing"

# ---- 非 Security 计划 + --security → 明确不适用，仍 GATE_OK ----
OUT="$(CC_CODE_REVIEWER_RUN_TIMESTAMP=20260921-010003 \
       bash "$PLANNER" "$D" "standard" "main" "frontend" "$MANIFEST")"
RUN3="$(printf '%s\n' "$OUT" | sed -n 's/^RUN_DIR=//p')"
grep -q 'security_controls_path' "$RUN3/plan.json" && fail "non-security plan must not carry security fields"
GATE3="$(bash "$GATE" "$RUN3" "$D" --rules --security 2>"$TMP/e7.txt")" || fail "non-security plan + --security must stay GATE_OK"
printf '%s\n' "$GATE3" | grep -q '^GATE_OK=' || fail "non-security gate stdout violated"
grep -q 'SECURITY_SNAPSHOT_SKIPPED' "$TMP/e7.txt" || fail "non-security skip note missing"

# ---- 原有 exit 0/1/2 契约不回归（无 --security 时旧调用完全兼容）----
bash "$GATE" "$RUN_DIR" "$D" --rules >/dev/null || fail "legacy gate call (no --security) regressed"
if bash "$GATE" "$TMP/no-such-dir" "$D" >/dev/null 2>&1; then fail "usage error must exit 1"; fi

echo "PASS: security resume gate contract"
