#!/bin/bash
set -euo pipefail

# OWASP 离线上游基线完整性契约（offline upstream baseline integrity）：
#   references/security/upstream/** 是不可变官方快照——manifest.json 是唯一清单，
#   逐文件 SHA-256 三方对账（manifest ↔ 磁盘字节 ↔ 各目录 SHA256SUMS），
#   NOTICE.md 记录来源/版本/许可证/原样保存声明。本测试只读本地文件，
#   不访问任何网络——上游更新只能走 scripts/maintenance/update-owasp-baseline.sh 显式维护流程。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
# CC_CODE_REVIEWER_UPSTREAM_DIR：仅供 scripts/maintenance/update-owasp-baseline.sh --verify-only
# 复用本契约核验 staging 目录；默认面向仓库内正式快照。
UPSTREAM="${CC_CODE_REVIEWER_UPSTREAM_DIR:-$ROOT_DIR/references/security/upstream}"

fail() { echo "FAIL(upstream): $*" >&2; exit 1; }

[ -f "$UPSTREAM/manifest.json" ] || fail "missing upstream/manifest.json"
[ -d "$UPSTREAM/asvs/5.0.0" ] || fail "missing upstream/asvs/5.0.0"
[ -d "$UPSTREAM/top10/2025" ] || fail "missing upstream/top10/2025"
[ -d "$UPSTREAM/api-top10/2023" ] || fail "missing upstream/api-top10/2023"
ls "$UPSTREAM"/nodejs-cheat-sheet/ >/dev/null 2>&1 || fail "missing upstream/nodejs-cheat-sheet/"

