#!/bin/bash
set -euo pipefail

# SARIF v2.1.0 导出：把审查报告 Markdown 中的发现块（`### P0-P3/待确认 | [维度] 标题`）
# 确定性转换为 CI 可消费的 SARIF JSON（GitHub Code Scanning 兼容），零 LLM。
#
#   bash scripts/core/export-sarif.sh <REPORT_MD> <OUTPUT_SARIF> [--project-name <name>]
#
# 契约：
# - 发现块切分与证据/路径/指纹口径统一在发现内核 scripts/core/lib/CCR/Findings.pm
#   （与 merge-batch-results.sh / relocate-findings.sh / compare-review-reports.sh /
#   mark-repeat-findings.sh 同源）：表头 `^###\s+(?:P[0-3]|待确认)(?:\b|\s|\|)`，
#   块在下一个 `^##`/`^###` 处结束。
# - partialFingerprints["ccCodeReviewer/v1"] = finding_fingerprint，与 merge 跨批次
#   去重指纹同一实现：sha256_hex(encode_utf8(文件路径 \0 维度标签 \0 归一化证据行))
#   ——路径仅 trim 并统一 "\\" 为 "/" 再剥结尾一个半/全角 ":数字"（区间行号不剥，
#   与 merge 口径一致）；证据行归一 = 去 CR → trim → 剥一个 +/- 前缀 → 再 trim →
#   去尾空白，空行全弃后按 "\n" 连接。
#   两处对同一发现块必须产出同一身份键（tests/core/test_core_export_sarif.sh 交叉验证）。
# - level 映射：P0→error、P1→warning、P2/P3/待确认→note。
# - ruleId = 维度标签内层文本（空白折叠）；缺失为 unknown-dimension；rules 数组为实际
#   出现过的去重集合，按字节序排序（确定性）。
# - 无 `- 文件：` 行的块 locations 为 []（SARIF 允许无位置结果，message 携带标题，
#   导出绝不丢发现）；有文件行但行号不可解析时保留 artifactLocation、省略 region。
# - stdout 单行 `SARIF_EXPORTED=<abs> RESULTS=<n> RULES=<m>`；成功 exit 0。
# - 用法/读入/输出目录错误 exit 1，stderr 输出 `ERROR_*` 机器可 grep 标签。
# - 输出原子落盘（tmp+rename）、UTF-8、恰好一个结尾换行；JSON::PP canonical + 2 空格
#   缩进保证字节级确定性。

usage() {
  echo "用法: bash scripts/core/export-sarif.sh <REPORT_MD> <OUTPUT_SARIF> [--project-name <name>]" >&2
}

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
  echo "ERROR_INVALID_ARGS=参数须为 <REPORT_MD> <OUTPUT_SARIF> [--project-name <name>]" >&2
  usage
  exit 1
fi

REPORT_MD="$1"
OUTPUT_SARIF="$2"
shift 2

PROJECT_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-name)
      if [ $# -lt 2 ]; then
        echo "ERROR_INVALID_ARGS=--project-name 缺少取值" >&2
        usage
        exit 1
      fi
      PROJECT_NAME="$2"
      shift 2
      ;;
    *)
      echo "ERROR_UNKNOWN_OPTION=$1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ ! -f "$REPORT_MD" ]; then
  echo "ERROR_REPORT_NOT_FOUND=$REPORT_MD" >&2
  exit 1
fi
if [ ! -r "$REPORT_MD" ]; then
  echo "ERROR_REPORT_NOT_READABLE=$REPORT_MD" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_SARIF")"
if [ ! -d "$OUTPUT_DIR" ]; then
  if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
    echo "ERROR_OUTPUT_DIR_NOT_CREATABLE=$OUTPUT_DIR" >&2
    exit 1
  fi
fi
if [ ! -w "$OUTPUT_DIR" ]; then
  echo "ERROR_OUTPUT_DIR_NOT_WRITABLE=$OUTPUT_DIR" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
VERSION_FILE="$(cd "$SCRIPT_DIR/../.." && pwd)/VERSION"
TOOL_VERSION="unknown"
if [ -r "$VERSION_FILE" ]; then
  TOOL_VERSION="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' < "$VERSION_FILE")"
fi

