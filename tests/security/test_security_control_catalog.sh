#!/bin/bash
set -euo pipefail

# Security Control Catalog 契约：
#   references/security/catalog/node-security-controls.json 是 Node/BFF 安全控制的
#   唯一提交态事实来源（稳定 CCR-NODE-* ID、封闭枚举、标准映射）。
#   每条 ASVS/Top10/API Top10 映射 ID 必须能在本地 upstream 快照中找到——
#   不得凭记忆编造占位映射。本测试只读本地文件，不访问网络。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CATALOG_DIR="$ROOT_DIR/references/security/catalog"
UPSTREAM="$ROOT_DIR/references/security/upstream"
VALIDATOR="$ROOT_DIR/scripts/core/validate-security-control-catalog.sh"

fail() { echo "FAIL(catalog): $*" >&2; exit 1; }

[ -f "$CATALOG_DIR/node-security-controls.json" ] || fail "missing node-security-controls.json"
[ -f "$CATALOG_DIR/security-control.schema.json" ] || fail "missing security-control.schema.json"
[ -f "$CATALOG_DIR/profiles/node-api.json" ] || fail "missing profiles/node-api.json"
[ -f "$CATALOG_DIR/profiles/node-bff.json" ] || fail "missing profiles/node-bff.json"
[ -f "$CATALOG_DIR/profiles/node-worker.json" ] || fail "missing profiles/node-worker.json"
[ -f "$ROOT_DIR/references/security/control-catalog.md" ] || fail "missing control-catalog.md"
[ -f "$VALIDATOR" ] || fail "missing validate-security-control-catalog.sh"

# ---- 校验脚本 happy path：stdout 单行稳定契约 ----
OUT="$(bash "$VALIDATOR" 2>/dev/null)" || fail "validator exited nonzero: $OUT"
printf '%s\n' "$OUT" | grep -Eq '^SECURITY_CATALOG_OK=[0-9]+\.[0-9]+\.[0-9]+ CONTROLS=[0-9]+ ASVS=[0-9]+ TOP10=[0-9]+ API_TOP10=[0-9]+$' \
  || fail "validator stdout contract violated: $OUT"

# ---- 校验脚本 fail-closed：目录被篡改时 exit 1 + ERROR_SECURITY_CATALOG_* ----
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec-catalog.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BAD_CAT="$TMP/node-security-controls.json"
perl -MJSON::PP -0777 -e '
  local $/; my $t = <STDIN>;
  $t =~ s/"catalog_id"\s*:\s*"[^"]*"/"catalog_id": "tampered"/;
  print $t;
' "$CATALOG_DIR/node-security-controls.json" > "$BAD_CAT"
if bash "$VALIDATOR" "$BAD_CAT" >/dev/null 2>"$TMP/err.txt"; then
  fail "validator accepted a tampered catalog"
fi
grep -q 'ERROR_SECURITY_CATALOG_' "$TMP/err.txt" || fail "validator stderr lacks ERROR_SECURITY_CATALOG_* tag"