# 单进程 Perl 完成全部 JSON/哈希/NOTICE 断言；任何违例 die（ERROR_UPSTREAM_*）。
perl -MJSON::PP -MDigest::SHA -e '
  use strict; use warnings;
  my $up = $ARGV[0];

  sub slurp { my ($p) = @_; open my $fh, "<:raw", $p or die "ERROR_UPSTREAM_READ_FAILED=$p\n"; local $/; my $d = <$fh>; close $fh; return $d; }
  sub sha { my ($p) = @_; my $d = Digest::SHA->new(256); $d->addfile($p, "b"); return $d->hexdigest; }
  sub failx { die "ERROR_UPSTREAM_CONTRACT=@_\n"; }

  my $mtext = slurp("$up/manifest.json");
  my $man = eval { decode_json($mtext) };
  failx("manifest.json is not valid JSON") if $@ || ref($man) ne "HASH";
  failx("manifest schema_version must be 1") unless ($man->{schema_version} // 0) == 1;
  failx("manifest generated_at must be ISO-8601 UTC") unless ($man->{generated_at} // "") =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
  my $srcs = $man->{sources};
  failx("manifest.sources must be a non-empty array") unless ref($srcs) eq "ARRAY" && @$srcs;

  my %want_ids = map { $_ => 1 } qw(owasp-asvs owasp-top10 owasp-api-top10 owasp-nodejs-cheat-sheet);
  my %seen_ids;
  my %all_paths;
  my %files_by_src;
  for my $s (@$srcs) {
    my $id = $s->{id} // "";
    failx("duplicate or unknown source id: $id") if $seen_ids{$id}++ || !$want_ids{$id};
    for my $k (qw(version source_url source_revision license local_root)) {
      failx("source $id lacks $k") unless defined($s->{$k}) && length($s->{$k} // "");
    }
    failx("source $id source_url must be official https") unless $s->{source_url} =~ m{^https://(www\.)?(owasp\.org|github\.com/OWASP/|raw\.githubusercontent\.com/OWASP/|githubusercontent\.com/OWASP/)}i;
    failx("source $id local_root must be relative without ..") if $s->{local_root} =~ m{^/|\.\.};
    my $files = $s->{files};
    failx("source $id files must be non-empty array") unless ref($files) eq "ARRAY" && @$files;
    for my $f (@$files) {
      my $p = $f->{path} // "";
      failx("source $id file path empty") unless length $p;
      failx("file path must be relative: $p") if $p =~ m{^/};
      failx("file path must not traverse: $p") if $p =~ m{(^|/)\.\.(/|$)};
      failx("duplicate file path in manifest: $p") if $all_paths{$p}++;
      failx("sha256 must be 64 lowercase hex: " . ($f->{sha256} // "")) unless ($f->{sha256} // "") =~ /^[0-9a-f]{64}$/;
      my $abs = "$up/$p";
      failx("manifest file missing on disk: $p") unless -f $abs;
      my $actual = sha($abs);
      failx("sha256 mismatch for $p: manifest=" . $f->{sha256} . " actual=$actual") unless $actual eq $f->{sha256};
      push @{ $files_by_src{$id} }, $f;
    }
  }
  failx("manifest must declare all 4 sources") unless scalar(keys %seen_ids) == 4;

  # 每个 local_root 的 SHA256SUMS / NOTICE.md 对账：SUMS 覆盖且仅覆盖该源内容文件。
  for my $s (@$srcs) {
    my $root = "$up/$s->{local_root}";
    my $sums_path = "$root/SHA256SUMS";
    failx("missing SHA256SUMS under $s->{local_root}") unless -f $sums_path;
    my %expect;
    for my $f (@{ $files_by_src{$s->{id}} }) {
      my @seg = split m{/}, $f->{path};
      $expect{ $seg[-1] } = $f->{sha256};
    }
    my %sums;
    for my $line (split /\n/, slurp($sums_path)) {
      next if $line =~ /^\s*$/;
      failx("SHA256SUMS line not in sha256-two-space-name format under $s->{local_root}: $line")
        unless $line =~ /^([0-9a-f]{64})  (\S.*)$/;
      my ($h, $n) = ($1, $2);
      failx("SHA256SUMS duplicate entry: $n") if $sums{$n}++;
      failx("SHA256SUMS entry not declared in manifest: $n") unless $expect{$n};
      failx("SHA256SUMS hash mismatch for $n") unless $h eq $expect{$n};
    }
    for my $n (keys %expect) {
      failx("SHA256SUMS missing manifest file: $n") unless $sums{$n};
    }
    my $notice = "$root/NOTICE.md";
    failx("missing NOTICE.md under $s->{local_root}") unless -f $notice;
    my $ntext = slurp($notice);
    for my $needle ("https://", "Revision", "抓取日期", "许可证", "原样保存") {
      failx("NOTICE.md under $s->{local_root} lacks marker: $needle") unless index($ntext, $needle) >= 0;
    }
  }

  # 结构断言：ASVS 单文件 + 顶层 Version=5.0.0；Top10/API 各 11 个 markdown；NodeCS 目录与正文。
  my $asvs_dir = "$up/asvs/5.0.0";
  my $asvs_file = "$asvs_dir/OWASP_Application_Security_Verification_Standard_5.0.0_en.json";
  failx("missing ASVS 5.0.0 en json") unless -f $asvs_file;
  my $asvs = eval { decode_json(slurp($asvs_file)) };
  failx("ASVS json invalid") if $@ || ref($asvs) ne "HASH";
  failx("ASVS top-level Version must be 5.0.0") unless ($asvs->{Version} // "") eq "5.0.0";

  my $t10 = "$up/top10/2025";
  failx("missing top10 introduction.md") unless -f "$t10/introduction.md";
  for my $i (1 .. 10) {
    my $n = sprintf("A%02d", $i);
    my $p = "$t10/$n.md";
    failx("missing $n.md") unless -f $p;
    my $t = slurp($p);
    failx("$n.md does not contain its Top10 id $n:2025") unless index($t, "$n:2025") >= 0;
  }
  my $api = "$up/api-top10/2023";
  failx("missing api introduction.md") unless -f "$api/introduction.md";
  for my $i (1 .. 10) {
    my $n = "API$i";
    my $p = "$api/$n.md";
    failx("missing $n.md") unless -f $p;
    my $t = slurp($p);
    failx("$n.md does not contain its API id $n:2023") unless index($t, "$n:2023") >= 0;
  }

  my @cs_dirs = glob("$up/nodejs-cheat-sheet/*");
  failx("nodejs-cheat-sheet must hold exactly one pinned dir") unless @cs_dirs == 1 && -d $cs_dirs[0];
  my ($cs_dir) = @cs_dirs;
  my $cs_name = $cs_dir; $cs_name =~ s{^.*/}{};
  failx("nodejs-cheat-sheet dir must be a commit SHA prefix (>=12 hex): $cs_name") unless $cs_name =~ /^[0-9a-f]{12,64}$/;
  my $cs_file = "$cs_dir/Nodejs_Security_Cheat_Sheet.md";
  failx("missing Nodejs_Security_Cheat_Sheet.md") unless -f $cs_file;
  my $cs_head = slurp($cs_file);
  failx("Node.js cheat sheet must start with its markdown title") unless $cs_head =~ /^#\s+Node\.?JS?\s+Security\s+Cheat\s+Sheet/mi;
' "$UPSTREAM" || { cat >&2 <<'HINT'
建议：upstream 快照缺失或被改动。核对 references/security/upstream/manifest.json 与
各目录 SHA256SUMS/NOTICE.md；上游更新只能通过 scripts/maintenance/update-owasp-baseline.sh
显式维护流程重做，不得手改快照正文。
HINT
exit 1; }

echo "PASS: security upstream baseline integrity"
