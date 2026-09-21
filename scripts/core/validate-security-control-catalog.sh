#!/bin/bash
set -euo pipefail

# Security Control Catalog fail-closed 校验器（离线、确定性、零网络）：
#   bash scripts/core/validate-security-control-catalog.sh [显式 catalog JSON 路径]
#
# 契约：
# - 成功 stdout 单行：SECURITY_CATALOG_OK=<catalog_version> CONTROLS=<n> ASVS=<a> TOP10=<t> API_TOP10=<ap>
#   （ASVS/TOP10/API_TOP10 为 catalog 中出现的去重标准映射数）
# - 失败 exit 1，stderr 输出稳定 ERROR_SECURITY_CATALOG_* 标签。
# - 校验内容：catalog 结构与封闭枚举、upstream_manifest_sha256 与本地 upstream/manifest.json
#   字节哈希一致、每条 ASVS/Top10/API Top10 映射 ID 在本地快照中真实存在、profiles 文件
#   与控制声明双向一致、CWE 格式。本脚本只读本地文件。
# - 默认 catalog 路径相对本脚本解析（../.. = 插件根）；显式参数时按该文件所在
#   references/security/catalog/ 布局向上寻找 upstream。

CATALOG_PATH="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"   # sha256_file 三级回退链

if [ -z "$CATALOG_PATH" ]; then
  CATALOG_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)/references/security/catalog/node-security-controls.json"
fi
[ -f "$CATALOG_PATH" ] || { echo "ERROR_SECURITY_CATALOG_NOT_FOUND=$CATALOG_PATH" >&2; exit 1; }
[ -r "$CATALOG_PATH" ] || { echo "ERROR_SECURITY_CATALOG_NOT_READABLE=$CATALOG_PATH" >&2; exit 1; }

# upstream manifest 位于 catalog 同级的 ../upstream/manifest.json（插件标准布局）。
CATALOG_DIR="$(cd "$(dirname "$CATALOG_PATH")" && pwd -P)"
UPSTREAM_MANIFEST="$CATALOG_DIR/../upstream/manifest.json"
if [ ! -r "$UPSTREAM_MANIFEST" ]; then
  UPSTREAM_MANIFEST="$(cd "$SCRIPT_DIR/../.." && pwd)/references/security/upstream/manifest.json"
fi
[ -r "$UPSTREAM_MANIFEST" ] || { echo "ERROR_SECURITY_CATALOG_UPSTREAM_MISSING=$UPSTREAM_MANIFEST" >&2; exit 1; }
UPSTREAM_ROOT="$(cd "$(dirname "$UPSTREAM_MANIFEST")" && pwd -P)"

MANIFEST_SHA="$(sha256_file "$UPSTREAM_MANIFEST")"

