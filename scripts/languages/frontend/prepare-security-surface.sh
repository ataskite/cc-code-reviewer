#!/bin/bash
set -euo pipefail

# Node Security Surface 生成器（离线、确定性、零网络；仅候选导航，不是发现清单）：
#   bash scripts/languages/frontend/prepare-security-surface.sh \
#     <PROJECT_DIR> <REVIEW_INPUT_JSON> <SECURITY_CONTROLS_JSON> <OUTPUT_JSON>
#
# 成功 stdout 单行：
#   SECURITY_SURFACE_PATH=<abs> FILES=<n> ENTRIES=<n> SOURCES=<n> SINKS=<n> LIMITATIONS=<n>
#
# 强制边界：
# - 只读 REVIEW_INPUT_JSON 中 selected=true 的文件（服务端扩展名 .js/.mjs/.cjs/.ts/.tsx）；
#   正式范围外内容不扫描、不进入索引——需要时仅写 limitation。
# - 只建立候选位置（entry/identity/source/sink/control-signal），不做 Source→Sink 结论，
#   不产生 finding/severity 字段；命中不等于漏洞，也不得据此决定 P0。
# - 所有 excerpt 恰好一行、≤200 字符、疑似密钥只保留键名与 *** 掩码；
#   token/口令/私钥/连接串原值绝不进入输出 JSON。
# - 文件/行号/kind 排序稳定（路径字节序 → 行号 → kind 字节序），同输入两次运行字节一致。
# - 大文件（>2MB）或不可读文件写 limitation，不静默跳过。
# - 输出原子落盘，canonical JSON + 恰好一个结尾换行。