perl -I "$LIB_DIR" -MCCR::Findings=:all -Mutf8 -MEncode=decode,encode,encode_utf8,FB_CROAK,LEAVE_SRC -MJSON::PP -MDigest::SHA=sha256_hex -MCwd=abs_path -e '
  use strict; use warnings;

  my $tmpfile = "";
  END { unlink $tmpfile if length $tmpfile && -e $tmpfile; }

  # 发现内核（scripts/core/lib/CCR/Findings.pm）：to_chars / slurp_raw /
  # collapse_ws / norm_line / parse_dim_tag / first_location_path / evidence_lines /
  # 块边界判定 / finding_fingerprint 的唯一实现，与 merge 去重 / compare 对比 /
  # relocate / mark-repeat 同源同口径（本脚本传入的是已去换行的块体行；
  # merge 传入带换行的行，各正则对二者等价）。
  # argv 中的自由文本（--project-name / VERSION）按 UTF-8 解码；文件路径保持原字节。
  #
  # Security 稳定规则 ID（v1.7.2）：发现块携带 `**安全规则 ID**：CCR-NODE-*` 时
  # ruleId 用该稳定 ID（rules 条目标题取块标题、属性取插件 catalog），历史/非
  # Security 报告缺字段时回退维度标签——跨批/跨轮指纹身份不变（partialFingerprint
  # 仍用现有发现指纹公式）。

  my ($report_path, $output_path, $project_name, $tool_version, $catalog_path) = @ARGV;
  ($project_name, $tool_version) = map { to_chars($_) } ($project_name, $tool_version);

  # 插件 catalog（可选增强；缺失/不可读时 rules[].properties 降级省略）
  my %ccr_meta;
  if (defined($catalog_path) && length($catalog_path) && -r $catalog_path) {
    my $craw = slurp_raw($catalog_path);
    my $ctxt = eval { decode("UTF-8", $craw, FB_CROAK | LEAVE_SRC) } // $craw;
    my $cat = eval { JSON::PP->new->decode($ctxt) };
    if ($cat && ref($cat) eq "HASH" && ref($cat->{controls}) eq "ARRAY") {
      for my $c (@{ $cat->{controls} }) {
        my $st = $c->{standards} || {};
        $ccr_meta{ $c->{id} } = {
          standards => join("; ", grep { length } (
            (join(",", @{ $st->{owasp_top10} || [] }) ? "Top10:" . join(",", @{ $st->{owasp_top10} }) : ()),
            (join(",", @{ $st->{owasp_api_top10} || [] }) ? "APITop10:" . join(",", @{ $st->{owasp_api_top10} }) : ()),
            (join(",", @{ $st->{asvs} || [] }) ? "ASVS:" . join(",", @{ $st->{asvs} }) : ()),
            (@{ $st->{cwe} || [] } ? join(",", @{ $st->{cwe} }) : ()),
          )),
          detectability => ($c->{detectability} || {})->{primary} // "",
          category => $c->{category} // "",
        };
      }
    }
  }

  my $raw = slurp_raw($report_path);
  die "ERROR_REPORT_READ_FAILED=$report_path\n" unless defined $raw;
  my $text = eval { decode("UTF-8", $raw, FB_CROAK | LEAVE_SRC) };
  $text = defined($text) ? $text : $raw;   # 非 UTF-8 输入按字节兜底（fail-open）
  $text =~ s/\r\n/\n/g;
  my @lines = split /\n/, $text, -1;
  pop @lines if @lines && $lines[-1] eq "";

  # ---- 发现块切分：块边界状态机统一在 scripts/core/lib/CCR/Findings.pm ----
  my @blocks;
  my (@block, $in_issue);
  sub flush_block {
    return unless $in_issue;
    push @blocks, { header => $block[0], body => [ @block[1 .. $#block] ] };
    @block = ();
    $in_issue = 0;
  }
  for my $l (@lines) {
    if (is_issue_heading($l)) {
      flush_block();
      @block = ($l); $in_issue = 1; next;
    }
    if ($in_issue) {
      if (is_block_terminator($l)) { flush_block(); next; }
      push @block, $l; next;
    }
  }
  flush_block();

  my @results;
  my %rule_seen;
  my %rule_title;   # CCR-NODE-* 规则 ID → 首个块标题（shortDescription 用）
  for my $b (@blocks) {
    my $header = $b->{header};
    my @body = @{ $b->{body} };

    my ($prio) = $header =~ /^###\s+(P[0-3]|待确认)/;
    my $level = !defined($prio) ? "note"
              : $prio eq "P0" ? "error"
              : $prio eq "P1" ? "warning"
              : "note";

    my $dim = parse_dim_tag($header);
    my $rule_id = length($dim) ? $dim : "unknown-dimension";
    # Security 稳定规则 ID：块内显式声明时优先于维度标签
    my ($sec_rule) = grep { defined } map { /^(?:-\s*)?\*\*安全规则 ID\*\*：\s*(CCR-NODE-[A-Z0-9]+-[0-9]{3})\s*$/ ? $1 : undef } @body;
    $rule_id = $sec_rule if defined $sec_rule;
    $rule_seen{$rule_id} = 1;

    # 标题：剥 `###` 前缀、优先级 token、可选问题编号（P0-1 / 待确认-N）、
    # 可选分隔竖线与可选 [维度] 前缀；其余字节原样保留（含（上轮已报）等后缀）。
    my $rest = $header;
    $rest =~ s/^###\s+//;
    $rest =~ s/^(?:P[0-3]|待确认)//;
    $rest =~ s/^[ \t]*//;
    $rest =~ s/^-\d+\s*//;
    $rest =~ s/^\|\s*//;
    $rest =~ s/^\[[^\]]*\]\s*//;
    $rest =~ s/^\s+//;
    $rest =~ s/\s+$//;
    my $title = $rest;

    # 建议 = 第一条 `- 建议：` 行内容，截 500 字符。
    my $advice = "";
    for my $bl (@body) {
      next unless $bl =~ /^-\s*建议：\s*(.*)$/;
      $advice = $1;
      $advice =~ s/^\s+//;
      $advice =~ s/\s+$//;
      last;
    }
    $advice = substr($advice, 0, 500) if length($advice) > 500;

    # 证据状态（Security 块可选字段；缺失省略）
    my $evidence_status = "";
    for my $bl (@body) {
      next unless $bl =~ /^(?:-\s*)?\*\*证据状态\*\*：\s*(\S.*?)\s*$/;
      $evidence_status = $1;
      last;
    }
    # 规则 ID 与标题（供 CCR 规则条目 shortDescription/properties 使用）
    my $sec_rule_id = "";
    for my $bl (@body) {
      next unless $bl =~ /^(?:-\s*)?\*\*安全规则 ID\*\*：\s*(CCR-NODE-[A-Z0-9]+-[0-9]{3})\s*$/;
      $sec_rule_id = $1;
      last;
    }
    $rule_title{$sec_rule_id} = $title if length($sec_rule_id) && !exists($rule_title{$sec_rule_id});
    my $message_text = length($title) && length($advice) ? "$title — $advice"
                    : length($title)                    ? $title
                    :                                     $advice;

    # 位置 = 第一条 `- 文件：` 行；支持 path:N / path:N-M / 全角冒号；无行号时仅保留 uri。
    my ($have_loc, $loc_raw) = (0, "");
    for my $bl (@body) {
      next unless $bl =~ /^-\s*文件：\s*(.*)$/;
      $loc_raw = $1; $have_loc = 1; last;
    }
    my ($uri, $start_line, $end_line) = ("", 0, 0);
    if ($have_loc) {
      my $v = $loc_raw;
      $v =~ s/^\s+//;
      $v =~ s/\s+$//;
      if (length $v) {
        if    ($v =~ /^(.*):(\d+)-(\d+)$/)  { ($uri, $start_line, $end_line) = ($1, $2, $3); }
        elsif ($v =~ /^(.*)：(\d+)-(\d+)$/) { ($uri, $start_line, $end_line) = ($1, $2, $3); }
        elsif ($v =~ /^(.*):(\d+)$/)        { ($uri, $start_line) = ($1, $2); }
        elsif ($v =~ /^(.*)：(\d+)$/)       { ($uri, $start_line) = ($1, $2); }
        else                                { $uri = $v; }
        $uri =~ s/^\s+//;
        $uri =~ s/\s+$//;
      }
    }

    # 指纹：finding_fingerprint（发现内核唯一实现，与 merge 去重键同公式；
    # 维度缺失时指纹内为空串，不代入 unknown-dimension）。
    my $fp_path = first_location_path(@body);
    my @ev = evidence_lines(@body);
    my $evid = @ev ? join("\n", @ev) : "";
    my $fp = finding_fingerprint($fp_path, $dim, $evid);

    push @results, {
      rule_id => $rule_id,
      level => $level,
      message_text => $message_text,
      uri => $uri,
      have_uri => ($have_loc && length($uri)) ? 1 : 0,
      start_line => $start_line,
      end_line => $end_line,
      fingerprint => $fp,
      sec_rule_id => $sec_rule_id,
      title => $title,
      evidence_status => $evidence_status,
    };
  }

  # rules = 实际出现的去重集合，按 UTF-8 字节序排序（确定性）。
  # CCR-NODE-* 条目：shortDescription 取块标题，properties 来自插件 catalog
  # （standards / detectability / category；catalog 不可读或 ID 未收录时省略）。
  my @rule_ids = sort { encode_utf8($a) cmp encode_utf8($b) } keys %rule_seen;
  my %rule_index = map { $rule_ids[$_] => $_ } 0 .. $#rule_ids;
  my @rules = map {
    if (/^CCR-NODE-/) {
      my %r = ( id => $_, shortDescription => { text => ($rule_title{$_} || $_) } );
      if (my $m = $ccr_meta{$_}) {
        my %props;
        $props{standards} = $m->{standards} if length $m->{standards};
        $props{detectability} = $m->{detectability} if length $m->{detectability};
        $props{securityCategory} = $m->{category} if length $m->{category};
        $r{properties} = \%props if %props;
      }
      \%r;
    } else {
      { id => $_, shortDescription => { text => "$_ 审查发现" } };
    }
  } @rule_ids;

  my @json_results;
  for my $r (@results) {
    my @locations;
    if ($r->{have_uri}) {
      my %phys = (artifactLocation => { uri => $r->{uri} });
      if ($r->{start_line} && $r->{start_line} > 0) {
        my %region = (startLine => $r->{start_line} + 0);
        $region{endLine} = $r->{end_line} + 0 if $r->{end_line} && $r->{end_line} > 0;
        $phys{region} = \%region;
      }
      push @locations, { physicalLocation => \%phys };
    }
    my %result = (
      ruleId => $r->{rule_id},
      level => $r->{level},
      ruleIndex => $rule_index{ $r->{rule_id} },
      message => { text => $r->{message_text} },
      locations => \@locations,
      partialFingerprints => { "ccCodeReviewer/v1" => $r->{fingerprint} },
    );
    $result{properties} = { evidenceStatus => $r->{evidence_status} } if length($r->{evidence_status});
    push @json_results, \%result;
  }

  my $run = {
    tool => { driver => {
      name => "cc-code-reviewer",
      version => $tool_version,
      informationUri => "https://github.com/ataskite/cc-code-reviewer",
      rules => \@rules,
    } },
    results => \@json_results,
  };
  $run->{properties} = { projectName => $project_name } if length $project_name;

  my $sarif = {
    "\$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
    version => "2.1.0",
    runs => [$run],
  };

  my $json_text = JSON::PP->new->canonical->pretty->indent_length(2)->space_before(0)->encode($sarif);
  $json_text =~ s/\n?\z/\n/;   # 恰好一个结尾换行

  $tmpfile = "$output_path.sarif-tmp.$$";
  open my $of, ">:raw", $tmpfile or die "ERROR_TMP_WRITE=$tmpfile: $!\n";
  print {$of} encode_utf8($json_text) or die "ERROR_TMP_WRITE=$tmpfile: $!\n";
  close $of or die "ERROR_TMP_WRITE=$tmpfile: $!\n";
  chmod 0644, $tmpfile;
  rename($tmpfile, $output_path) or die "ERROR_RENAME=$output_path: $!\n";
  $tmpfile = "";

  my $abs_out = abs_path($output_path);
  $abs_out = $output_path unless defined $abs_out;
  print "SARIF_EXPORTED=$abs_out RESULTS=" . scalar(@json_results) . " RULES=" . scalar(@rules) . "\n";
' "$REPORT_MD" "$OUTPUT_SARIF" "$PROJECT_NAME" "$TOOL_VERSION" "$(cd "$SCRIPT_DIR/../.." && pwd)/references/security/catalog/node-security-controls.json" || exit 1
# perl 任何 die（读入失败 / 临时文件写入 / rename 失败）统一归一为 exit 1，
# 保证对外只有 0（成功）与 1（用法/IO 错误）两个退出码。