perl -MJSON::PP -e '
  use strict; use warnings;
  my ($cat_path, $upstream_root, $manifest_sha) = @ARGV;
  sub slurp { my ($p) = @_; open my $fh, "<:raw", $p or die "ERROR_SECURITY_CATALOG_READ=$p\n"; local $/; my $d = <$fh>; close $fh; return $d; }
  sub failx { die "ERROR_SECURITY_CATALOG_INVALID=@_\n"; }

  my $cat = eval { decode_json(slurp($cat_path)) };
  failx("catalog json parse failed") if $@ || ref($cat) ne "HASH";
  failx("schema_version must be 1") unless ($cat->{schema_version} // 0) == 1;
  failx("catalog_id must be cc-code-reviewer-node-security") unless ($cat->{catalog_id} // "") eq "cc-code-reviewer-node-security";
  failx("catalog_version missing") unless ($cat->{catalog_version} // "") =~ /^\d+\.\d+\.\d+$/;
  failx("upstream_manifest_sha256 mismatch (catalog is not bound to the current upstream snapshot)") unless ($cat->{upstream_manifest_sha256} // "") eq $manifest_sha;
  my $controls = $cat->{controls};
  failx("controls must be non-empty array") unless ref($controls) eq "ARRAY" && @$controls;

  my %cat_set = map { $_ => 1 } qw(identity authorization injection external-resource file data-secret business-abuse logging-exception configuration-supply-chain);
  my %det_set = map { $_ => 1 } qw(pattern taint semantic config dependency runtime);
  my %sev_set = map { $_ => 1 } qw(P0 P1 P2 P3 none);
  my %prof_set = map { $_ => 1 } qw(node-api node-bff node-worker);
  sub no_dup { my ($a, $w) = @_; my %s; for (@$a) { failx("duplicate in $w: $_") if $s{$_}++; } }

  my %ids;
  my (%asvs_all, %t10_all, %api_all);
  for my $c (@$controls) {
    my $id = $c->{id} // "";
    failx("control id format: $id") unless $id =~ /^CCR-NODE-[A-Z0-9]+-[0-9]{3}$/;
    failx("duplicate control id: $id") if $ids{$id}++;
    for my $k (qw(title_zh category profiles applicability standards detectability sources sinks required_controls required_evidence severity_candidate description_zh remediation_zh)) {
      failx("control $id lacks field $k") unless exists $c->{$k};
    }
    failx("control $id category invalid") unless $cat_set{ $c->{category} };
    failx("control $id detectability.primary invalid") unless $det_set{ $c->{detectability}{primary} // "" };
    failx("control $id severity_candidate invalid") unless $sev_set{ $c->{severity_candidate} // "" };
    failx("control $id profiles empty") unless @{ $c->{profiles} };
    no_dup($c->{profiles}, "profiles of $id");
    failx("control $id unknown profile") if grep { !$prof_set{$_} } @{ $c->{profiles} };
    no_dup($_, "array of $id") for ($c->{sources}, $c->{sinks}, $c->{required_controls}, $c->{required_evidence});
    my $st = $c->{standards};
    failx("control $id standards subkeys") unless ref($st) eq "HASH" && defined $st->{owasp_top10} && defined $st->{owasp_api_top10} && defined $st->{asvs} && defined $st->{cwe};
    no_dup($_, "standards of $id") for ($st->{owasp_top10}, $st->{owasp_api_top10}, $st->{asvs}, $st->{cwe});
    failx("control $id cwe format") if grep { !/^CWE-\d+$/ } @{ $st->{cwe} };
    $asvs_all{$_} = 1 for @{ $st->{asvs} };
    $t10_all{$_} = 1 for @{ $st->{owasp_top10} };
    $api_all{$_} = 1 for @{ $st->{owasp_api_top10} };
  }
  failx("catalog must declare at least 12 controls") unless @$controls >= 12;

  # profiles 双向一致
  my $cat_dir = $cat_path; $cat_dir =~ s{/[^/]+$}{};
  for my $p (sort keys %prof_set) {
    my $pp = "$cat_dir/profiles/$p.json";
    failx("profile file missing: $p") unless -f $pp;
    my $pd = eval { decode_json(slurp($pp)) };
    failx("profile $p json invalid") if $@ || ref($pd) ne "HASH";
    my $list = $pd->{controls} // [];
    failx("profile $p empty") unless @$list;
    no_dup($list, "profile $p");
    my %in_prof = map { $_ => 1 } @$list;
    for my $cid (@$list) { failx("profile $p references unknown control: $cid") unless $ids{$cid}; }
    for my $c (@$controls) {
      if (grep { $_ eq $p } @{ $c->{profiles} }) {
        failx("control $c->{id} declares profile $p but profile lacks it") unless $in_prof{ $c->{id} };
      }
    }
  }

  # 标准映射必须在本地快照中存在
  my $asvs = eval { decode_json(slurp("$upstream_root/asvs/5.0.0/OWASP_Application_Security_Verification_Standard_5.0.0_en.json")) };
  failx("local ASVS snapshot unreadable") if $@ || ref($asvs) ne "HASH";
  my %asvs_ids;
  my $walk; $walk = sub {
    my ($n) = @_;
    return unless ref($n) eq "HASH";
    $asvs_ids{ $n->{Shortcode} } = 1 if defined $n->{Shortcode};
    $walk->($_) for @{ $n->{Items} // [] };
  };
  $walk->($_) for @{ $asvs->{Requirements} // [] };
  for my $a (sort keys %asvs_all) {
    failx("asvs id lacks v5.0.0- prefix: $a") unless $a =~ /^v5\.0\.0-/;
    (my $sc = $a) =~ s/^v5\.0\.0-//;
    failx("asvs id not in local snapshot: $sc") unless $asvs_ids{$sc};
  }
  for my $t (sort keys %t10_all) {
    failx("top10 id format: $t") unless $t =~ /^A(\d{2}):2025$/;
    my $p = "$upstream_root/top10/2025/" . sprintf("A%02d", $1) . ".md";
    failx("top10 id not in local snapshot: $t") unless -f $p && index(slurp($p), $t) >= 0;
  }
  for my $t (sort keys %api_all) {
    failx("api id format: $t") unless $t =~ /^API(\d{1,2}):2023$/;
    my $p = "$upstream_root/api-top10/2023/API$1.md";
    failx("api id not in local snapshot: $t") unless -f $p && index(slurp($p), $t) >= 0;
  }

  printf "SECURITY_CATALOG_OK=%s CONTROLS=%d ASVS=%d TOP10=%d API_TOP10=%d\n",
    $cat->{catalog_version}, scalar(@$controls), scalar(keys %asvs_all), scalar(keys %t10_all), scalar(keys %api_all);
' "$CATALOG_PATH" "$UPSTREAM_ROOT" "$MANIFEST_SHA" || exit 1
