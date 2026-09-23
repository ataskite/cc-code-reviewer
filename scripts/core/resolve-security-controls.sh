#!/bin/bash
set -euo pipefail

# Security 适用控制解析器（离线、确定性、零网络）：
#   bash scripts/core/resolve-security-controls.sh <PROJECT_DIR> <PROJECT_TYPE> <REVIEW_INPUT_JSON> <OUTPUT_JSON>
#
# 成功 stdout 单行：
#   SECURITY_CONTROLS_PATH=<abs> SECURITY_PROFILES=<csv> CONTROLS=<n> CATALOG_SHA256=<sha256>
#
# 契约：
# - 只读 PROJECT_DIR 内配置与 REVIEW_INPUT_JSON 中 selected=true 的文件；不得联网。
# - 信号只决定「本轮要检查什么」（适用控制），绝不输出漏洞结论。
# - 输出原子落盘，JSON::PP canonical(utf8) + 恰好一个结尾换行；同输入两次运行字节
#   一致（无时间戳字段）。
# - fail closed：用法错误 / 输入 JSON 非法 / catalog 校验失败 / selected 路径越出
#   PROJECT_DIR / 输出目录不可写 → exit 1，stderr ERROR_SECURITY_RESOLVE_*。
# - catalog 默认位于插件 references/security/catalog/，可用
#   CC_CODE_REVIEWER_SECURITY_CATALOG 覆盖（测试/企业内嵌场景）。
#
# Profile 判定（信号词表封闭，见 references/security/control-catalog.md §4）：
# - node-api    = PROJECT_TYPE=node，或冻结输入存在 http-server 信号
# - node-bff    = node-api 成立 且 前端信号（.vue/.jsx/.tsx 文件或 vue/react 依赖）——
#                 前端项目的服务端层即 BFF；外发客户端词表未命中不代表不存在（封装/改名常见）
# - node-worker = worker-queue 信号（队列/任务/Webhook/消息消费）
# 控制适用性（保守语义）：控制 profiles ∩ 激活 profile 非空即适用。
# 信号只做两件事：导航（matched_signals 供 agent 优先取证）与确认（basis=signal-confirmed）；
# 信号未命中只降级为 basis=profile-default（保守保留），绝不构成排除——静态词表无法证明
# 不存在改名封装/跨文件实现（事故复现：Http.request 封装让 outbound-http-client 全部未命中）。
# 排除只发生在 profile 层（无服务端代码）。Agent 语义发现被排除控制的风险时可「语义提升」：
# 以 finding_confirmed 台账行 + 携带规则 ID 的问题块纳入（校验器按此放行）。

