#!/bin/bash
set -euo pipefail

# 报告证据重归档：finding 声明的文件与证据代码实际所在文件不一致时，先在声明文件内
# 校正行号漂移；声明文件内找不到证据时，在 manifest 圈定的审查范围内逐行精确匹配，
# 唯一命中才把位置（文件+行号）一起重写到真实文件并追加位置修正说明；0 处或多处命中
# 保持原状（fail-open，绝不猜测）。报告仅在发生修改时原子替换。

REPORT_MD="${1:?请输入报告 Markdown 路径}"
PROJECT_DIR="${2:?请输入项目根目录}"
MANIFEST_FILE="${3:?请输入审查范围 manifest 路径}"
[ -f "$REPORT_MD" ] || { echo "REPORT_MD_NOT_FOUND=$REPORT_MD" >&2; exit 1; }
[ -r "$REPORT_MD" ] || { echo "REPORT_MD_NOT_READABLE=$REPORT_MD" >&2; exit 1; }
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
[ -r "$MANIFEST_FILE" ] || { echo "MANIFEST_FILE_NOT_READABLE=$MANIFEST_FILE" >&2; exit 1; }
REPORT_MD="$(cd "$(dirname "$REPORT_MD")" && pwd -P)/$(basename "$REPORT_MD")"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

