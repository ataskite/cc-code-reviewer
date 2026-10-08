#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG="$ROOT_DIR/references/security/catalog/node-security-controls.json"
TEMP_DIR="$(mktemp -d /tmp/cc-proxy-auth-contract.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Runtime invariants, not model recall: retain controls despite absent keywords.
for case_key in host-routing/renamed-wrapped host-routing/secure proxy-capability/secure jwt-validation/secure proxy-trust/topology-unproven; do
  fixture="$ROOT_DIR/tests/evals/node-security/$case_key"
  slug="$(printf '%s' "$case_key" | tr / -)"
  case_dir="$TEMP_DIR/$slug"
  mkdir -p "$case_dir"
  bash "$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh" "$fixture" > "$case_dir/manifest" 2>/dev/null
  bash "$ROOT_DIR/scripts/core/prepare-review-input.sh" "$fixture" frontend full 0 "$case_dir/manifest" "$case_dir/input.json" >/dev/null
  bash "$ROOT_DIR/scripts/core/resolve-security-controls.sh" "$fixture" node "$case_dir/input.json" "$case_dir/controls.json" >/dev/null 2>/dev/null
  bash "$ROOT_DIR/scripts/languages/frontend/prepare-security-surface.sh" "$fixture" "$case_dir/input.json" "$case_dir/controls.json" "$case_dir/surface.json" >/dev/null 2>/dev/null
  perl -MJSON::PP -0777 -e '
    my $d = decode_json(<>);
    my %ids = map { $_->{id} => 1 } @{$d->{controls}};
    die "stand-alone API lost a proxy/auth control\n" if grep { !$ids{$_} }
      qw(CCR-NODE-HOSTROUTE-001 CCR-NODE-PROXYCAP-001 CCR-NODE-JWTAUTH-001 CCR-NODE-PROXYTRUST-001);
    die "wrong API count\n" unless @{$d->{controls}} == 15;
  ' "$case_dir/controls.json"
  cp "$case_dir/surface.json" "$case_dir/first.json"
  bash "$ROOT_DIR/scripts/languages/frontend/prepare-security-surface.sh" "$fixture" "$case_dir/input.json" "$case_dir/controls.json" "$case_dir/surface.json" >/dev/null 2>/dev/null
  cmp "$case_dir/first.json" "$case_dir/surface.json"
  perl -MJSON::PP -0777 -e '
    my $d = decode_json(<>);
    for my $k (qw(entries identity_sources request_sources sensitive_sinks outbound_clients config_signals)) {
      for my $r (@{$d->{$k} // []}) {
        die "surface must not declare a finding\n" if exists($r->{severity}) || exists($r->{finding}) || exists($r->{status});
      }
    }
  ' "$case_dir/surface.json"
done

# Candidates also exist on positive code, never a vuln classification.
perl -MJSON::PP -0777 -e '
  my $d=decode_json(<>); my %k=map { $_->{kind}=>1 } @{$d->{config_signals}};
  die "routing identity candidate missing\n" unless $k{"routing-identity"};
' "$TEMP_DIR/host-routing-secure/surface.json"
perl -MJSON::PP -0777 -e '
  my $d=decode_json(<>); my %k=map { $_->{kind}=>1 } @{$d->{config_signals}};
  die "JWT options candidate missing\n" unless $k{"jwt-verification-options"};
' "$TEMP_DIR/jwt-validation-secure/surface.json"
perl -MJSON::PP -0777 -e '
  my $d=decode_json(<>); my %k=map { $_->{kind}=>1 } @{$d->{config_signals}};
  die "proxy trust candidate missing\n" unless $k{"proxy-trust"};
' "$TEMP_DIR/proxy-trust-topology-unproven/surface.json"

# Synthetic ledger tests formatting only, not review behavior.
perl -MJSON::PP -e '
  sub load { open my $f,"<",$_[0] or die; local $/; decode_json(<$f>) }
  my ($catalog,$controls,$report)=@ARGV;
  my $cat=load($catalog); my $ctl=load($controls);
  my %by=map { $_->{id} => $_ } @{$cat->{controls}};
  open my $f,">:raw",$report or die;
  print $f "## 🛡️ Security 控制覆盖\n\n- 适用控制：15\n- 已发现问题：0\n- 已检查无发现：15\n- 外部证据缺失：0\n- 静态不可验证：0\n- 不适用：1\n- 对账：N = A + B + C + D\n\n| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |\n|---|---|---|---|---|---|\n";
  for my $c (@{$ctl->{controls}}) {
    my $v=$by{$c->{id}}; my $s=$v->{standards};
    my @m=(@{$s->{owasp_top10}//[]},@{$s->{owasp_api_top10}//[]},@{$s->{asvs}//[]},@{$s->{cwe}//[]});
    print $f "| $c->{id} | gate fixture | ".join(" / ",@m)." | $v->{detectability}{primary} | checked_no_finding | synthetic gate test only |\n";
  }
' "$CATALOG" "$TEMP_DIR/host-routing-secure/controls.json" "$TEMP_DIR/ledger.md"
bash "$ROOT_DIR/scripts/core/validate-security-report.sh" "$TEMP_DIR/ledger.md" "$TEMP_DIR/host-routing-secure/controls.json" >/dev/null
for id in HOSTROUTE PROXYCAP JWTAUTH PROXYTRUST; do
  perl -ne 'print unless /^\| CCR-NODE-'"$id"'-001 /' "$TEMP_DIR/ledger.md" > "$TEMP_DIR/missing.md"
  if bash "$ROOT_DIR/scripts/core/validate-security-report.sh" "$TEMP_DIR/missing.md" "$TEMP_DIR/host-routing-secure/controls.json" >/dev/null 2>"$TEMP_DIR/error"; then
    echo "missing $id row wrongly accepted" >&2; exit 1
  fi
  rg -q 'ERROR_SECURITY_REPORT_ROW_MISSING' "$TEMP_DIR/error"
done
# The new evals must not turn missing deployment evidence into a secure PASS.
# This artificial report exercises comparator strictness, not model recall.
perl -0pe 's/已检查无发现：15/已检查无发现：14/; s/外部证据缺失：0/外部证据缺失：1/;
  s/(\| CCR-NODE-JWTAUTH-001[^\n]*\| semantic \| )checked_no_finding/$1external_evidence_missing/' \
  "$TEMP_DIR/ledger.md" > "$TEMP_DIR/uncertain.md"
printf '%s\n' '[{"case":"strict/status","strict_control_status":true,"expected_findings":[],"forbidden_findings":["CCR-NODE-JWTAUTH-001"],"expected_control_status":{"CCR-NODE-JWTAUTH-001":"checked_no_finding"}}]' > "$TEMP_DIR/strict.json"
if perl "$ROOT_DIR/tests/evals/node-security/compare-eval-report.pl" "$TEMP_DIR/uncertain.md" \
    "$TEMP_DIR/strict.json" strict/status --controls "$TEMP_DIR/host-routing-secure/controls.json" > "$TEMP_DIR/verdict"; then
  echo 'uncertain evidence wrongly passed as checked-no-finding' >&2; exit 1
fi
rg -q '"report_valid":1' "$TEMP_DIR/verdict"
rg -q '"status_drift":\{"CCR-NODE-JWTAUTH-001"' "$TEMP_DIR/verdict"
echo 'PASS: proxy/auth controls, deterministic navigation and mandatory rows (not model recall)'
