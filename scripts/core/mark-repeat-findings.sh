#!/bin/bash
set -euo pipefail

# 增量复审重复发现标记（repeat-finding suppression，吸收自 OpenCodeReview 增量模式并适配）：
#   mark-repeat-findings.sh <NEW_REPORT> <PREV_REPORT> [iou_threshold]
#
# 复审同一仓库时，上轮报告已出现过的发现不应再以全新问题的姿态全量呈现。本脚本把
# 本轮报告中命中上轮的发现块就地“标记”而非删除（fail-open：宁可多报，绝不吞问题），
# 命中判定零 LLM、只依赖稳定事实：
#
# 身份前置条件（同时满足才进入区间比较）：
#   1. 文件路径一致：块内第一条「- 文件：」行提取路径，按原字节比较，仅做 trim 与
#      反斜杠→正斜杠统一（不做相对化 / 大小写归一）；
#   2. 维度标签一致：表头第一个 [...] 内层文本（内部连续空白折叠为单空格）相等；
#      单侧缺失方括号即不可比，双侧同时缺失才视为可比。
#
# 行区间（每条发现独立构造，口径与 relocate-findings.sh / merge-batch-results.sh 一致）：
#   - 「路径:行号」点发现：[start, start + max(1, 非空归一化证据行数) - 1]，证据取块内
#     第一个闭合围栏代码块（围栏行允许缩进/带语言标记），逐行按 norm_line 归一
#     （去 CR → trim → 剥一个 +/- 前缀 → 再 trim → 丢弃空行）；无闭合围栏或全空时退化为
#     [line, line]；
#   - 「路径:起-止」范围发现：显式范围优先 [start, end]，起止倒置自动纠正。
#
# 命中：IoU = 交集行数 / 并集行数（不相交为 0），IoU > 阈值（严格大于）即命中；命中仅
# 在本轮表头行末尾追加一次“（上轮已报）”，其余行零改动；表头已带标记的块不重复叠加
# （幂等，重复运行字节稳定）。阈值默认 0.6，环境变量
# CC_CODE_REVIEWER_REPEAT_IOU_THRESHOLD 可覆盖，命令行第 3 参优先于环境变量；非法阈值
# （非数字或超出 [0,1]）按用法错误 exit 1。
#
# stdout 契约（恒 4 行）：
#   REPEAT_REPORT_PATH=<NEW_REPORT 绝对路径>
#   REPEAT_TOTAL_BLOCKS=<NEW_REPORT 位置可解析发现块数>
#   REPEAT_PREV_BLOCKS=<PREV_REPORT 位置可解析发现块数>
#   REPEAT_MARKED=<本次实际追加标记的块数>
# 「位置可解析」= 第一条「- 文件：」行带数字锚点（:N 或 :N-M，半角/全角冒号均可）。
#
# fail-open：PREV_REPORT 解析不出任何有效块时按零命中继续（零标记、报告不动）；
# PREV_REPORT 路径不存在/不可读属用法错误（exit 1 + stderr 标签）。报告仅在发生修改时
# 原子替换（同目录临时文件 + rename），零修改时磁盘字节保持不变。

NEW_REPORT="${1:?请输入本轮报告 Markdown 路径}"
PREV_REPORT="${2:?请输入上轮报告 Markdown 路径}"
IOU_THRESHOLD="${3:-${CC_CODE_REVIEWER_REPEAT_IOU_THRESHOLD:-0.6}}"

[ -f "$NEW_REPORT" ] || { echo "NEW_REPORT_NOT_FOUND=$NEW_REPORT" >&2; exit 1; }
[ -r "$NEW_REPORT" ] || { echo "NEW_REPORT_NOT_READABLE=$NEW_REPORT" >&2; exit 1; }
[ -f "$PREV_REPORT" ] || { echo "PREV_REPORT_NOT_FOUND=$PREV_REPORT" >&2; exit 1; }
[ -r "$PREV_REPORT" ] || { echo "PREV_REPORT_NOT_READABLE=$PREV_REPORT" >&2; exit 1; }
NEW_REPORT="$(cd "$(dirname "$NEW_REPORT")" && pwd -P)/$(basename "$NEW_REPORT")"

# 阈值合法性：非负小数且不超过 1（“1” 合法但严格大于 ⇒ 永不命中，属合法配置）。
if ! perl -e 'my $t = $ARGV[0]; exit 0 if $t =~ /^[0-9]+(?:\.[0-9]+)?$/ && $t + 0 <= 1; exit 1;' "$IOU_THRESHOLD"; then
  echo "ERROR_REPEAT_IOU_THRESHOLD=${IOU_THRESHOLD}（取值须为 0 到 1 之间的小数）" >&2
  exit 1
fi

