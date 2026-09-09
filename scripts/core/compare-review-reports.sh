#!/bin/bash
set -euo pipefail

# 跨轮报告对比（吸收自 OpenCodeReview v1.10.2 session compare，v1.11 系列持续验证）：
#   compare-review-reports.sh <CURR_REPORT> <PREV_REPORT> [--reviewed-from <coverage.json|manifest>]
#
# 修复-复审闭环（cc-code-reviewer → cc-code-fixer → 再审查）里，用户最关心的是
# 「上一轮的问题这轮怎么样了」。本脚本对两份本地 Markdown 报告做零 LLM 的确定性
# 四桶对比，把发现分为：
#   新增（new）        仅出现在本轮的发现；
#   仍存在（persisting）两轮都出现（多重集交集，逐键取 min(N,M)）；
#   已修复（resolved） 上轮存在、本轮消失，且其文件在本轮已审范围内；
#   未复审（not_reviewed）上轮存在、本轮消失，但其文件不在本轮已审范围——绝不计为
#                     已修复（对照全量报告 vs 差量复审时，这是本命令唯一能给错的答案）。
#
# 身份键（与跨批次去重 / SARIF partialFingerprints 同一族公式，行号不入键）：
#   sha256(文件路径 ␀ 维度标签 ␀ 归一化证据行)
#   - 文件路径：块内第一条「- 文件：」或「**位置**：」行，先只剥正式格式末尾的
#     「（同类问题共N处）」说明，再 trim → 反斜杠统一为正斜杠 → 剥结尾行号锚
#     （:N / ：N / :N-M / ：N-M 全剥——跨轮报告的引用方式会在点/区间之间漂移，这里
#     比同轮去重口径剥得更彻底）；无位置行的块路径为空串；
#   - 维度标签：表头第一个 [...] 内层文本（空白折叠）；缺失为空串；
#   - 证据行：第一个闭合围栏代码块逐行归一（去 CR → trim → 剥一个 +/- 前缀 →
#     再 trim → 去尾空白），空行全弃后按 "\n" 连接；无闭合围栏为空串。
#   优先级（P0-P3/待确认）刻意不入键：同一问题升级/降级判定为「仍存在」，
#   不应读成「旧的修好了、又冒出一个新的」。多重集语义：同键 N 条上轮、M 条
#   本轮 → min(N,M) 条仍存在，多出的一侧归新增/已修复侧。
#
# --reviewed-from（可选，已审范围来源，决定 not_reviewed 豁免）：
#   - run-manifest.json：取 coverage_sets.completed + coverage_sets.reused 的
#     path（含 old_path 变体）——阶段性合并报告只信 completed，与 merge 台账一致；
#   - review-input.json：取 items[].selected=true 的 path（单 agent 全程完成的口径）；
#   - 纯文本清单：每行一个路径。
#   路径比较 = trim + 反斜杠统一后的字节相等（清单路径与报告路径同为仓库相对路径）。
#   缺失/不可读/不可解析一律 fail-open 退化为三桶（未复审恒 0，其余照常）。
#
# stdout 契约（恒 8 行）：
#   COMPARE_REPORT_PATH=<CURR_REPORT 绝对路径>
#   COMPARE_CURR_FINDINGS=<本轮位置可解析发现块数>
#   COMPARE_PREV_FINDINGS=<上轮位置可解析发现块数>
#   COMPARE_NEW=<新增>
#   COMPARE_PERSISTING=<仍存在>
#   COMPARE_RESOLVED=<已修复>
#   COMPARE_NOT_REVIEWED=<未复审>
#   COMPARE_COVERAGE_SOURCE=none|review-input|run-manifest|manifest
#
# 报告改写（仅在有意义时）：本轮报告末尾追加「## 📊 与上轮报告对比」小节（对照
# 报告 / 匹配口径 / 四桶计数 / 覆盖来源），已存在同名小节先整体移除再重写（幂等，
# 重复运行字节稳定）；上轮解析不出任何有效块且报告原本无该小节时报告字节不动。
# 原子落盘（同目录临时文件 + rename），修改时保留原文件权限位。
#
# 用法/读入错误 exit 1（stderr 输出 ERROR_* 机器可 grep 标签）。

usage() {
  echo "用法: bash scripts/core/compare-review-reports.sh <CURR_REPORT> <PREV_REPORT> [--reviewed-from <coverage.json|manifest>]" >&2
}

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
  echo "ERROR_INVALID_ARGS=参数须为 <CURR_REPORT> <PREV_REPORT> [--reviewed-from <path>]" >&2
  usage
  exit 1