# ---- 结构、枚举、映射存在性（单进程 Perl）----
. "$ROOT_DIR/scripts/core/lib/common.sh"
perl -MJSON::PP -e '
  use strict; use warnings;
  my ($cat_dir, $upstream, $sha_manifest_actual, $root_dir) = @ARGV;
  sub slurp { my ($p) = @_; open my $fh, "<:raw", $p or die "ERROR_CATALOG_READ=$p\n"; local $/; my $d = <$fh>; close $fh; return $d; }
  sub failx { die "ERROR_CATALOG_CONTRACT=@_\n"; }
  sub load_json { my ($p) = @_; my $d = eval { decode_json(slurp($p)) }; failx("invalid JSON: $p") if $@ || !defined $d; return $d; }
  sub no_dup { my ($a, $w) = @_; my %s; for (@$a) { failx("duplicate entry in $w: $_") if $s{$_}++; } }

  my $cat = load_json("$cat_dir/node-security-controls.json");
  failx("schema_version must be 1") unless ($cat->{schema_version} // 0) == 1;
  failx("catalog_id must be cc-code-reviewer-node-security") unless ($cat->{catalog_id} // "") eq "cc-code-reviewer-node-security";
  failx("catalog_version must be semver") unless ($cat->{catalog_version} // "") =~ /^\d+\.\d+\.\d+$/;
  failx("upstream_manifest_sha256 must equal manifest bytes hash") unless ($cat->{upstream_manifest_sha256} // "") eq $sha_manifest_actual;
  my $controls = $cat->{controls};
  failx("controls must be non-empty array") unless ref($controls) eq "ARRAY" && @$controls;

  my %valid_cat = map { $_ => 1 } qw(identity authorization injection external-resource file data-secret business-abuse logging-exception configuration-supply-chain);
  my %valid_det = map { $_ => 1 } qw(pattern taint semantic config dependency runtime);
  my %valid_sev = map { $_ => 1 } qw(P0 P1 P2 P3 none);
  my %valid_prof = map { $_ => 1 } qw(node-api node-bff node-worker);
  my @first_batch = qw(
    CCR-NODE-BFFHEADER-001 CCR-NODE-IDENTITY-001 CCR-NODE-SESSION-001 CCR-NODE-SSRF-001
    CCR-NODE-CMD-001 CCR-NODE-PATH-001 CCR-NODE-PROTO-001 CCR-NODE-NOSQL-001
    CCR-NODE-DESER-001 CCR-NODE-BOLA-001 CCR-NODE-BFLA-001 CCR-NODE-CSRF-001
  );
  my %ids;
  for my $c (@$controls) {
    my $id = $c->{id} // "";
    failx("control id format invalid: $id") unless $id =~ /^CCR-NODE-[A-Z0-9]+-[0-9]{3}$/;
    failx("duplicate control id: $id") if $ids{$id}++;
    for my $k (qw(title_zh category profiles applicability standards detectability sources sinks required_controls required_evidence severity_candidate description_zh remediation_zh)) {
      failx("control $id lacks required field $k") unless exists $c->{$k};
    }
    failx("control $id category invalid: " . ($c->{category} // "")) unless $valid_cat{ $c->{category} };
    failx("control $id detectability.primary invalid") unless $valid_det{ $c->{detectability}{primary} // "" };
    failx("control $id severity_candidate invalid") unless $valid_sev{ $c->{severity_candidate} // "" };
    failx("control $id profiles empty") unless ref($c->{profiles}) eq "ARRAY" && @{ $c->{profiles} };
    no_dup($c->{profiles}, "profiles of $id");
    failx("control $id unknown profile: @{ $c->{profiles} }") if grep { !$valid_prof{$_} } @{ $c->{profiles} };
    no_dup($_, $_ . " of $id") for ($c->{sources}, $c->{sinks}, $c->{required_controls}, $c->{required_evidence});
    my $st = $c->{standards};
    failx("control $id standards missing subkeys") unless ref($st) eq "HASH" && defined $st->{owasp_top10} && defined $st->{owasp_api_top10} && defined $st->{asvs} && defined $st->{cwe};
    no_dup($_, "$_ of $id") for ($st->{owasp_top10}, $st->{owasp_api_top10}, $st->{asvs}, $st->{cwe});
    failx("control $id cwe format invalid: @{ $st->{cwe} }") if grep { !/^CWE-\d+$/ } @{ $st->{cwe} };
    no_dup($c->{applicability}{review_signals} // [], "signals of $id");
  }
  failx("catalog must contain >= 12 controls") unless @$controls >= 12;
  for my $fb (@first_batch) {
    failx("first-batch control missing: $fb") unless $ids{$fb};
  }

  # profiles 只引用 control ID，不复制控制内容。
  my %prof_ids;
  for my $p (qw(node-api node-bff node-worker)) {
    my $pd = load_json("$cat_dir/profiles/$p.json");
    failx("profile $p must be object") unless ref($pd) eq "HASH";
    failx("profile $p schema_version must be 1") unless ($pd->{schema_version} // 0) == 1;
    my $list = $pd->{controls} // [];
    failx("profile $p controls must be non-empty") unless @$list;
    no_dup($list, "profile $p");
    for my $cid (@$list) {
      failx("profile $p references unknown control: $cid") unless $ids{$cid};
    }
    $prof_ids{$p} = { map { $_ => 1 } @$list };
  }
  for my $c (@$controls) {
    for my $p (@{ $c->{profiles} }) {
      failx("control $c->{id} declares profile $p but profile file does not list it") unless $prof_ids{$p}{ $c->{id} };
    }
  }

  # 标准映射存在性：ASVS Shortcode / Top10 ID / API Top10 ID 必须能在本地快照找到。
  my $asvs = load_json("$upstream/asvs/5.0.0/OWASP_Application_Security_Verification_Standard_5.0.0_en.json");
  my %asvs_ids;
  my %asvs_description;
  my $walk; $walk = sub {
    my ($n) = @_;
    return unless ref($n) eq "HASH";
    if (defined $n->{Shortcode}) {
      $asvs_ids{ $n->{Shortcode} } = 1;
      $asvs_description{ $n->{Shortcode} } = $n->{Description} // "";
    }
    $walk->($_) for @{ $n->{Items} // [] };
  };
  $walk->($_) for @{ $asvs->{Requirements} // [] };
  my ($ssrf) = grep { $_->{id} eq "CCR-NODE-SSRF-001" } @$controls;
  join(",", @{ $ssrf->{standards}{asvs} || [] }) eq "v5.0.0-V1.3.6"
    or failx("SSRF control must map to its semantically verified ASVS SSRF requirement V1.3.6 only");
  $asvs_description{"V1.3.6"} =~ /Server-side Request Forgery/i
    or failx("ASVS V1.3.6 no longer identifies SSRF; review the control mapping");
  for my $c (@$controls) {
    for my $a (@{ $c->{standards}{asvs} }) {
      failx("control $c->{id} asvs id must carry v5.0.0- prefix: $a") unless $a =~ /^v5\.0\.0-/;
      my $sc = $a;
      $sc =~ s/^v5\.0\.0-//;
      failx("control $c->{id} asvs id not found in local ASVS snapshot: $sc") unless $asvs_ids{$sc};
    }
    for my $t (@{ $c->{standards}{owasp_top10} }) {
      failx("control $c->{id} top10 id format: $t") unless $t =~ /^A(\d{2}):2025$/;
      my $p = "$upstream/top10/2025/" . sprintf("A%02d", $1) . ".md";
      failx("control $c->{id} top10 id not found in snapshot: $t") unless -f $p && index(slurp($p), $t) >= 0;
    }
    for my $t (@{ $c->{standards}{owasp_api_top10} }) {
      failx("control $c->{id} api id format: $t") unless $t =~ /^API(\d{1,2}):2023$/;
      my $p = "$upstream/api-top10/2023/API$1.md";
      failx("control $c->{id} api id not found in snapshot: $t") unless -f $p && index(slurp($p), $t) >= 0;
    }
  }

  # schema 文件必须是合法 JSON 对象（说明用途，真正 fail-closed 由校验脚本承担）。
  my $schema = load_json("$cat_dir/security-control.schema.json");
  failx("schema must be object") unless ref($schema) eq "HASH";

  # 人类可读说明必须登记第二批「仅设计登记、未实现」候选，禁止假装已实现。
  my $doc = slurp("$root_dir/references/security/control-catalog.md");
  for my $needle ("第二批", "未实现") {
    failx("control-catalog.md lacks marker: $needle") unless index($doc, $needle) >= 0;
  }
' "$CATALOG_DIR" "$UPSTREAM" "$(sha256_file "$UPSTREAM/manifest.json")" "$ROOT_DIR" || fail "catalog contract violated (see ERROR_CATALOG_* above)"

echo "PASS: security control catalog contract"
