#!/usr/bin/perl
use strict; use warnings; use utf8; use JSON::PP; use Encode qw(decode FB_CROAK);
use FindBin; use IPC::Open3; use IO::Select; use Symbol qw(gensym);
binmode STDOUT, ':utf8';

# 评测比对器（记录工具，不伪造模型召回率——协议见同目录 README.md）：
#   perl compare-eval-report.pl <REPORT_MD> <EXPECTED_JSON> <CASE_KEY> --controls <CONTROLS_JSON> [--validate-only]
#
# 读模型产出的 security 报告与 expected-controls.json 中对应 case 条目，输出判定：
#   {"case":"ssrf/vulnerable","verdict":"PASS|FAIL|ERROR","expected":[...],"found":[...],
#    "forbidden":[...],"missed":[...],"false_positives":[...],"status_drift":{...},
#    "report_valid":true|false,"findings":N,"pending":N}
# 判定规则：
#   expected_findings  → 报告必须存在携带该规则 ID 的问题块（漏报 = missed）
#   forbidden_findings → 报告不得出现该规则 ID 的问题块（误报 = false_positives）
#   expected_control_status → 台账行状态必须一致（漂移 = status_drift）
#   报告必须先通过 validate-security-report.sh（--validate-only 时只做这一步）

my ($report, $expected_json, $case_key) = @ARGV;
my $usage = "usage: compare-eval-report.pl <REPORT_MD> <EXPECTED_JSON> <CASE_KEY> --controls <CONTROLS_JSON> [--validate-only]\n";
die $usage
  unless $report && $expected_json && $case_key;