if [ $# -ne 4 ]; then
  echo "ERROR_SECURITY_RESOLVE_USAGE=参数须为 <PROJECT_DIR> <PROJECT_TYPE> <REVIEW_INPUT_JSON> <OUTPUT_JSON>" >&2
  exit 1
fi

PROJECT_DIR="$1"
PROJECT_TYPE="$2"
REVIEW_INPUT_JSON="$3"
OUTPUT_JSON="$4"

[ -d "$PROJECT_DIR" ] || { echo "ERROR_SECURITY_RESOLVE_PROJECT_DIR=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
[ -f "$REVIEW_INPUT_JSON" ] || { echo "ERROR_SECURITY_RESOLVE_INPUT_NOT_FOUND=$REVIEW_INPUT_JSON" >&2; exit 1; }
[ -r "$REVIEW_INPUT_JSON" ] || { echo "ERROR_SECURITY_RESOLVE_INPUT_NOT_READABLE=$REVIEW_INPUT_JSON" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"   # sha256_file 三级回退链

CATALOG="${CC_CODE_REVIEWER_SECURITY_CATALOG:-$(cd "$SCRIPT_DIR/../.." && pwd)/references/security/catalog/node-security-controls.json}"
[ -f "$CATALOG" ] || { echo "ERROR_SECURITY_RESOLVE_CATALOG_NOT_FOUND=$CATALOG" >&2; exit 1; }

# 先整体校验 catalog（含 upstream 绑定哈希与映射存在性），非法即 fail closed。
bash "$SCRIPT_DIR/validate-security-control-catalog.sh" "$CATALOG" >/dev/null

OUTPUT_DIR="$(dirname "$OUTPUT_JSON")"
[ -d "$OUTPUT_DIR" ] || { echo "ERROR_SECURITY_RESOLVE_OUTPUT_DIR=$OUTPUT_DIR" >&2; exit 1; }
[ -w "$OUTPUT_DIR" ] || { echo "ERROR_SECURITY_RESOLVE_OUTPUT_DIR_NOT_WRITABLE=$OUTPUT_DIR" >&2; exit 1; }

CATALOG_SHA256="$(sha256_file "$CATALOG")"
REVIEW_INPUT_SHA256="$(sha256_file "$REVIEW_INPUT_JSON")"
UPSTREAM_MANIFEST_SHA256="$(perl -MJSON::PP -0777 -e '
  my $d = eval { decode_json(do { local $/; open my $fh, "<", $ARGV[0] or die; <$fh> }) };
  die "NO_SHA\n" if $@ || ref($d) ne "HASH" || !$d->{upstream_manifest_sha256};
  print $d->{upstream_manifest_sha256}, "\n";
' "$CATALOG")" || { echo "ERROR_SECURITY_RESOLVE_CATALOG_INVALID=$CATALOG" >&2; exit 1; }

TMP_OUT="${OUTPUT_JSON}.tmp.$$"
trap 'rm -f "$TMP_OUT"' EXIT

perl -MJSON::PP -MCwd=abs_path -MFile::Spec -e '
  use strict; use warnings; use utf8;
  my ($project_dir, $project_type, $input_path, $catalog_path, $catalog_sha, $manifest_sha, $ri_sha, $tmp_out) = @ARGV;
  sub failx { my ($tag, $msg) = @_; print STDERR "ERROR_SECURITY_RESOLVE_${tag}=${msg}\n"; exit 1; }
  binmode(STDERR, ":utf8");

  # ---- 读取冻结输入：selected=true 且位于 PROJECT_DIR 内的文件 ----
  my $inp;
  { local $/; open my $fh, "<", $input_path or failx("INPUT_INVALID", "unreadable: $input_path"); my $t = <$fh>;
    $inp = eval { decode_json($t) }; failx("INPUT_INVALID", "unparseable json: $input_path") if $@ || ref($inp) ne "HASH"; }
  my $items = $inp->{items};
  failx("INPUT_INVALID", "items[] missing") unless ref($items) eq "ARRAY";
  my $proj_abs = abs_path($project_dir) or failx("PROJECT_DIR", $project_dir);
  my @selected;
  for my $it (@$items) {
    next unless ref($it) eq "HASH" && defined $it->{path} && length $it->{path};
    # selected 兼容 JSON 布尔（JSON::PP::Boolean 数值化）与字符串 "true"
    my $sel = $it->{selected};
    my $sel_ok = !defined($sel) ? 0
               : ref($sel)      ? ($sel ? 1 : 0)
               : (($sel eq "true" || $sel eq "1") ? 1 : 0);
    next unless $sel_ok;
    my $p = $it->{path};
    my $abs = File::Spec->file_name_is_absolute($p) ? abs_path($p) : abs_path(File::Spec->rel2abs($p, $proj_abs));
    failx("INPUT_SCOPE", "selected path outside PROJECT_DIR or missing: $p")
      unless defined($abs) && -e $abs && $abs =~ /^\Q$proj_abs\E(\/|$)/;
    push @selected, $abs;
  }

  # ---- 信号扫描（封闭词表；逐文件逐行正则，与 control-catalog.md §4 一致）----
  my %sig;
  my @sig_re = (
    ["http-server",        qr{require\s*\(\s*["\x27](?:express|koa|fastify|\@nestjs/core|hapi|\@hapi/hapi|egg)["\x27]\s*\)|from\s*["\x27](?:express|koa|fastify|\@nestjs/core|hapi|\@hapi/hapi|egg)["\x27]|express\s*\(\s*\)|\.listen\s*\(|createServer\s*\(|(?:router|app|server)\s*\.\s*(?:get|post|put|patch|delete|all|use)\s*\(|requestMapping|\@Controller\b|["\x27](?:express|koa|fastify|\@nestjs/core|egg)["\x27]\s*:\s*["\x27]}i],
    ["request-source",     qr{req\s*\.\s*(?:body|query|params|headers|cookies|files)\b|ctx\s*\.\s*(?:request\s*\.\s*)?(?:body|query|headers)\b|event\s*\.\s*(?:body|queryStringParameters)|(?:msg|message|payload)\s*\.\s*(?:body|payload|content|value)\b|request\s*\.\s*(?:body|query)\b}],
    ["outbound-http-client", qr{\bfetch\s*\(|\baxios\b|\bgot\s*\(|\bgot\s*\.\s*(?:get|post|put|delete|stream)|http\s*\.\s*request\s*\(|https\s*\.\s*request\s*\(|superagent|request-promise|node-fetch|urllib\s*\.}],
    ["session-usage",      qr{req\s*\.\s*session\b|ctx\s*\.\s*session\b|express-session|cookie-session|sessionStore|session\s*\.\s*(?:regenerate|destroy|save)\s*\(}],
    ["child-process",      qr{child_process|require\s*\(\s*["\x27]exec["\x27]|(?:\.|context\s*\.)?(?:exec|execSync|spawn|spawnSync|execFile(?:Sync)?)\s*\(\s*["\x27]}],
    ["fs-path-ops",        qr{fs\s*\.\s*(?:readFile|writeFile|appendFile|unlink|createReadStream|createWriteStream|readdir|stat)\b|(?:read|write)FileSync\s*\(|\.sendFile\s*\(|res\s*\.\s*download\s*\(|path\s*\.\s*(?:join|resolve)\s*\(}],
    ["deep-merge",         qr{deepmerge|\bmerge\s*\(|\.merge(?:With|Deep)?\s*\(|\bextend\s*\(|\.extend\s*\(|\.defaults(?:Deep)?\s*\(|\.assignIn\s*\(|Object\s*\.\s*assign\s*\(}],
    ["nosql-client",       qr{mongodb|mongoose|MongoClient|mongo\s*\.\s*connect|db\s*\.\s*collection\b}],
    ["deserialize-usage",  qr{node-serialize|unserialize\s*\(|yaml\s*\.\s*load\s*\(|\.unserialize\s*\(|\.deserialize\s*\(|funcstream}],
    ["worker-queue",       qr{kafkajs|amqplib|rabbitmq|bullmq|bee-queue|\bbull\b|\bagenda\b|node-cron|sqs-consumer|channel\s*\.\s*consume\s*\(|consumer\s*\.\s*(?:subscribe|run|connect)\s*\(|\.prefetch\s*\(|webhook}],
  );
  my $frontend_signal = 0;
  for my $file (@selected) {
    $frontend_signal = 1 if !$frontend_signal && $file =~ /\.(vue|jsx|tsx)$/;
    next unless -f $file && -r $file;
    open my $fh, "<", $file or next;
    while (my $line = <$fh>) {
      for my $sr (@sig_re) { $sig{ $sr->[0] } = 1 if $line =~ $sr->[1]; }
    }
    close $fh;
  }
  if (!$frontend_signal) {
    for my $f (@selected) {
      next unless $f =~ /package\.json$/ && -r $f;
      local $/; open my $fh, "<", $f or next; my $t = <$fh>; close $fh;
      if ($t =~ /"(?:vue|react|nuxt|next)"\s*:\s*["\x27]/) { $frontend_signal = 1; last; }
    }
  }

  # ---- Profile 判定 ----
  my %profile;
  $profile{"node-api"} = 1 if ($project_type // "") eq "node" || $sig{"http-server"};
  my $supported_frontend_project = ($project_type // "") =~ /^frontend-(?:react|vue[23])$/;
  $profile{"node-bff"} = 1 if $profile{"node-api"} && ($frontend_signal || $supported_frontend_project);
  $profile{"node-worker"} = 1 if $sig{"worker-queue"};
  my @profiles = grep { $profile{$_} } qw(node-api node-bff node-worker);

  # ---- 控制适用性（catalog 顺序输出；排除项给明确可复核原因）----
  my $cat;
  { local $/; open my $fh, "<", $catalog_path or failx("CATALOG_INVALID", $catalog_path); my $t = <$fh>;
    $cat = eval { decode_json($t) }; failx("CATALOG_INVALID", "unparseable") if $@ || ref($cat) ne "HASH"; }
  my $controls = $cat->{controls} // [];
  my (@applicable, @excluded);
  my %seen_out;
  for my $c (@$controls) {
    my $id = $c->{id} // next;
    next if $seen_out{$id}++;
    my @in_prof = grep { $profile{$_} } @{ $c->{profiles} // [] };
    if (!@in_prof) {
      push @excluded, { id => $id, reason => "profile 未启用（激活 profile: " . (@profiles ? join(",", @profiles) : "无") . "）；如语义审查发现该控制风险，可在台账中以 finding_confirmed 语义提升" };
      next;
    }
    my @req = @{ $c->{applicability}{review_signals} // [] };
    my @matched = grep { $sig{$_} } @req;
    my $basis = @matched ? "signal-confirmed" : "profile-default";
    push @applicable, {
      id => $id,
      applicability => "applicable",
      basis => $basis,
      matched_signals => [@matched],
    };
  }

  my $out = {
    schema_version           => 1,
    language_id              => $inp->{language_id} // "",
    security_profile         => [@profiles],
    project_type             => $project_type,
    catalog_path             => (abs_path($catalog_path) || $catalog_path),
    catalog_sha256           => $catalog_sha,
    upstream_manifest_sha256 => $manifest_sha,
    review_input_sha256      => $ri_sha,
    controls                 => [@applicable],
    excluded_controls        => [@excluded],
  };
  my $json = JSON::PP->new->canonical->allow_bignum->utf8->encode($out);
  open my $of, ">:raw", $tmp_out or failx("TMP_WRITE", $tmp_out);
  print {$of} $json, "\n";
  close $of or failx("TMP_WRITE", $tmp_out);

  my $profiles_csv = @profiles ? join(",", @profiles) : "";
  my $n = scalar @applicable;
  print STDERR "CCR_RESOLVE_PROFILES=$profiles_csv CONTROLS=$n SIGNALS=", join(",", sort keys %sig), "\n";
' "$PROJECT_DIR" "$PROJECT_TYPE" "$REVIEW_INPUT_JSON" "$CATALOG" "$CATALOG_SHA256" "$UPSTREAM_MANIFEST_SHA256" "$REVIEW_INPUT_SHA256" "$TMP_OUT" || exit 1

mv -f "$TMP_OUT" "$OUTPUT_JSON"
trap - EXIT

PROFILES_CSV="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f> }); print join(",", @{$d->{security_profile}})' "$OUTPUT_JSON")"
CONTROLS_N="$(perl -MJSON::PP -0777 -e 'my $d=decode_json(do { local $/; open my $f, "<", $ARGV[0] or die; <$f> }); print scalar @{$d->{controls}}' "$OUTPUT_JSON")"
OUT_ABS="$(cd "$(dirname "$OUTPUT_JSON")" && pwd)/$(basename "$OUTPUT_JSON")"
printf 'SECURITY_CONTROLS_PATH=%s SECURITY_PROFILES=%s CONTROLS=%s CATALOG_SHA256=%s\n' \
  "$OUT_ABS" "$PROFILES_CSV" "$CONTROLS_N" "$CATALOG_SHA256"
