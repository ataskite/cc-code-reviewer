#!/bin/bash
set -euo pipefail

# Security 报告确定性校验器（离线、零网络）：
#   bash scripts/core/validate-security-report.sh <REPORT_MD> <SECURITY_CONTROLS_JSON>
#
# 成功 stdout 单行：
#   SECURITY_REPORT_OK=<abs> CONTROLS=<n> FINDINGS=<n> PENDING=<n>
#
# 校验内容（fail closed，exit 1 + stderr ERROR_SECURITY_REPORT_*）：
# - 报告含「## 🛡️ Security 控制覆盖」章节；适用控制计数与对账行存在且数字自洽
#   （N = A + B + C + D；not_applicable 行单独计 E，不进入对账）。
# - 冻结 controls 的每条适用控制在台账表中恰好一行，状态属于封闭集合
#   {finding_confirmed, checked_no_finding, external_evidence_missing, static_unsupported}；
#   excluded_controls 只能以 not_applicable 行出现（最多一次）；表外 ID = 范围外引用，拒绝。
# - finding_confirmed 至少有一个携带该 安全规则 ID 的正式问题块（P0-P3）；
#   external_evidence_missing 至少有一个携带该 ID 的问题块（通常为待确认）。
# - 携带「**安全规则 ID**：CCR-NODE-*」的问题块必须同时携带 标准映射 与 检测方式
#   字段，且标准映射与 catalog 归一化一致（顺序无关、内容不可漂移）。
# - 本脚本只应被 Security（frontend）报告调用；报告无控制覆盖章节即失败。
#
# 本脚本不做飞书/SARIF 副作用；调用方（SKILL）在失败时必须禁止上传与 SARIF 导出。