if [ $# -ne 4 ]; then
  echo "ERROR_SECURITY_SURFACE_USAGE=参数须为 <PROJECT_DIR> <REVIEW_INPUT_JSON> <SECURITY_CONTROLS_JSON> <OUTPUT_JSON>" >&2
  exit 1
fi

PROJECT_DIR="$1"
REVIEW_INPUT_JSON="$2"
SECURITY_CONTROLS_JSON="$3"
OUTPUT_JSON="$4"

[ -d "$PROJECT_DIR" ] || { echo "ERROR_SECURITY_SURFACE_PROJECT_DIR=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
[ -r "$REVIEW_INPUT_JSON" ] || { echo "ERROR_SECURITY_SURFACE_INPUT_NOT_READABLE=$REVIEW_INPUT_JSON" >&2; exit 1; }
[ -r "$SECURITY_CONTROLS_JSON" ] || { echo "ERROR_SECURITY_SURFACE_CONTROLS_NOT_READABLE=$SECURITY_CONTROLS_JSON" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../../core/lib/common.sh"   # sha256_file 三级回退链

# 仅当冻结 controls 声明了 Node profile 时才生成 surface（主 skill/规划器同样把关；
# 这里独立复核，防止误调用把纯前端项目误导向 Node 攻击面）。
HAS_NODE_PROFILE="$(perl -MJSON::PP -0777 -e '
  my $d = eval { decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f> }) };
  die "BAD\n" if $@ || ref($d) ne "HASH";
  my %p = map { $_ => 1 } @{ $d->{security_profile} // [] };
  print(($p{"node-api"} || $p{"node-bff"} || $p{"node-worker"}) ? "1" : "0");
' "$SECURITY_CONTROLS_JSON")" || { echo "ERROR_SECURITY_SURFACE_CONTROLS_INVALID=$SECURITY_CONTROLS_JSON" >&2; exit 1; }
if [ "$HAS_NODE_PROFILE" != "1" ]; then
  echo "ERROR_SECURITY_SURFACE_NO_NODE_PROFILE=security-controls.json 未启用任何 Node profile，不应生成攻击面" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_JSON")"
[ -d "$OUTPUT_DIR" ] || { echo "ERROR_SECURITY_SURFACE_OUTPUT_DIR=$OUTPUT_DIR" >&2; exit 1; }
[ -w "$OUTPUT_DIR" ] || { echo "ERROR_SECURITY_SURFACE_OUTPUT_DIR_NOT_WRITABLE=$OUTPUT_DIR" >&2; exit 1; }

REVIEW_INPUT_SHA256="$(sha256_file "$REVIEW_INPUT_JSON")"
TMP_OUT="${OUTPUT_JSON}.tmp.$$"
trap 'rm -f "$TMP_OUT"' EXIT

perl -MJSON::PP -MCwd=abs_path -MEncode=decode,FB_CROAK -e '
  use strict; use warnings;
  my ($project_dir, $input_path, $ri_sha, $tmp_out) = @ARGV;
  sub failx { my ($tag, $msg) = @_; print STDERR "ERROR_SECURITY_SURFACE_${tag}=${msg}\n"; exit 1; }
  binmode(STDERR, ":utf8");

  my $inp;
  { local $/; open my $fh, "<", $input_path or failx("INPUT_INVALID", $input_path); my $t = <$fh>;
    $inp = eval { decode_json($t) }; failx("INPUT_INVALID", "unparseable") if $@ || ref($inp) ne "HASH"; }
  my $items = $inp->{items};
  failx("INPUT_INVALID", "items[] missing") unless ref($items) eq "ARRAY";
  my $proj_abs = abs_path($project_dir) or failx("PROJECT_DIR", $project_dir);
  my @selected;
  for my $it (@$items) {
    next unless ref($it) eq "HASH" && ($it->{selected} // "") eq "true" && defined $it->{path};
    my $abs = abs_path($it->{path});
    failx("INPUT_SCOPE", "selected path outside PROJECT_DIR or missing: $it->{path}")
      unless defined($abs) && -e $abs && $abs =~ /^\Q$proj_abs\E(\/|$)/;
    push @selected, $abs;
  }

  # ---- 模式表：kind => [regex]。命中即产生候选（file,line,kind,excerpt）。----
  # excerpt 一律先脱敏再截断；不做任何跨行/跨文件推断。
  my @entry_pats = (
    ["http-route",        qr{\b(?:app|router|server|api|r)\s*\.\s*(?:get|post|put|patch|delete|all)\s*\(\s*["\x27]}],
    ["http-middleware",   qr{\b(?:app|router)\s*\.\s*use\s*\(}],
    ["server-listen",     qr{\.listen\s*\(|createServer\s*\(}],
    ["graphql-handler",   qr{graphql\s*\(|makeExecutableSchema|ApolloServer|graphqlHTTP}],
    ["websocket-handler", qr{new\s+WebSocket\.Server|WebSocketServer|\.on\s*\(\s*["\x27]connection["\x27]|io\s*\.\s*on\s*\(}],
    ["message-consumer",  qr{channel\s*\.\s*consume\s*\(|\.consume\s*\(|consumer\s*\.\s*(?:run|subscribe|connect)\s*\(|\.on\s*\(\s*["\x27]message["\x27]|webhook}],
  );
  my @identity_pats = (
    ["session-identity",  qr{req\s*\.\s*session\b|ctx\s*\.\s*session\b|express-session|cookie-session}],
    ["authorization-header", qr{headers\s*\[\s*["\x27]authorization["\x27]\s*\]|get\s*\(\s*["\x27]authorization["\x27]|authorization["\x27]\s*:|bearer\s}],
    ["jwt-usage",         qr{jsonwebtoken|jwt\s*\.\s*(?:verify|decode|sign)\s*\(}],
    ["client-identity-header", qr{headers\s*\[\s*["\x27]x-(?:user|uid|tenant|org|account)[^"\x27]*["\x27]|req\s*\.\s*headers\s*\.\s*(?:x[A-Z]|x-)}i],
    ["service-account-env", qr{process\s*\.\s*env\s*\.\s*[A-Z0-9_]*(?:TOKEN|SECRET|KEY|PASSWORD|CREDENTIAL)}],
  );
  my @source_pats = (
    ["request-body",      qr{req\s*\.\s*body\b|ctx\s*\.\s*(?:request\s*\.\s*)?body\b|event\s*\.\s*body\b}],
    ["request-query",     qr{req\s*\.\s*query\b|ctx\s*\.\s*(?:request\s*\.\s*)?query\b|queryStringParameters}],
    ["request-params",    qr{req\s*\.\s*params\b|ctx\s*\.\s*params\b}],
    ["request-headers",   qr{req\s*\.\s*headers\b|ctx\s*\.\s*(?:request\s*\.\s*)?headers\b|req\s*\.\s*get\s*\(\s*["\x27]}],
    ["request-cookies",   qr{req\s*\.\s*cookies\b|req\s*\.\s*signedCookies\b|cookie\s*\.\s*parse|\bcookies\s*\[}],
    ["message-payload",   qr{msg\s*\.\s*(?:payload|body|content|value)|message\s*\.\s*(?:payload|body|content|value)|job\s*\.\s*data\b|event\s*\.\s*Records}],
  );
  my @sink_pats = (
    ["db-write",          qr{insertOne\s*\(|insertMany\s*\(|updateOne\s*\(|updateMany\s*\(|deleteOne\s*\(|deleteMany\s*\(|findOneAndUpdate\s*\(|\.save\s*\(\s*\)|bulkWrite\s*\(}],
    ["db-query",          qr{\.find\s*\(|findOne\s*\(|findById\s*\(|aggregate\s*\(|\.collection\s*\(|where\s*\(\s*\{|\$query|\$where}],
    ["fs-access",         qr{fs\s*\.\s*(?:readFile|writeFile|appendFile|unlink|createReadStream|createWriteStream|readdir|stat)\b|(?:read|write)FileSync\s*\(|\.sendFile\s*\(|res\s*\.\s*download\s*\(}],
    ["child-process-exec", qr{child_process|\bexec\s*\(|execSync\s*\(|spawnSync\s*\(|execFile(?:Sync)?\s*\(|\.exec\s*\(|\.execSync\s*\(|\.spawn\s*\(|\.execFile\s*\(}],
    ["template-render",   qr{\.render\s*\(|ejs\.render|nunjucks|pug\s*\.|Mustache|handlebars\s*\.}],
    ["dynamic-code-eval", qr{\beval\s*\(|new\s+Function\s*\(}],
    ["deserialize-unsafe", qr{unserialize\s*\(|node-serialize|yaml\s*\.\s*load\s*\(|\.unserialize\s*\(|\.deserialize\s*\(|funcstream}],
    ["outbound-http",     qr{\bfetch\s*\(|\baxios\b|\bgot\s*\(|http\s*\.\s*request\s*\(|https\s*\.\s*request\s*\(|superagent|node-fetch|urllib\s*\.}],
    ["redirect-response", qr{res\s*\.\s*redirect\s*\(|ctx\s*\.\s*redirect\s*\(}],
    ["session-write",     qr{req\s*\.\s*session\s*(?:\.\w+|\[\s*["\x27][^\s"\x27]+["\x27]\s*\])\s*=|session\s*\.\s*(?:save|regenerate)\s*\(}],
  );
  my @control_pats = (
    ["schema-validation", qr{joi\.|\@hapi/joi|\bajv\b|\bzod\b|celebrate|\.validate\s*\(|validateAsync\s*\(}],
    ["allowlist",         qr{allowlist|whitelist|ALLOWLIST|allowedHosts|allowed_}],
    ["owner-tenant-binding", qr{owner(?:Id)?\s*[:=]|tenant(?:Id)?\s*[:=]|user_?id\s*[:=].*(?:req|session|ctx)|created_?by\s*[:=]}i],
    ["auth-middleware",   qr{requireAuth|ensureAuthenticated|isAuthenticated|authMiddleware|verifyToken|checkPermission|requireRole|isAdmin|can\s*\(|passport\s*\.|authenticate\s*\(}],
    ["csrf-control",      qr{csurf|csrfToken|_csrf|sameSite}],
    ["security-headers",  qr{helmet|X-Frame-Options|Content-Security-Policy|X-Content-Type-Options|hsts}],
    ["rate-limit",        qr{rateLimit|rate-limit|express-rate-limit|throttle\s*\(}],
  );

  # 脱敏：键名=值 形态的敏感赋值 → 键名=***；长随机串（≥32 的 base64/hex）→ ***
  # 非 UTF-8 行的 excerpt 退化为 ASCII（保持输出 JSON 字节确定）。
  sub mask_excerpt {
    my ($s) = @_;
    $s = eval { decode("UTF-8", $s, FB_CROAK) } // do { my $x = $s; $x =~ s/[^\x20-\x7E\t]/ /g; $x };    $s =~ s/((?:password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|authorization|auth|credential)[A-Za-z0-9_]*\s*[:=]\s*)(["\x27]?)[^\s"\x27,;)}{]{4,}\2/${1}***MASKED***/gi;
    $s =~ s/["\x27][A-Za-z0-9+\/=_-]{32,}["\x27]/***MASKED***/g;
    $s =~ s/(bearer\s+)[A-Za-z0-9._-]{8,}/${1}***MASKED***/gi;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    return length($s) > 200 ? substr($s, 0, 200) : $s;
  }

  my (@entries, @identity_sources, @request_sources, @sensitive_sinks, @outbound_clients, @config_signals, @limitations);
  my $files_scanned = 0;
  my $MAX_BYTES = 2 * 1024 * 1024;

  my @sorted = sort { $a cmp $b } @selected;
  for my $file (@sorted) {
    next unless $file =~ /\.(?:js|mjs|cjs|ts|tsx)$/;
    my $rel = $file;
    $rel =~ s/^\Q$proj_abs\E\///;
    if (!-r $file) {
      push @limitations, "unreadable file skipped: $rel";
      next;
    }
    my $size = -s $file;
    if ($size > $MAX_BYTES) {
      push @limitations, "file exceeds 2MB, skipped: $rel ($size bytes)";
      next;
    }
    $files_scanned++;
    open my $fh, "<", $file or do { push @limitations, "open failed: $rel"; next; };
    my $line_no = 0;
    my $saw_binary = 0;
    while (my $line = <$fh>) {
      $line_no++;
      last if $line_no > 20000;   # 单文件行数护栏：超出记 limitation
      if ($line =~ /\x00/) { $saw_binary = 1; last; }
      my $excerpt = mask_excerpt($line);
      for my $p (@entry_pats) {
        push @entries, { file => $rel, line => $line_no, kind => $p->[0], symbol_or_excerpt => $excerpt } if $line =~ $p->[1];
      }
      for my $p (@identity_pats) {
        push @identity_sources, { file => $rel, line => $line_no, kind => $p->[0], symbol_or_excerpt => $excerpt } if $line =~ $p->[1];
      }
      for my $p (@source_pats) {
        push @request_sources, { file => $rel, line => $line_no, kind => $p->[0], symbol_or_excerpt => $excerpt } if $line =~ $p->[1];
      }
      for my $p (@sink_pats) {
        if ($line =~ $p->[1]) {
          my %item = (file => $rel, line => $line_no, kind => $p->[0], symbol_or_excerpt => $excerpt);
          if ($p->[0] eq "outbound-http") { push @outbound_clients, \%item; }
          push @sensitive_sinks, \%item;
        }
      }
      for my $p (@control_pats) {
        push @config_signals, { file => $rel, line => $line_no, kind => $p->[0], symbol_or_excerpt => $excerpt } if $line =~ $p->[1];
      }
    }
    close $fh;
    push @limitations, "binary-like content skipped: $rel" if $saw_binary;
    push @limitations, "line cap reached (20000): $rel" if $line_no > 20000;
  }

  # 确定性排序：路径字节序 → 行号 → kind 字节序
  my $cmp_item = sub { my ($a, $b) = @_; $a->{file} cmp $b->{file} || $a->{line} <=> $b->{line} || $a->{kind} cmp $b->{kind} };
  for my $bucket (\@entries, \@identity_sources, \@request_sources, \@sensitive_sinks, \@outbound_clients, \@config_signals) {
    @$bucket = sort { $cmp_item->($a, $b) } @$bucket;
  }
  @limitations = sort @limitations;

  my $out = {
    schema_version      => 1,
    review_input_sha256 => $ri_sha,
    files_scanned       => $files_scanned,
    entries             => \@entries,
    identity_sources    => \@identity_sources,
    request_sources     => \@request_sources,
    sensitive_sinks     => \@sensitive_sinks,
    outbound_clients    => \@outbound_clients,
    config_signals      => \@config_signals,
    limitations         => \@limitations,
  };
  my $json = JSON::PP->new->canonical->allow_bignum->utf8->encode($out);
  open my $of, ">:raw", $tmp_out or failx("TMP_WRITE", $tmp_out);
  print {$of} $json, "\n";
  close $of or failx("TMP_WRITE", $tmp_out);
  printf STDERR "CCR_SURFACE_FILES=%d ENTRIES=%d SOURCES=%d SINKS=%d LIMITATIONS=%d\n",
    $files_scanned, scalar(@entries), scalar(@request_sources), scalar(@sensitive_sinks), scalar(@limitations);
' "$PROJECT_DIR" "$REVIEW_INPUT_JSON" "$REVIEW_INPUT_SHA256" "$TMP_OUT" || exit 1

mv -f "$TMP_OUT" "$OUTPUT_JSON"
trap - EXIT

STATS="$(perl -MJSON::PP -0777 -e '
  my $d = decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f> });
  printf "FILES=%d ENTRIES=%d SOURCES=%d SINKS=%d LIMITATIONS=%d",
    $d->{files_scanned}, scalar(@{$d->{entries}}), scalar(@{$d->{request_sources}}),
    scalar(@{$d->{sensitive_sinks}}), scalar(@{$d->{limitations}});
' "$OUTPUT_JSON")"
OUT_ABS="$(cd "$(dirname "$OUTPUT_JSON")" && pwd)/$(basename "$OUTPUT_JSON")"
printf 'SECURITY_SURFACE_PATH=%s %s\n' "$OUT_ABS" "$STATS"