my ($validate_only, $controls_json) = (0, $ENV{CCR_CONTROLS_JSON} // '');
for (my $i = 3; $i < @ARGV; $i++) {
  if ($ARGV[$i] eq '--validate-only') { $validate_only = 1; next; }
  if ($ARGV[$i] eq '--controls' && defined $ARGV[$i + 1]) { $controls_json = $ARGV[++$i]; next; }
  die $usage;
}
die "controls JSON required (--controls or CCR_CONTROLS_JSON)\n$usage" unless $controls_json && -f $controls_json;

sub slurp { my ($p) = @_; open my $f, '<:raw', $p or die "read $p: $!\n"; local $/; my $d = <$f>; close $f; return $d; }

my $result = { case => $case_key, verdict => 'ERROR' };

# ---- 第一步：确定性报告校验器 ----
my $validator = $ENV{CCR_VALIDATOR}
  // "$FindBin::Bin/../../../scripts/core/validate-security-report.sh";
my $report_valid = 0;
if (-x $validator) {
  my $err = gensym;
  my $pid = open3(undef, my $stdout, $err, $validator, $report, $controls_json);
  my $select = IO::Select->new($stdout, $err);
  my $out = '';
  while (my @ready = $select->can_read) {
    for my $fh (@ready) {
      my $n = sysread($fh, my $chunk, 4096);
      if ($n) { $out .= $chunk; } else { $select->remove($fh); close $fh; }
    }
    last unless $select->count;
  }
  waitpid($pid, 0);
  $report_valid = ($? == 0) ? 1 : 0;
  $result->{validator_output} = $report_valid ? 'ok' : $out;
} else {
  $result->{validator_output} = 'validator not found: $validator';
}
$result->{report_valid} = $report_valid;
if ($validate_only) { $result->{verdict} = $report_valid ? 'PASS' : 'FAIL'; emit($result); }

# ---- 第二步：问题块与台账抽取 ----
# 报告按 UTF-8 解码（失败按字节兜底）——本脚本正则为字符模式（use utf8），
# 不解码会导致中文/emoji 模式（安全规则 ID、🛡️ 章节）与字节文本永不匹配。
my $raw_text = slurp($report);
my $text = eval { decode("UTF-8", $raw_text, FB_CROAK) } // $raw_text;
$text =~ s/\r\n/\n/g;
my %blocks;          # 规则 ID → 出现次数（正式/待确认全部问题块）
my (%confirmed_blocks, %pending_blocks);
my %ledger;          # 规则 ID → 台账状态
my ($findings, $pending) = (0, 0);
my @lines = split /\n/, $text, -1;
my (@blocks_raw, $cur, $in);
for my $l (@lines) {
  if ($l =~ /^###\s+(?:P[0-3]|待确认)(?:\b|\s|\|)/) { push @blocks_raw, $cur if $in; $cur = [$l]; $in = 1; next; }
  if ($in) { if ($l =~ /^##\s/) { push @blocks_raw, $cur; $cur = undef; $in = 0; } else { push @$cur, $l; } }
}
push @blocks_raw, $cur if $in;
for my $blk (@blocks_raw) {
  next unless $blk && @$blk;
  my $body = join "\n", @$blk;
  next unless $body =~ /\*\*安全规则 ID\*\*：\s*(CCR-NODE-[A-Z0-9]+-[0-9]{3})/;
  my $id = $1;
  $blocks{$id}++;
  if ($blk->[0] =~ /^###\s+(P[0-3])/) { $findings++; $confirmed_blocks{$id}++; }
  else { $pending++; $pending_blocks{$id}++; }
}
my $in_sec = 0;
for my $l (@lines) {
  $in_sec = 1 if $l =~ /^##\s*🛡️\s*Security 控制覆盖/;
  if ($in_sec && $l =~ /^##\s/ && $l !~ /🛡️/) { $in_sec = 0; }
  next unless $in_sec && $l =~ /^\|\s*(CCR-NODE-[A-Z0-9]+-[0-9]{3})\s*\|/;
  my @cells = map { my $c = $_; $c =~ s/^\s+|\s+$//g; $c } split /\|/, $l;
  shift @cells if @cells && $cells[0] eq '';
  pop @cells if @cells && $cells[-1] eq '';
  next unless @cells >= 5;
  $ledger{ $cells[0] } = $cells[4] unless exists $ledger{ $cells[0] };
}

# ---- 第三步：预期比对 ----
my $expected = eval { decode_json(slurp($expected_json)) };
die "expected-controls.json 解析失败: $@\n" if $@;
my ($entry) = grep { ($_->{case} // '') eq $case_key } @{ $expected };
die "expected-controls.json 中不存在 case: $case_key\n" unless $entry;

my @missed = grep { !$confirmed_blocks{$_} } @{ $entry->{expected_findings} // [] };
my @false_pos = grep { $confirmed_blocks{$_} } @{ $entry->{forbidden_findings} // [] };
# 状态口径：
#   expected=finding_confirmed   → 台账必须是 finding_confirmed（漏报检测）
#   expected=checked_no_finding  → 语义为「不得确认」：finding_confirmed 即漂移
#     （误报检测）。安全对照夹具中被 profile 排除的控制常以 not_applicable 行
#     或无行 + E 披露呈现，均为合规形态，不强求逐字 checked_no_finding。
#   其他 expected 值 → 逐字比对。
my %drift;
for my $id (sort keys %{ $entry->{expected_control_status} // {} }) {
  my $want = $entry->{expected_control_status}{$id};
  my $got = $ledger{$id} // '<台账缺行>';
  my $bad;
  if ($entry->{strict_control_status})   { $bad = ($got ne $want) }
  elsif ($want eq 'finding_confirmed')   { $bad = ($got ne 'finding_confirmed') }
  elsif ($want eq 'checked_no_finding')  { $bad = ($got eq 'finding_confirmed') }
  else                                   { $bad = ($got ne $want) }
  $drift{$id} = "$got (expected $want)" if $bad;
}
$result->{expected} = $entry->{expected_findings} // [];
$result->{found} = [sort keys %blocks];
$result->{confirmed_found} = [sort keys %confirmed_blocks];
$result->{pending_found} = [sort keys %pending_blocks];
$result->{forbidden} = $entry->{forbidden_findings} // [];
$result->{missed} = \@missed;
$result->{false_positives} = \@false_pos;
$result->{status_drift} = \%drift;
$result->{findings} = $findings;
$result->{pending} = $pending;
$result->{verdict} = (!$report_valid || @missed || @false_pos || %drift) ? 'FAIL' : 'PASS';
emit($result);

sub emit {
  my ($r) = @_;
  print JSON::PP->new->canonical->utf8->encode($r), "\n";
  exit(($r->{verdict} eq 'PASS') ? 0 : 1);
}