perl -Mutf8 -MEncode=decode,encode,FB_CROAK,LEAVE_SRC -e '
  use strict; use warnings;
  binmode STDOUT, ":utf8";
  my $MARKER = "（上轮已报）";
  my $tmpfile = "";
  END { unlink $tmpfile if length $tmpfile && -e $tmpfile; }

  # argv 按 UTF-8 解码，保证中文路径/标题可与报告内字符串正确拼接比较。
  sub to_chars {
    my $s = shift;
    return $s if utf8::is_utf8($s);
    my $t = eval { decode("UTF-8", $s, FB_CROAK | LEAVE_SRC) };
    return defined $t ? $t : $s;
  }
  sub slurp_raw {
    my $p = shift;
    open my $fh, "<:raw", $p or return undef;
    local $/; my $d = <$fh>; close $fh;
    return defined $d ? $d : "";
  }
  sub read_text {
    my ($p, $label) = @_;
    my $raw = slurp_raw($p);
    die "${label}_READ_ERROR=$p\n" unless defined $raw;
    my $t = eval { decode("UTF-8", $raw, FB_CROAK | LEAVE_SRC) };
    return defined $t ? $t : $raw;  # 非 UTF-8 输入按字节兜底：块头匹配不上即零标记（fail-open）
  }
  # 证据行归一化：与 relocate-findings.sh / merge-batch-results.sh 的 norm_line 完全一致
  # （步骤顺序不得调整，保证同一线证据在两处归一结果逐字节相同）。
  sub norm_line {
    my $l = shift // "";
    $l =~ s/\r$//;
    $l =~ s/^\s+//;
    $l =~ s/^[-+]?//;
    $l =~ s/^\s+//;
    $l =~ s/\s+$//;
    return $l;
  }
  sub collapse_ws {
    my $s = shift // "";
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
  }
  # 表头维度信息：(是否含方括号, 折叠后标签)。缺失方括号返回 (0, "")。
  sub dim_info {
    my $hdr = shift // "";
    return (0, "") unless $hdr =~ /\[([^\]]*)\]/;
    return (1, collapse_ws($1));
  }
  # 维度可比：双方都有括号 ⇒ 标签相等；双方都无括号 ⇒ 可比；单侧缺失 ⇒ 不可比。
  sub dim_ok {
    my ($a, $b) = @_;
    return $a->[1] eq $b->[1] if $a->[0] && $b->[0];
    return ($a->[0] || $b->[0]) ? 0 : 1;
  }
  # 块内第一个闭合围栏代码块的非空归一化证据行数；无闭合围栏返回 0。
  sub evidence_count {
    my $blkr = shift;
    my ($open, $close);
    for my $i (1 .. $#$blkr) {
      my $t = $blkr->[$i];
      $t =~ s/^\s+//;
      $t =~ s/\s+$//;
      next unless $t =~ /^```/;
      if (!defined $open) { $open = $i; }
      else { $close = $i; last; }
    }
    return 0 unless defined $open && defined $close;
    my $n = 0;
    for my $i ($open + 1 .. $close - 1) {
      $n++ if length norm_line($blkr->[$i]);
    }
    return $n;
  }
  # 位置可解析 = 第一条「- 文件：」行带数字锚点（:N / :N-M，半角或全角冒号）。
  # 返回 { path, s, e, dim }；不可解析返回 undef。
  sub parse_finding {
    my $blkr = shift;                 # [0] = 表头行
    my ($path, $s, $e);
    for my $i (1 .. $#$blkr) {
      my $l = $blkr->[$i];
      next unless $l =~ /^-\s*文件：\s*(\S.*?)\s*$/;
      my $rest = $1;
      if    ($rest =~ /^(.*):(\d+)-(\d+)$/)  { ($path, $s, $e) = ($1, $2, $3); }
      elsif ($rest =~ /^(.*)：(\d+)-(\d+)$/) { ($path, $s, $e) = ($1, $2, $3); }
      elsif ($rest =~ /^(.*):(\d+)$/)        { ($path, $s)    = ($1, $2); }
      elsif ($rest =~ /^(.*)：(\d+)$/)       { ($path, $s)    = ($1, $2); }
      else { return undef; }          # 有文件行但无数字锚点：位置不可解析
      last;
    }
    return undef unless defined $path && length $path;
    $path =~ s!\\!/!g;                # 仅 trim（正则已保证）+ 反斜杠统一，保留原字节
    ($s, $e) = ($e, $s) if defined $e && $e < $s;
    if (!defined $e) {
      my $n = evidence_count($blkr);
      $n = 1 if $n < 1;
      $e = $s + $n - 1;
    }
    return { path => $path, s => $s + 0, e => $e + 0, dim => [ dim_info($blkr->[0]) ] };
  }
  # 区间 IoU：交集行数 / 并集行数；不相交为 0。
  sub iou {
    my ($s1, $e1, $s2, $e2) = @_;
    my $is = $s1 > $s2 ? $s1 : $s2;
    my $ie = $e1 < $e2 ? $e1 : $e2;
    my $inter = $is <= $ie ? ($ie - $is + 1) : 0;
    return 0 unless $inter;
    my $us = $s1 < $s2 ? $s1 : $s2;
    my $ue = $e1 > $e2 ? $e1 : $e2;
    return $inter / ($ue - $us + 1);
  }
  # 块迭代口径与 relocate-findings.sh 相同：表头 ^### (P0-3|待确认)，块终于 ^## / ^###。
  sub collect_findings {
    my $lr = shift;
    my (@found, $blk);
    for my $l (@$lr) {
      if ($l =~ /^###\s+(?:P[0-3]|待确认)(?:\b|\s|\|)/) {
        if (defined $blk) { my $f = parse_finding($blk); push @found, $f if defined $f; }
        $blk = [$l];
      } elsif (defined $blk) {
        if ($l =~ /^##\s+/ || $l =~ /^###\s+/) {
          my $f = parse_finding($blk); push @found, $f if defined $f;
          $blk = undef;
        } else {
          push @$blk, $l;
        }
      }
    }
    if (defined $blk) { my $f = parse_finding($blk); push @found, $f if defined $f; }
    return @found;
  }

  # 共享状态（须在 process_new_block 定义前声明——闭包可见性，参照 relocate-findings.sh）。
  my $threshold = 0;
  my @prev = ();
  my ($total, $marked, $changed) = (0, 0, 0);

  sub process_new_block {
    my $blkr = shift;
    my $f = parse_finding($blkr);
    return unless defined $f;
    $total++;
    return unless @prev;
    for my $pf (@prev) {
      next unless $pf->{path} eq $f->{path};
      next unless dim_ok($f->{dim}, $pf->{dim});
      next unless iou($f->{s}, $f->{e}, $pf->{s}, $pf->{e}) > $threshold;
      unless ($blkr->[0] =~ /\Q$MARKER\E\z/) {   # 幂等：已标记的表头不再叠加
        $blkr->[0] .= $MARKER;
        $marked++;
        $changed++;
      }
      last;                                       # 一个块至多一个标记，即使多处命中
    }
  }

  my ($new_report, $prev_report, $thr) = map { to_chars($_) } @ARGV;
  $threshold = $thr + 0;

  # 上轮报告：fail-open——解析失败/无有效块时得到空列表，本轮零标记照常输出。
  my $prev_text = read_text($prev_report, "PREV_REPORT");
  $prev_text =~ s/\r\n/\n/g;
  my @plines = split /\n/, $prev_text, -1;
  pop @plines if @plines && $plines[-1] eq "";
  @prev = collect_findings(\@plines);

  my $text = read_text($new_report, "NEW_REPORT");
  $text =~ s/\r\n/\n/g;
  my $had_nl = $text =~ /\n\z/ ? 1 : 0;
  my @lines = split /\n/, $text, -1;
  pop @lines if @lines && $lines[-1] eq "";

  my (@out, $blk);
  for my $l (@lines) {
    if ($l =~ /^###\s+(?:P[0-3]|待确认)(?:\b|\s|\|)/) {
      if (defined $blk) { process_new_block($blk); push @out, @$blk; }
      $blk = [$l];
    } elsif (defined $blk && ($l =~ /^##\s+/ || $l =~ /^###\s+/)) {
      process_new_block($blk);
      push @out, @$blk;
      push @out, $l;
      $blk = undef;
    } elsif (defined $blk) {
      push @$blk, $l;
    } else {
      push @out, $l;
    }
  }
  if (defined $blk) { process_new_block($blk); push @out, @$blk; }

  # 仅在发生修改时写出：内容先落同目录临时文件再原子 rename，零修改保持原字节。
  if ($changed) {
    my $newtext = join("\n", @out);
    $newtext .= "\n" if $had_nl;
    $tmpfile = "$new_report.repeat.$$";
    my @st = stat($new_report);
    open my $of, ">:raw", $tmpfile or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
    print {$of} encode("UTF-8", $newtext) or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
    close $of or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
    chmod((@st ? $st[2] & 07777 : 0644), $tmpfile);
    rename($tmpfile, $new_report) or die "RENAME_ERROR=$new_report: $!\n";
  }

  print "REPEAT_REPORT_PATH=$new_report\n";
  print "REPEAT_TOTAL_BLOCKS=$total\n";
  print "REPEAT_PREV_BLOCKS=" . scalar(@prev) . "\n";
  print "REPEAT_MARKED=$marked\n";
' "$NEW_REPORT" "$PREV_REPORT" "$IOU_THRESHOLD"