fi

CURR_REPORT="${1:?}"
PREV_REPORT="${2:?}"
shift 2

REVIEWED_FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reviewed-from)
      if [ $# -lt 2 ]; then
        echo "ERROR_INVALID_ARGS=--reviewed-from 缺少取值" >&2
        usage
        exit 1
      fi
      REVIEWED_FROM="$2"
      shift 2
      ;;
    *)
      echo "ERROR_UNKNOWN_OPTION=$1" >&2
      usage
      exit 1
      ;;
  esac
done

[ -f "$CURR_REPORT" ] || { echo "ERROR_CURR_NOT_FOUND=$CURR_REPORT" >&2; exit 1; }
[ -r "$CURR_REPORT" ] || { echo "ERROR_CURR_NOT_READABLE=$CURR_REPORT" >&2; exit 1; }
[ -f "$PREV_REPORT" ] || { echo "ERROR_PREV_NOT_FOUND=$PREV_REPORT" >&2; exit 1; }
[ -r "$PREV_REPORT" ] || { echo "ERROR_PREV_NOT_READABLE=$PREV_REPORT" >&2; exit 1; }
if [ -n "$REVIEWED_FROM" ] && { [ ! -f "$REVIEWED_FROM" ] || [ ! -r "$REVIEWED_FROM" ]; }; then
  # 辅助输入缺失属降级而非用法错误：warn 后按无覆盖来源继续。
  echo "WARN_REVIEWED_FROM_UNREADABLE=$REVIEWED_FROM" >&2
  REVIEWED_FROM=""
fi
CURR_REPORT="$(cd "$(dirname "$CURR_REPORT")" && pwd -P)/$(basename "$CURR_REPORT")"
PREV_BASENAME="$(basename "$PREV_REPORT")"
PREV_REPORT="$(cd "$(dirname "$PREV_REPORT")" && pwd -P)/$(basename "$PREV_REPORT")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