perl -Mutf8 -MEncode=decode,encode,FB_CROAK,LEAVE_SRC -MCwd=abs_path -MFile::Spec -e '
  use strict; use warnings;
  my $MAX_FILE_BYTES = 2 * 1024 * 1024;  # 超过 2MiB 的候选不参与匹配
  my $BINARY_SNIFF   = 8000;             # 前 8000 字节含 NUL 视为二进制
  my $MAX_NEEDLE     = 5;                # 证据最多取前 5 个非空行

  my $tmpfile = "";
  END { unlink $tmpfile if length $tmpfile && -e $tmpfile; }

  # argv/manifest 路径按 UTF-8 解码，保证中文路径可与报告内字符串拼接比较。
  sub to_chars {
    my $s = shift;
    return $s if utf8::is_utf8($s);
    my $t = eval { decode("UTF-8", $s, FB_CROAK | LEAVE_SRC) };
    return defined $t ? $t : $s;
  }
  my ($report, $project, $manifest) = map { to_chars($_) } @ARGV;
  sub inside_project {
    my $ap = shift;
    return defined($ap) && ($ap eq $project || index($ap, "$project/") == 0);
  }
  my @cands;                              # 候选须在所有子过程定义前声明（闭包可见性）
  my ($total, $same, $refiled, $unresolved, $changed) = (0, 0, 0, 0, 0);
  sub slurp_raw {
    my $p = shift;
    open my $fh, "<:raw", $p or return undef;
    local $/; my $d = <$fh>; close $fh;
    return defined $d ? $d : "";
  }
  sub slurp_text {
    my $raw = slurp_raw(shift);
    return undef unless defined $raw;
    my $t = eval { decode("UTF-8", $raw, FB_CROAK | LEAVE_SRC) };
    return defined $t ? $t : $raw;  # 非 UTF-8 输入按字节兜底，匹配不上即原样保留
  }
  # 候选/声明文件统一约束：存在、可读、不超过 2MiB、非二进制。
  sub usable_source {
    my $ap = shift;
    return unless defined $ap && -f $ap && -r $ap;
    return if -s $ap > $MAX_FILE_BYTES;
    open my $bf, "<:raw", $ap or return;
    my $buf = ""; my $got = read($bf, $buf, $BINARY_SNIFF); close $bf;
    return if defined($got) && index($buf, "\x00") >= 0;
    return 1;
  }
  # 归一化：去 CRLF、去缩进、剥掉一个 diff 前缀（+/-，空格前缀已随缩进去除）、再去首尾空白。
  # 报告内证据行通常带缩进，必须先去缩进才能看到 diff 前缀；源文件行做同样处理保证口径一致。
  sub norm_line {
    my $l = shift;
    $l =~ s/\r$//;
    $l =~ s/^\s+//;
    $l =~ s/^[-+]?//;
    $l =~ s/^\s+//;
    $l =~ s/\s+$//;
    return $l;
  }

  my %seq_cache;
  sub load_seq {
    my $ap = shift;
    return $seq_cache{$ap} if exists $seq_cache{$ap};
    my $seq = [];
    my $t = slurp_text($ap);
    if (defined $t) {
      $t =~ s/\r\n/\n/g;
      my @ls = split /\n/, $t, -1;
      pop @ls if @ls && $ls[-1] eq "";
      for my $i (0 .. $#ls) {
        my $n = norm_line($ls[$i]);
        push @$seq, [$n, $i + 1] if length $n;
      }
    }
    $seq_cache{$ap} = $seq;
    return $seq;
  }
  # 在非空行序列上滑动窗口精确匹配，返回所有命中的起始源文件行号。
  sub match_lines {
    my ($seq, $needle) = @_;
    my $n = @$needle;
    my @hits;
    return @hits unless $n;
    for (my $i = 0; $i + $n <= @$seq; $i++) {
      my $ok = 1;
      for my $j (0 .. $n - 1) {
        if ($seq->[$i + $j][0] ne $needle->[$j]) { $ok = 0; last; }
      }
      push @hits, $seq->[$i][1] if $ok;
    }
    return @hits;
  }
  sub display_path {
    my $ap = shift;
    return substr($ap, length($project) + 1) if index($ap, "$project/") == 0;
    return $ap;
  }

  # manifest → 绝对路径、去重、按路径排序的候选列表（确定性迭代顺序）。
  {
    my %seen;
    open my $mf, "<", $manifest or die "MANIFEST_READ_ERROR=$manifest\n";
    while (my $line = <$mf>) {
      $line =~ s/\r?\n\z//;
      $line =~ s/^\s+//;
      $line =~ s/\s+$//;
      next unless length $line;
      $line = to_chars($line);
      my $raw = File::Spec->file_name_is_absolute($line) ? $line : File::Spec->catfile($project, $line);
      my $ap = abs_path($raw);
      next unless defined $ap && inside_project($ap) && !$seen{$ap}++ && usable_source($ap);
      push @cands, $ap;
    }
    close $mf;
  }
  @cands = sort @cands;

  my $text = slurp_text($report);
  die "REPORT_READ_ERROR=$report\n" unless defined $text;
  $text =~ s/\r\n/\n/g;
  my $had_nl = $text =~ /\n\z/ ? 1 : 0;
  my @lines = split /\n/, $text, -1;
  pop @lines if @lines && $lines[-1] eq "";

  sub process_block {
    my $blkr = shift;
    my ($loc_idx, $loc_path, $loc_line);
    for my $i (1 .. $#$blkr) {
      my $l = $blkr->[$i];
      next unless $l =~ /^-\s*文件：\s*(\S.*?)\s*$/;
      my $rest = $1;
      if    ($rest =~ /^(.*):(\d+)$/)  { ($loc_path, $loc_line) = ($1, $2); }
      elsif ($rest =~ /^(.*)：(\d+)$/) { ($loc_path, $loc_line) = ($1, $2); }
      else                             { ($loc_path, $loc_line) = ($rest, 0); }
      $loc_idx = $i;
      last;
    }
    return 0 unless defined $loc_idx && length $loc_path;
    # 证据 = 块内第一个围栏代码块（围栏行允许缩进/带语言标记）；未闭合围栏视为无证据。
    my ($open, $close);
    for my $i (1 .. $#$blkr) {
      my $t = $blkr->[$i];
      $t =~ s/^\s+//;
      $t =~ s/\s+$//;
      if (!defined $open) { $open = $i if $t =~ /^```/; }
      elsif (!defined $close && $t =~ /^```/) { $close = $i; last; }
    }
    return 0 unless defined $open && defined $close;
    my @needle;
    for my $i ($open + 1 .. $close - 1) {
      my $n = norm_line($blkr->[$i]);
      next unless length $n;
      push @needle, $n;
      last if @needle >= $MAX_NEEDLE;
    }
    return 0 unless @needle;

    $total++;
    my $old_line = $loc_line;
    my $claim_raw = File::Spec->file_name_is_absolute($loc_path) ? $loc_path : File::Spec->catfile($project, $loc_path);
    my $claim_abs = abs_path($claim_raw);
    my @claim = (defined $claim_abs && inside_project($claim_abs) && usable_source($claim_abs)) ? match_lines(load_seq($claim_abs), \@needle) : ();
    if (@claim) {
      my %d;
      $d{$_} = 1 for @claim;
      return 0 if $d{$old_line};          # 命中报告行号：本来就好，不动
      if (keys(%d) == 1) {
        my ($new) = keys %d;
        $blkr->[$loc_idx] =~ s/^(-\s*文件：\s*).*$/$1$loc_path:$new/;
        $same++;
        return 1;
      }
      $unresolved++;                      # 同文件多处命中，无法唯一定位
      return 0;
    }
    my @hits;
    for my $c (@cands) {
      next if defined $claim_abs && $c eq $claim_abs;
      my @h = match_lines(load_seq($c), \@needle);
      push @hits, [$c, $h[0]] if @h;     # 每个候选文件只记首个命中，唯一性按文件计
    }
    if (@hits == 1) {
      my ($newabs, $new_line) = @{$hits[0]};
      my $disp = display_path($newabs);
      $blkr->[$loc_idx] =~ s/^(-\s*文件：\s*).*$/$1$disp:$new_line/;
      splice @$blkr, $loc_idx + 1, 0, "- 位置修正：原 $loc_path:$old_line，证据代码实际位于本文件（跨文件重归档）";
      $refiled++;
      return 1;
    }
    $unresolved++;
    return 0;
  }

  my (@out, $blk);
  for my $l (@lines) {
    if ($l =~ /^###\s+(?:P[0-3]|待确认)(?:\b|\s|\|)/) {
      if (defined $blk) { $changed += process_block($blk); push @out, @$blk; }
      $blk = [$l];
    } elsif (defined $blk && ($l =~ /^##\s+/ || $l =~ /^###\s+/)) {
      $changed += process_block($blk);
      push @out, @$blk;
      push @out, $l;
      $blk = undef;
    } elsif (defined $blk) {
      push @$blk, $l;
    } else {
      push @out, $l;
    }
  }
  if (defined $blk) { $changed += process_block($blk); push @out, @$blk; }

  # 仅在发生修改时写出：内容先落临时文件再原子 rename，崩溃不会留下半份报告。
  if ($changed) {
    my $newtext = join("\n", @out);
    $newtext .= "\n" if $had_nl;
    $tmpfile = "$report.relocate.$$";
    my @st = stat($report);
    open my $of, ">:raw", $tmpfile or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
    print {$of} encode("UTF-8", $newtext) or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
    close $of or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
    chmod((@st ? $st[2] & 07777 : 0644), $tmpfile);
    rename($tmpfile, $report) or die "RENAME_ERROR=$report: $!\n";
  }

  print "RELOCATE_REPORT_PATH=$report\n";
  print "RELOCATE_TOTAL_BLOCKS=$total\n";
  print "RELOCATE_SAME_FILE_FIXED=$same\n";
  print "RELOCATE_REFILED=$refiled\n";
  print "RELOCATE_UNRESOLVED=$unresolved\n";
' "$REPORT_MD" "$PROJECT_DIR" "$MANIFEST_FILE"
