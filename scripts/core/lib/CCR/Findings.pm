package CCR::Findings;

# 发现内核（finding kernel）：报告后处理脚本共享的发现块解析 / 证据归一 / 路径口径 /
# 内容指纹 / 报告 IO 的唯一实现。此前这些子程序在以下五个脚本中逐句复制同步：
#   scripts/core/relocate-findings.sh
#   scripts/core/mark-repeat-findings.sh
#   scripts/core/merge-batch-results.sh
#   scripts/core/compare-review-reports.sh
#   scripts/core/export-sarif.sh
# 五脚本统一通过 `-I <libdir> -MCCR::Findings=:all` 导入；任何口径调整必须只改本模块，
# 并由 tests/core/test_core_lib_findings.sh 与五个脚本各自的契约测试共同守护。
#
# 两条有意不同、不得合并的路径口径：
#   - first_location_path（同轮：merge 去重 / SARIF 指纹 / relocate）只剥结尾一个
#     半/全角「:数字」点锚，区间行号不剥；
#   - compare_path（跨轮：compare 对比）把 :N / ：N / :N-M / ：N-M 全剥——跨轮报告
#     的引用方式会在点/区间之间漂移。
#
# 兼容性约束：面向系统 perl（macOS/Linux 发行版自带），只用核心模块
# （Exporter / Encode / Digest::SHA），不使用签名、后缀解引用等新语法。

use strict;
use warnings;
use utf8;   # 模块源码含中文正则字面量（待确认 / 文件 等），必须按字符语义编译

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
  norm_line collapse_ws parse_dim_tag dim_info
  first_location_path compare_path
  evidence_lines evidence_count
  is_issue_heading is_block_terminator
  finding_fingerprint
  to_chars slurp_raw read_text atomic_write_text
);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

use Encode qw(decode encode_utf8 FB_CROAK LEAVE_SRC);
use Digest::SHA qw(sha256_hex);

# ---- 报告 IO（Tier B）----

# argv/路径按 UTF-8 解码：已是字符序列则原样返回，非 UTF-8 字节按原字节兜底，
# 保证中文路径/标题可与报告内字符串正确拼接比较。
sub to_chars {
  my $s = shift;
  return $s if utf8::is_utf8($s);
  my $t = eval { decode("UTF-8", $s, FB_CROAK | LEAVE_SRC) };
  return defined $t ? $t : $s;
}

# 原始字节读入：文件不存在/不可读返回 undef（调用方决定 fail-open 还是 die）。
sub slurp_raw {
  my $p = shift;
  open my $fh, "<:raw", $p or return undef;
  local $/; my $d = <$fh>; close $fh;
  return defined $d ? $d : "";
}

# UTF-8 解码读入：$err_tag 必须是完整的 die 标签（各调用方保留历史标签，如
# mark-repeat 传 "PREV_REPORT_READ_ERROR"、compare 传 "ERROR_CURR_READ"），
# die 输出 "$err_tag=$path\n" 逐字节稳定。非 UTF-8 输入按字节兜底（fail-open）。
sub read_text {
  my ($p, $err_tag) = @_;
  my $raw = slurp_raw($p);
  die "$err_tag=$p\n" unless defined $raw;
  my $t = eval { decode("UTF-8", $raw, FB_CROAK | LEAVE_SRC) };
  return defined $t ? $t : $raw;
}

# 原子写：UTF-8 编码先落同目录临时文件（"$path$suffix"）→ 保留原文件权限位
# （缺失时 0644）→ rename 原子替换。die 标签固定 TMP_WRITE_ERROR / RENAME_ERROR
# （需要其他标签的调用方自行本地实现）。返回临时文件名；调用方可先按同一规则
# 预赋值自己的 $tmpfile，以便 END 钩子在异常中断时清理残片。
sub atomic_write_text {
  my ($path, $chars, $suffix) = @_;
  my $tmpfile = "$path$suffix";
  my @st = stat($path);
  open my $of, ">:raw", $tmpfile or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
  print {$of} encode_utf8($chars) or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
  close $of or die "TMP_WRITE_ERROR=$tmpfile: $!\n";
  chmod((@st ? $st[2] & 07777 : 0644), $tmpfile);
  rename($tmpfile, $path) or die "RENAME_ERROR=$path: $!\n";
  return $tmpfile;
}

# ---- 发现块解析 / 证据归一（Tier A）----