perl -I "$LIB_DIR" -MCCR::Findings=:all -Mutf8 -MEncode=decode,encode,FB_CROAK,LEAVE_SRC -MJSON::PP -MDigest::SHA=sha256_hex -e '
  use strict; use warnings;
  binmode STDOUT, ":utf8";
  my $tmpfile = "";
  END { unlink $tmpfile if length $tmpfile && -e $tmpfile; }

  # 发现内核（scripts/core/lib/CCR/Findings.pm）：to_chars / slurp_raw / read_text /
  # collapse_ws / norm_line / parse_dim_tag / evidence_lines / compare_path /
  # 块边界判定 / finding_fingerprint 的唯一实现；read_text 的 die 标签传入完整
  # 历史标签（"ERROR_<label>_READ"），stderr 逐字节不变。compare_path 的跨轮
  # 剥锚口径（点/区间全剥，与同轮 first_location_path 有意不同）见本文件头部
  # 「身份键」契约与 Findings.pm 内注释。
  sub block_key {
    my ($hdr, $body) = @_;
    my $dim = parse_dim_tag($hdr);
    my $path = "";
    for my $bl (@$body) {
      my $raw_path;
      if ($bl =~ /^-\s*文件：\s*(.*)$/) {
        $raw_path = $1;
      } elsif ($bl =~ /^\*\*位置\*\*：\s*(.*)$/) {
        $raw_path = $1;
      } else {
        next;
      }
      # 仅处理权威格式约定的末尾聚合说明，避免泛化剥离括号而损伤合法路径。
      $raw_path =~ s/\s*（同类问题共[0-9]+处）\s*$//;
      $path = compare_path($raw_path);
      last;
    }
    my @ev = evidence_lines(@$body);
    my $evid = @ev ? join("\n", @ev) : "";
    # 发现身份与四桶计数只接受完整块：没有可比较路径或有效闭合证据时，
    # 既不能可靠匹配，也不能据此宣称“已修复”。
    return undef unless length $path && length $evid;
    return { key => finding_fingerprint($path, $dim, $evid), path => $path };
  }
  # 发现块切分：is_issue_heading / is_block_terminator 统一在发现内核。
  sub collect_blocks {
    my @lines = @{ $_[0] };
    my (@blocks, @block, $in);
    for my $l (@lines) {
      if (is_issue_heading($l)) {
        if ($in) { push @blocks, [@block]; @block = (); }
        @block = ($l); $in = 1; next;
      }
      if ($in) {
        if (is_block_terminator($l)) { push @blocks, [@block]; @block = (); $in = 0; next; }
        push @block, $l; next;
      }
    }
    push @blocks, [@block] if $in;
    return @blocks;
  }

  my ($curr_report, $prev_report, $prev_basename, $reviewed_from) = map { to_chars($_) } @ARGV;

  # ---- 已审范围（fail-open：任何解析失败都退化为无覆盖来源） ----
  my %reviewed = ();
  my $cov_source = "none";
  if (length $reviewed_from) {
    my $rf = read_text($reviewed_from, "ERROR_REVIEWED_FROM_READ");
    my $trimmed = $rf;
    $trimmed =~ s/^\s+//;
    $trimmed =~ s/\s+$//;
    my $parsed = eval {
      if ($trimmed =~ /^\{/) {
        # decode_json 需要 UTF-8 字节；read_text 可能已解码为字符，先按需回编码。
        my $raw_json = utf8::is_utf8($rf) ? encode("UTF-8", $rf) : $rf;
        my $d = decode_json($raw_json);
        if (ref($d) eq "HASH" && exists $d->{coverage_sets}) {
          return undef unless ref($d->{coverage_sets}) eq "HASH";
          return undef unless ref($d->{coverage_sets}{completed}) eq "ARRAY"
            && ref($d->{coverage_sets}{reused}) eq "ARRAY";
          for my $set (qw(completed reused)) {
            my $arr = $d->{coverage_sets}{ $set };
            for my $it (@$arr) {
              next unless ref($it) eq "HASH";
              for my $k (qw(path old_path)) {
                next unless defined $it->{ $k } && length $it->{ $k };
                my $p = compare_path($it->{ $k });
                $reviewed{ $p } = 1 if length $p;
              }
            }
          }
          return "run-manifest";
        }
        if (ref($d) eq "HASH" && exists $d->{items}) {
          return undef unless ref($d->{items}) eq "ARRAY";
          for my $it (@{ $d->{items} }) {
            next unless ref($it) eq "HASH" && $it->{selected};
            # rename 项同时收 path 与 old_path：上轮发现引用旧路径时不算未复审。
            for my $fld (qw(path old_path)) {
              next unless defined $it->{ $fld } && length $it->{ $fld };
              my $p = compare_path($it->{ $fld });
              $reviewed{ $p } = 1 if length $p;
            }
          }
          return "review-input";
        }
        # 以 JSON 对象开头却不符合受支持 schema 的覆盖输入，不能降格解释为
        # 纯文本路径清单；否则损坏/版本不兼容文件会制造虚假的覆盖范围。
        return undef;
      }
      my @paths;
      for my $l (split /\n/, $rf, -1) {
        $l =~ s/^\s+//;
        $l =~ s/\s+$//;
        next unless length $l;
        my $p = compare_path($l);
        push @paths, $p if length $p;
      }
      $reviewed{ $_ } = 1 for @paths;
      return "manifest";
    };
    if (defined $parsed && length $parsed) { $cov_source = $parsed; }
    else { %reviewed = (); $cov_source = "none"; }
  }

  # ---- 两轮报告解析与多重集匹配 ----
  my $prev_text = read_text($prev_report, "ERROR_PREV_REPORT_READ");
  $prev_text =~ s/\r\n/\n/g;
  my @plines = split /\n/, $prev_text, -1;
  pop @plines if @plines && $plines[-1] eq "";
  my @prev_blocks = collect_blocks(\@plines);
  my @prev = grep { defined $_ }
    map { block_key($_->[0], [ @{ $_ }[1 .. $#$_] ]) } @prev_blocks;

  my $curr_text = read_text($curr_report, "ERROR_CURR_REPORT_READ");
  $curr_text =~ s/\r\n/\n/g;
  my @clines = split /\n/, $curr_text, -1;
  pop @clines if @clines && $clines[-1] eq "";
  my @curr_blocks = collect_blocks(\@clines);
  my @curr = grep { defined $_ }
    map { block_key($_->[0], [ @{ $_ }[1 .. $#$_] ]) } @curr_blocks;

  my %prev_cnt;
  $prev_cnt{ $_->{key} }++ for @prev;
  my %curr_cnt;
  $curr_cnt{ $_->{key} }++ for @curr;

  # 仍存在 = 逐键 min(N,M)：本轮按首次出现次序在前 min 个同键块上消耗配额（确定性）。
  my (%prev_used) = ();
  my ($new_cnt, $persist_cnt, $resolved_cnt, $not_reviewed_cnt) = (0, 0, 0, 0);
  for my $f (@curr) {
    my $k = $f->{key};
    my $matched_limit = ($curr_cnt{ $k } < ($prev_cnt{ $k } // 0)) ? $curr_cnt{ $k } : ($prev_cnt{ $k } // 0);
    if (($prev_used{ $k } // 0) < $matched_limit) {
      $prev_used{ $k }++;
      $persist_cnt++;
    } else {
      $new_cnt++;
    }
  }
  for my $f (@prev) {
    my $k = $f->{key};
    if (($prev_used{ $k } // 0) > 0) { $prev_used{ $k }--; next; }   # 已配对为仍存在
    # 上轮剩余：文件不在本轮已审范围 → 未复审（不计已修复）；无路径的块无法豁免。
    if ($cov_source ne "none" && length $f->{path} && !$reviewed{ $f->{path} }) {
      $not_reviewed_cnt++;
    } else {
      $resolved_cnt++;
    }
  }

  # ---- 小节改写：移除旧「## 📊 与上轮报告对比」→ 需要时在末尾重写 ----
  my $SECTION_HEADER = "## 📊 与上轮报告对比";
  my @out;
  my $in_section = 0;
  my $had_section = 0;
  for my $l (@clines) {
    if ($l =~ /^\Q$SECTION_HEADER\E\s*$/) { $in_section = 1; $had_section = 1; next; }
    if ($in_section) {
      if ($l =~ /^##\s+/) { $in_section = 0; } else { next; }
    }
    push @out, $l;
  }

  my $write_needed = 0;
  if (@prev || $had_section) {
    # 末尾收敛为恰好一个空行分隔，再追加小节（幂等：重复运行字节稳定）。
    pop @out while @out && $out[-1] eq "";
    push @out, "";
    push @out, $SECTION_HEADER;
    push @out, "";
    push @out, "- 对照报告：$prev_basename";
    push @out, "- 匹配口径：文件 × 维度 × 证据代码内容指纹（行号不入键；措辞漂移与重排版不影响判定）";
    push @out, "- 上轮发现 " . scalar(@prev) . " 条 → 本轮发现 " . scalar(@curr) . " 条";
    push @out, "- 新增：$new_cnt 条";
    push @out, "- 仍存在：$persist_cnt 条";
    push @out, "- 已修复：$resolved_cnt 条";
    push @out, "- 未复审（其文件不在本轮已审范围，不计为已修复）：$not_reviewed_cnt 条";
    push @out, "- 已审范围来源：$cov_source" if $cov_source ne "none";
    $write_needed = 1;
  }

  if ($write_needed) {
    my $newtext = join("\n", @out);
    $newtext =~ s/\n+\z/\n/;
    $tmpfile = "$curr_report.compare.$$";
    my @st = stat($curr_report);
    open my $of, ">:raw", $tmpfile or die "ERROR_TMP_WRITE=$tmpfile: $!\n";
    print {$of} encode("UTF-8", $newtext) or die "ERROR_TMP_WRITE=$tmpfile: $!\n";
    close $of or die "ERROR_TMP_WRITE=$tmpfile: $!\n";
    chmod((@st ? $st[2] & 07777 : 0644), $tmpfile);
    rename($tmpfile, $curr_report) or die "ERROR_RENAME=$curr_report: $!\n";
    $tmpfile = "";
  }

  print "COMPARE_REPORT_PATH=$curr_report\n";
  print "COMPARE_CURR_FINDINGS=" . scalar(@curr) . "\n";
  print "COMPARE_PREV_FINDINGS=" . scalar(@prev) . "\n";
  print "COMPARE_NEW=$new_cnt\n";
  print "COMPARE_PERSISTING=$persist_cnt\n";
  print "COMPARE_RESOLVED=$resolved_cnt\n";
  print "COMPARE_NOT_REVIEWED=$not_reviewed_cnt\n";
  print "COMPARE_COVERAGE_SOURCE=$cov_source\n";
' "$CURR_REPORT" "$PREV_REPORT" "$PREV_BASENAME" "$REVIEWED_FROM"