if [ $# -ne 2 ]; then
  echo "ERROR_SECURITY_REPORT_USAGE=参数须为 <REPORT_MD> <SECURITY_CONTROLS_JSON>" >&2
  exit 1
fi
REPORT_MD="$1"
SECURITY_CONTROLS_JSON="$2"
[ -r "$REPORT_MD" ] || { echo "ERROR_SECURITY_REPORT_NOT_READABLE=$REPORT_MD" >&2; exit 1; }
[ -r "$SECURITY_CONTROLS_JSON" ] || { echo "ERROR_SECURITY_REPORT_CONTROLS_NOT_READABLE=$SECURITY_CONTROLS_JSON" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# catalog 与冻结 controls 同源（controls 产物记录 catalog_path；此处按插件标准布局解析，
# 冻结 controls 自身已含 catalog_sha256 绑定，哈希校验由恢复门禁负责）。
CATALOG="${CC_CODE_REVIEWER_SECURITY_CATALOG:-$(cd "$SCRIPT_DIR/../.." && pwd)/references/security/catalog/node-security-controls.json}"

perl -MJSON::PP -e '
  use strict; use warnings;
  my ($report_path, $controls_path, $catalog_path) = @ARGV;
  sub slurp { my ($p) = @_; open my $fh, "<", $p or die "ERROR_SECURITY_REPORT_READ=$p\n"; local $/; my $d = <$fh>; close $fh; return $d; }
  sub failx { my ($t, $m) = @_; print STDERR "ERROR_SECURITY_REPORT_${t}=${m}\n"; exit 1; }

  my $frozen = eval { decode_json(slurp($controls_path)) };
  failx("CONTROLS_INVALID", $controls_path) if $@ || ref($frozen) ne "HASH";
  my @applicable = map { $_->{id} // () } @{ $frozen->{controls} // [] };
  my %excluded = map { ($_->{id} // "") => 1 } @{ $frozen->{excluded_controls} // [] };
  my %allowed = map { $_ => 1 } (@applicable, keys %excluded);
  failx("CONTROLS_EMPTY", "frozen controls contain no applicable control") unless @applicable;

  my $catalog = eval { decode_json(slurp($catalog_path)) };
  failx("CATALOG_INVALID", $catalog_path) if $@ || ref($catalog) ne "HASH";
  my %cat_by_id = map { ($_->{id} // "") => $_ } @{ $catalog->{controls} // [] };

  my $text = slurp($report_path);
  $text =~ s/\r\n/\n/g;

  # ---- 章节 ----
  $text =~ /^##\s*🛡️\s*Security 控制覆盖[^\n]*$/m
    or failx("SECTION_MISSING", "报告缺少「## 🛡️ Security 控制覆盖」章节");
  my ($hdr_line, $sec_body) = $text =~ /^(##\s*🛡️\s*Security 控制覆盖[^\n]*)\n(.*?)(?=^##\s|\z)/ms
    or failx("SECTION_UNPARSEABLE", "控制覆盖章节边界无法解析");

  # ---- 计数行 ----
  my %metric;
  for my $name (qw(适用控制 已发现问题 已检查无发现 外部证据缺失 静态不可验证 不适用)) {
    $sec_body =~ /^-\s*${name}：\s*(\d+)\s*$/m or failx("METRIC_MISSING", "缺少计数行「- ${name}：N」");
    $metric{$name} = $1 + 0;
  }
  # 对账行：以字面「N = A + B + C + D」开头，行内可附带实际数字复算
  # （首个「x = a + b + c + d」形态，如「→ 5 = 1 + 4 + 0 + 0 ✓（…）」）；
  # 数字存在时必须与台账计数完全一致。
  my ($recon_ok, @recon_nums);
  for my $line (split /\n/, $sec_body) {
    # 字面形态「N = A + B + C + D」（可附数字复算后缀）或纯数字形态「6 = 1 + 4 + 1 + 0」
    next unless $line =~ /^-\s*对账：\s*(?:N = A \+ B \+ C \+ D|\d+\s*=\s*\d+\s*\+\s*\d+\s*\+\s*\d+\s*\+\s*\d+)/;
    $recon_ok = 1;
    if ($line =~ /(\d+)\s*=\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)/) {
      @recon_nums = ($1, $2, $3, $4, $5);
    }
    last;
  }
  failx("RECON_LINE_MISSING", "缺少对账行「- 对账：N = A + B + C + D」") unless $recon_ok;
  my $N = scalar @applicable;
  my $sum_abcd = $metric{"已发现问题"} + $metric{"已检查无发现"} + $metric{"外部证据缺失"} + $metric{"静态不可验证"};
  $metric{"适用控制"} == $N or failx("N_MISMATCH", "适用控制 $metric{qq(适用控制)} != 冻结适用数 $N");
  $sum_abcd == $N or failx("RECON_MISMATCH", "A+B+C+D=$sum_abcd != N=$N");
  # 数字复算后缀（若 agent 提供）：必须与台账计数完全一致
  if (@recon_nums && $recon_nums[0] ne "") {
    my @expect = ($N, $metric{"已发现问题"}, $metric{"已检查无发现"}, $metric{"外部证据缺失"}, $metric{"静态不可验证"});
    my @got = map { $_ + 0 } @recon_nums;
    failx("RECON_NUM_MISMATCH", "对账数字 @got 与台账计数 @expect 不一致") unless "@got" eq "@expect";
  }

  # ---- 台账表 ----
  my %row_status;   # id => status
  my %row_evidence; # id => evidence cell
  my $table_header_seen = 0;
  for my $line (split /\n/, $sec_body) {
    next unless $line =~ /^\|\s*CCR-NODE-/;
    my @cells = map { my $c = $_; $c =~ s/^\s+|\s+$//g; $c } split /\|/, $line;
    shift @cells if @cells && $cells[0] eq "";
    pop @cells if @cells && $cells[-1] eq "";
    @cells >= 6 or failx("ROW_MALFORMED", $line);
    my ($id, $title, $mapping, $detect, $status, $evidence) = @cells[0..5];
    $id =~ /^CCR-NODE-[A-Z0-9]+-[0-9]{3}$/ or failx("ROW_ID_INVALID", $id);
    exists $allowed{$id} or failx("ID_OUT_OF_SCOPE", "台账引用范围外控制: $id");
    exists $row_status{$id} and failx("ROW_DUPLICATED", $id);
    my %closed = map { $_ => 1 } qw(finding_confirmed checked_no_finding external_evidence_missing static_unsupported not_applicable);
    $closed{$status} or failx("STATUS_INVALID", "$id => $status");
    if ($excluded{$id}) {
      $status eq "not_applicable" or failx("EXCLUDED_NOT_NA", "excluded 控制 $id 只能是 not_applicable，实际 $status");
    } else {
      $status ne "not_applicable" or failx("APPLICABLE_NA", "适用控制 $id 不得标记 not_applicable（应给 checked_no_finding 或证据缺口）");
    }
    $row_status{$id} = $status;
    $row_evidence{$id} = $evidence // "";
  }
  for my $id (@applicable) {
    exists $row_status{$id} or failx("ROW_MISSING", "适用控制缺少台账行: $id");
  }
  # 计数与行状态一致。「不适用 E」按冻结 resolver 排除数对齐（deterministic）；
  # not_applicable 台账行可选（只能引用 excluded 控制，数量不得超过 E）。
  my %by_status;
  $by_status{ $_ }++ for values %row_status;
  $metric{"已发现问题"} == ($by_status{finding_confirmed} // 0) or failx("COUNT_A_MISMATCH", "已发现问题计数与台账不符");
  $metric{"已检查无发现"} == ($by_status{checked_no_finding} // 0) or failx("COUNT_B_MISMATCH", "已检查无发现计数与台账不符");
  $metric{"外部证据缺失"} == ($by_status{external_evidence_missing} // 0) or failx("COUNT_C_MISMATCH", "外部证据缺失计数与台账不符");
  $metric{"静态不可验证"} == ($by_status{static_unsupported} // 0) or failx("COUNT_D_MISMATCH", "静态不可验证计数与台账不符");
  my $excluded_n = scalar(keys %excluded);
  $metric{"不适用"} == $excluded_n or failx("COUNT_E_MISMATCH", "不适用计数 $metric{qq(不适用)} != 冻结排除控制数 $excluded_n");
  ($by_status{not_applicable} // 0) <= $excluded_n or failx("COUNT_E_MISMATCH", "not_applicable 台账行数超过冻结排除控制数");

  # ---- 问题块（### P0-P3/待确认 | ...）与 安全规则 ID 字段 ----
  my @lines = split /\n/, $text, -1;
  my (@blocks, $cur, $in);
  for my $l (@lines) {
    if ($l =~ /^###\s+(?:P[0-3]|待确认)/) { push @blocks, $cur if $in; $cur = [$l]; $in = 1; next; }
    if ($in) { if ($l =~ /^##\s/) { push @blocks, $cur; $in = 0; } else { push @$cur, $l; } }
  }
  push @blocks, $cur if $in;
  my %blocks_by_id;   # id -> [ [priority, block_text], ... ]
  my ($findings, $pending) = (0, 0);
  for my $b (@blocks) {
    my $header = $b->[0] // "";
    my ($prio) = $header =~ /^###\s+(P[0-3]|待确认)/;
    my $body = join "\n", @$b;
    next unless $body =~ /\*\*安全规则 ID\*\*：\s*(CCR-NODE-[A-Z0-9]+-[0-9]{3})/;
    my $id = $1;
    exists $allowed{$id} && !$excluded{$id} or failx("BLOCK_ID_OUT_OF_SCOPE", "问题块引用非适用控制: $id");
    my ($map_line) = $body =~ /\*\*标准映射\*\*：\s*(.+)$/m or failx("BLOCK_MAPPING_MISSING", "$id 问题块缺少标准映射字段");
    $body =~ /\*\*检测方式\*\*：\s*(.+)$/m or failx("BLOCK_DETECT_MISSING", "$id 问题块缺少检测方式字段");
    # 标准映射与 catalog 归一化一致
    my $c = $cat_by_id{$id};
    if ($c) {
      my %got = (top10 => [ $map_line =~ /(A\d{2}:2025)/g ],
                 api   => [ $map_line =~ /(API\d{1,2}:2023)/g ],
                 asvs  => [ $map_line =~ /(v5\.0\.0-V[\d.]+)/g ],
                 cwe   => [ $map_line =~ /(CWE-\d+)/g ]);
      my %want = (top10 => $c->{standards}{owasp_top10} || [], api => $c->{standards}{owasp_api_top10} || [],
                  asvs => $c->{standards}{asvs} || [], cwe => $c->{standards}{cwe} || []);
      for my $k (qw(top10 api asvs cwe)) {
        my %gs = map { $_ => 1 } @{ $got{$k} };
        my %ws = map { $_ => 1 } @{ $want{$k} };
        my $same = (keys(%gs) == keys(%ws)) && !grep { !$ws{$_} } keys %gs;
        $same or failx("MAPPING_DRIFT", "$id 的标准映射($k)与 catalog 不一致: 报告[@{[join qq(,), sort keys %gs]}] vs catalog[@{[join qq(,), sort keys %ws]}]");
      }
    }
    push @{ $blocks_by_id{$id} }, [$prio, $body];
    if ($prio =~ /^P[0-3]$/) { $findings++; } else { $pending++; }
  }
  # finding_confirmed 必须有正式问题块；external_evidence_missing 必须有问题块
  for my $id (@applicable) {
    my $st = $row_status{$id};
    next unless $st eq "finding_confirmed" || $st eq "external_evidence_missing";
    my $blk = $blocks_by_id{$id} || [];
    @$blk or failx("BLOCK_MISSING", "$st 控制 $id 缺少携带该规则 ID 的问题块");
    if ($st eq "finding_confirmed") {
      grep { $_->[0] =~ /^P[0-3]$/ } @$blk
        or failx("CONFIRMED_NOT_FORMAL", "finding_confirmed 控制 $id 的问题块均为待确认（需 P0-P3 正式条目）");
    }
  }

  printf "SECURITY_REPORT_OK=%s CONTROLS=%d FINDINGS=%d PENDING=%d\n",
    $report_path, $N, $findings, $pending;
' "$REPORT_MD" "$SECURITY_CONTROLS_JSON" "$CATALOG" || exit 1