# 证据行归一化（步骤顺序不得调整，保证同一线证据在所有消费方归一结果逐字节相同）：
# 去 CRLF → 去缩进 → 剥掉一个 diff 前缀（+/-，空格前缀已随缩进去除）→ 再去首尾空白。
sub norm_line {
  my $l = shift // "";
  $l =~ s/\r$//;
  $l =~ s/^\s+//;
  $l =~ s/^[-+]?//;
  $l =~ s/^\s+//;
  $l =~ s/\s+$//;
  return $l;
}

# 连续空白折叠为单空格，再去首尾空白。
sub collapse_ws {
  my $s = shift // "";
  $s =~ s/\s+/ /g;
  $s =~ s/^\s+//;
  $s =~ s/\s+$//;
  return $s;
}

# 表头第一个 [...] 内层文本（内部连续空白折叠为单空格）；缺失为 ""。
sub parse_dim_tag {
  my ($hdr) = @_;
  return "" unless $hdr =~ /\[([^\]]*)\]/;
  my $tag = collapse_ws($1);
  return $tag // "";
}

# 表头维度信息：(是否含方括号, 折叠后标签)。缺失方括号返回 (0, "")。
sub dim_info {
  my $hdr = shift // "";
  return (0, "") unless $hdr =~ /\[([^\]]*)\]/;
  return (1, collapse_ws($1));
}

# 同轮路径口径：块内第一条「- 文件：」行。保留原字节（不做相对化/大小写归一），
# 仅 trim 并统一 "\\" 为 "/"，再剥掉结尾一个半角/全角 ":数字" 点锚；区间锚
# ":N-M" 的冒号后不是纯数字到行尾，正则整体不匹配，路径原样保留
# （tests/core/test_core_lib_findings.sh 断言的历史行为）。
# 无「- 文件：」行返回 ""。
sub first_location_path {
  for (@_) {
    next unless /^-\s*文件：\s*(.*)$/;
    my $p = $1;
    $p =~ s/^\s+//;
    $p =~ s/\s+$//;
    return "" unless length $p;
    $p =~ s!\\!/!g;
    ($p =~ s/:([0-9]+)$//) || ($p =~ s/：([0-9]+)$//);
    return $p;
  }
  return "";
}

# 跨轮路径口径（compare 专用）：trim → 反斜杠统一为正斜杠 → 剥结尾点/区间行号锚
# （:N / ：N / :N-M / ：N-M 全剥——跨轮报告的引用方式会在点/区间之间漂移）。
# 与 first_location_path 有意不同，不得合并。
sub compare_path {
  my $v = shift // "";
  $v =~ s/^\s+//;
  $v =~ s/\s+$//;
  return "" unless length $v;
  $v =~ s!\\!/!g;
  $v =~ s/[:：]\d+-\d+$//;
  $v =~ s/[:：]\d+$//;
  return $v;
}

# 证据 = 传入行里第一个闭合围栏代码块（围栏行允许缩进/带语言标记）的非空归一化行，
# 按原顺序返回；未闭合围栏或内容全空返回空列表。传入行应为发现块的“体”行
# （不含表头；表头行永不匹配围栏，混入也不影响结果）。
sub evidence_lines {
  my ($open, $close);
  for my $i (0 .. $#_) {
    my $t = $_[$i];
    $t =~ s/^\s+//;
    $t =~ s/\s+$//;
    next unless $t =~ /^```/;
    if (!defined $open) { $open = $i; }
    else { $close = $i; last; }
  }
  return () unless defined $open && defined $close && $close > $open;
  my @ev;
  for my $i (($open + 1) .. ($close - 1)) {
    my $n = norm_line($_[$i]);
    push @ev, $n if length $n;
  }
  return @ev;
}

# 注意必须先接进数组再取 scalar：`scalar evidence_lines(@_)` 在无闭合围栏时会得到
# undef（空列表 return 在标量上下文为 undef），而历史实现返回 0。
sub evidence_count { my @ev = evidence_lines(@_); return scalar @ev; }

# 发现块边界状态机（五个报告后处理脚本共用）：
# 表头 = ^### (P0-3|待确认)（后跟词界/空白/竖线）；块终于 ^## / ^###。
sub is_issue_heading {
  my ($l) = @_;
  return $l =~ /^###\s+(?:P[0-3]|待确认)(?:\b|\s|\|)/;
}

sub is_block_terminator {
  my ($l) = @_;
  return $l =~ /^##\s+/ || $l =~ /^###\s+/;
}

# 内容指纹（merge 跨批次去重 / SARIF partialFingerprints / compare 身份键同一公式）：
# sha256_hex(encode_utf8(文件路径 \0 维度标签 \0 归一化证据行))，行号不入键。
sub finding_fingerprint {
  my ($path, $dim, $evid) = @_;
  return sha256_hex(encode_utf8(join("\x00", $path, $dim, $evid)));
}

1;
