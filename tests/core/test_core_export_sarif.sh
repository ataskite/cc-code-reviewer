#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-sarif.XXXXXX")"
TMP_DIR="$(cd "$TMP_DIR" && pwd -P)"   # 物理路径（macOS /var → /private/var），与导出脚本的 abs_path 对齐
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT="$ROOT_DIR/scripts/core/export-sarif.sh"
fail() { echo "FAIL: core export-sarif: $*" >&2; exit 1; }

# JSON 断言辅助：json_eval <file> <perl expr>，expr 内 $d 为解码后的 SARIF 结构，
# 结果按 UTF-8 打印到 stdout 供 bash 比较。
json_eval() {
  perl -MJSON::PP -e '
    my ($file, $expr) = @ARGV;
    open my $f, "<", $file or die "open $file: $!\n";
    local $/; my $d = decode_json(<$f>);
    binmode STDOUT, ":utf8";
    my $v = eval $expr; die "$@\n" if $@;
    print $v;
  ' "$1" "$2"
}

# ---- 1) 主 fixture：P0 + P1 + P2(区间行号) + 待确认(无行号) + 无位置块 ----
D="$TMP_DIR/main"; mkdir -p "$D/out"
cat > "$D/report.md" <<'MD'
# 代码审查报告 - demo

## 发现列表

### P0 | [维度5-安全] 认证缺失导致 RCE
- 文件：src/main/java/Order.java:142
- 置信度：高
- 证据：
  ```java
  +    if (token == null) {
  +        return false;
  +    }
  ```
- 建议：补充权限校验并统一走网关鉴权

### P1 | [维度4-正确性] 金额计算使用 double
- 文件：src/main/java/Pay.java:12
- 置信度：中
- 证据：
  ```java
  double total = amount * rate;
  ```
- 建议：改用 BigDecimal

### P2 | [维度3-性能] 循环内重复查询（上轮已报）
- 文件：src/main/java/ListSvc.java:7-19
- 置信度：中
- 证据：
  ```java
  for (Item i : items) {
      dao.load(i.getId());
  }
  ```
- 建议：批量预加载

### 待确认 | [维度3-性能] 缓存失效策略待复核
- 文件：src/main/java/Cache.java
- 置信度：低
- 证据：
  ```java
  cache.put(k, v);
  ```
- 建议：确认 TTL 配置来源

### P1 | 无法定位的全局配置问题
- 置信度：中
- 建议：人工确认配置来源
MD
SARIF="$D/out/report.sarif"
OUT="$(bash "$SCRIPT" "$D/report.md" "$SARIF")"
ABS_SARIF="$(cd "$D/out" && pwd -P)/report.sarif"

# stdout 契约：单行 SARIF_EXPORTED=<abs> RESULTS=<n> RULES=<m>
grep -qx "SARIF_EXPORTED=$ABS_SARIF RESULTS=5 RULES=4" <<< "$OUT" || fail "1 stdout contract"
test "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 1 || fail "1 stdout must be single line"

# 顶层 schema 与 driver
[ "$(json_eval "$SARIF" '$d->{version}')" = "2.1.0" ] || fail "1 sarif version"
[ "$(json_eval "$SARIF" "\$d->{q(\$schema)}")" = "https://json.schemastore.org/sarif-2.1.0.json" ] || fail "1 \$schema"
[ "$(json_eval "$SARIF" '$d->{runs}[0]{tool}{driver}{name}')" = "cc-code-reviewer" ] || fail "1 driver name"
[ "$(json_eval "$SARIF" '$d->{runs}[0]{tool}{driver}{informationUri}')" = "https://github.com/ataskite/cc-code-reviewer" ] || fail "1 driver informationUri"
EXPECTED_VERSION="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$ROOT_DIR/VERSION")"
[ "$(json_eval "$SARIF" '$d->{runs}[0]{tool}{driver}{version}')" = "$EXPECTED_VERSION" ] || fail "1 driver version tracks VERSION file"

# rules：去重 + 字节序排序（ASCII "unknown-dimension" 的 0x75 小于 UTF-8 CJK 首字节 0xE7）
[ "$(json_eval "$SARIF" 'join(",", map { $_->{id} } @{$d->{runs}[0]{tool}{driver}{rules}})')" = "unknown-dimension,维度3-性能,维度4-正确性,维度5-安全" ] || fail "1 rules sorted unique"
[ "$(json_eval "$SARIF" 'join("|", map { $_->{shortDescription}{text} } @{$d->{runs}[0]{tool}{driver}{rules}})')" = "unknown-dimension 审查发现|维度3-性能 审查发现|维度4-正确性 审查发现|维度5-安全 审查发现" ] || fail "1 rules shortDescription"

# severity 映射与 ruleIndex（文档顺序保留）
[ "$(json_eval "$SARIF" 'join(",", map { $_->{level} } @{$d->{runs}[0]{results}})')" = "error,warning,note,note,warning" ] || fail "1 severity map"
[ "$(json_eval "$SARIF" 'join(",", map { $_->{ruleId} } @{$d->{runs}[0]{results}})')" = "维度5-安全,维度4-正确性,维度3-性能,维度3-性能,unknown-dimension" ] || fail "1 ruleIds in document order"
[ "$(json_eval "$SARIF" 'join(",", map { $_->{ruleIndex} } @{$d->{runs}[0]{results}})')" = "3,2,1,1,0" ] || fail "1 ruleIndex"

# 区间行号块：startLine + endLine
[ "$(json_eval "$SARIF" '$d->{runs}[0]{results}[2]{locations}[0]{physicalLocation}{region}{startLine}')" = "7" ] || fail "1 range startLine"
[ "$(json_eval "$SARIF" '$d->{runs}[0]{results}[2]{locations}[0]{physicalLocation}{region}{endLine}')" = "19" ] || fail "1 range endLine"
# 单行号块：只有 startLine，无 endLine 键
[ "$(json_eval "$SARIF" '$d->{runs}[0]{results}[0]{locations}[0]{physicalLocation}{region}{startLine}')" = "142" ] || fail "1 single startLine"
[ "$(json_eval "$SARIF" 'join(",", sort keys %{$d->{runs}[0]{results}[0]{locations}[0]{physicalLocation}{region}})')" = "startLine" ] || fail "1 single-line region has no endLine"
[ "$(json_eval "$SARIF" '$d->{runs}[0]{results}[0]{locations}[0]{physicalLocation}{artifactLocation}{uri}')" = "src/main/java/Order.java" ] || fail "1 uri as written"

# 待确认块：有文件行但行号不可解析 → 保留 artifactLocation、省略 region
[ "$(json_eval "$SARIF" 'scalar(@{$d->{runs}[0]{results}[3]{locations}})')" = "1" ] || fail "1 path-only location kept"
[ "$(json_eval "$SARIF" '$d->{runs}[0]{results}[3]{locations}[0]{physicalLocation}{artifactLocation}{uri}')" = "src/main/java/Cache.java" ] || fail "1 path-only uri"
[ "$(json_eval "$SARIF" 'exists $d->{runs}[0]{results}[3]{locations}[0]{physicalLocation}{region} ? "HAS" : "NO"')" = "NO" ] || fail "1 path-only has no region"

# 无位置块：locations 为空数组，发现不丢失
[ "$(json_eval "$SARIF" 'ref($d->{runs}[0]{results}[4]{locations})')" = "ARRAY" ] || fail "1 no-location locations is array"
[ "$(json_eval "$SARIF" 'scalar(@{$d->{runs}[0]{results}[4]{locations}})')" = "0" ] || fail "1 no-location block kept with empty locations"
[ "$(json_eval "$SARIF" '$d->{runs}[0]{results}[4]{message}{text}')" = "无法定位的全局配置问题 — 人工确认配置来源" ] || fail "1 no-location message"

# message.text 组合（标题 — 建议）
[ "$(json_eval "$SARIF" '$d->{runs}[0]{results}[0]{message}{text}')" = "认证缺失导致 RCE — 补充权限校验并统一走网关鉴权" ] || fail "1 message composition"

# 格式钉子：canonical + 2 空格缩进 + 恰好一个结尾换行（有效 UTF-8 已由 decode_json 隐式校验）
grep -qxF '  "version": "2.1.0"' "$SARIF" || fail "1 two-space indent pin"
[ "$(perl -0777 -ne 'print /\n\z/ ? "NL" : "NO"' "$SARIF")" = "NL" ] || fail "1 trailing newline"
[ "$(perl -0777 -ne 'print /[^\n]\n\z/ ? "ONE" : "BAD"' "$SARIF")" = "ONE" ] || fail "1 exactly one trailing newline"

# ---- 2) message.text：建议截断 500 字符 / 无建议仅标题 / JSON 转义压力 ----
D2="$TMP_DIR/msg"; mkdir -p "$D2"
LONG_ADVICE="$(perl -e 'print "修" x 520')"
TRUNC_ADVICE="$(perl -e 'print "修" x 500')"
{
  echo '# 代码审查报告 - demo'
  echo
  echo '## 发现列表'
  echo
  echo '### P1 | [维度2-可维护性] 超长建议截断'
  echo '- 文件：src/A.java:1'
  echo "- 建议：$LONG_ADVICE"
  echo
  echo '### P2 | [维度1-规范] 无建议行的发现'
  echo '- 文件：src/A.java:2'
  echo
  echo '### P1 | [维度1-规范] 转义压力测试'
  echo '- 文件：src/A.java:3'
  echo '- 建议：包含"双引号"与\反斜杠'
} > "$D2/report.md"
bash "$SCRIPT" "$D2/report.md" "$D2/out.sarif" > /dev/null
[ "$(json_eval "$D2/out.sarif" 'scalar(@{$d->{runs}[0]{results}})')" = "3" ] || fail "2 results count"
[ "$(json_eval "$D2/out.sarif" '$d->{runs}[0]{results}[0]{message}{text}')" = "超长建议截断 — $TRUNC_ADVICE" ] || fail "2 advice truncated to 500 chars"
[ "$(json_eval "$D2/out.sarif" 'length($d->{runs}[0]{results}[0]{message}{text})')" = "509" ] || fail "2 message length 6+3+500"
[ "$(json_eval "$D2/out.sarif" '$d->{runs}[0]{results}[1]{message}{text}')" = "无建议行的发现" ] || fail "2 title-only message"
[ "$(json_eval "$D2/out.sarif" '$d->{runs}[0]{results}[2]{message}{text}')" = '转义压力测试 — 包含"双引号"与\反斜杠' ] || fail "2 json escaping round-trip"

# ---- 3) 指纹一致性：与 merge 跨批次去重指纹同公式 ----
# 交叉验证方案（文档化）：
#   (a) 用「发布公式」的内联 perl 重实现（sha256(路径\0维度\0归一化证据)，行归一
#       = 去CR→trim→剥一个+/-→再trim→去尾空白、空行全弃）计算期望值，与导出值精确相等；
#   (b) 直接调用 merge-batch-results.sh 的 dedupe_issue_blocks（sed 抽取函数体 + eval
#       定义，不复制代码）：两个 (路径,维度,证据) 相同、措辞不同的块被 merge 合并
#       （merged_dups=1），且本导出给两块发出相同指纹 —— 两处对同一块身份判定一致。
EXPECTED_FP="$(perl -Mutf8 -MDigest::SHA=sha256_hex -MEncode=encode_utf8 -e '
  sub norm { my $l = shift; $l =~ s/\r$//; $l =~ s/^\s+//; $l =~ s/^[-+]?//; $l =~ s/^\s+//; $l =~ s/\s+$//; return $l; }
  my @raw = ("+    if (token == null) {", "+        return false;", "+    }");
  my @ev = grep { length } map { norm($_) } @raw;
  print sha256_hex(encode_utf8(join("\x00", "src/main/java/Order.java", "维度5-安全", join("\n", @ev))));
')"
FP0="$(json_eval "$SARIF" '$d->{runs}[0]{results}[0]{partialFingerprints}{"ccCodeReviewer/v1"}')"
[ "$FP0" = "$EXPECTED_FP" ] || fail "3 fingerprint equals published formula"

DEDUP_IN="$TMP_DIR/dedup-in.md"
cat > "$DEDUP_IN" <<'MD'
# 代码审查报告 - demo

### P1 | [维度5-安全] 措辞甲
- 文件：src/main/java/Order.java:142
- 证据：
  ```java
  +    if (token == null) {
  +        return false;
  +    }
  ```
- 建议：补充校验

### P1 | [维度5-安全] 措辞乙完全不同
- 文件：src/main/java/Order.java:88
- 证据：
  ```java
  +    if (token == null) {
  +        return false;
  +    }
  ```
- 建议：另写一个完全不同的建议
MD
eval "$(sed -n '/^dedupe_issue_blocks()/,/^}$/p' "$ROOT_DIR/scripts/core/merge-batch-results.sh")"
DEDUP_OUT="$TMP_DIR/dedup-out.md"
DEDUP_STATS="$TMP_DIR/dedup-stats"
dedupe_issue_blocks "$DEDUP_IN" "$DEDUP_OUT" "$DEDUP_STATS"
[ "$(sed -n '1p' "$DEDUP_STATS")" = "2" ] || fail "3 merge dedup input blocks"
[ "$(sed -n '2p' "$DEDUP_STATS")" = "1" ] || fail "3 merge dedup merged the wording-drift duplicate"
OUT3="$(bash "$SCRIPT" "$DEDUP_IN" "$TMP_DIR/dedup.sarif")"
grep -qx "SARIF_EXPORTED=$TMP_DIR/dedup.sarif RESULTS=2 RULES=1" <<< "$OUT3" || fail "3 dedup fixture export stdout"
FP_PAIR="$(json_eval "$TMP_DIR/dedup.sarif" 'join(",", map { $_->{partialFingerprints}{"ccCodeReviewer/v1"} } @{$d->{runs}[0]{results}})')"
[ "$FP_PAIR" = "$EXPECTED_FP,$EXPECTED_FP" ] || fail "3 export fingerprints equal merge identity for shared fixture"

# ---- 4) 确定性：两次导出字节一致 ----
bash "$SCRIPT" "$D/report.md" "$D/out/run1.sarif" > /dev/null
bash "$SCRIPT" "$D/report.md" "$D/out/run2.sarif" > /dev/null
cmp -s "$D/out/run1.sarif" "$D/out/run2.sarif" || fail "4 determinism double run"
cmp -s "$D/out/run1.sarif" "$SARIF" || fail "4 stable against first run"

# ---- 5) 零发现报告：合法 SARIF，results/rules 均为空数组 ----
D5="$TMP_DIR/zero"; mkdir -p "$D5"
cat > "$D5/report.md" <<'MD'
# 代码审查报告 - demo

## 审查配置快照

暂无正式发现。
MD
OUT5="$(bash "$SCRIPT" "$D5/report.md" "$D5/out.sarif")"
grep -qx "SARIF_EXPORTED=$D5/out.sarif RESULTS=0 RULES=0" <<< "$OUT5" || fail "5 zero-findings stdout"
[ "$(json_eval "$D5/out.sarif" 'ref($d->{runs}[0]{results})')" = "ARRAY" ] || fail "5 results is array"
[ "$(json_eval "$D5/out.sarif" 'scalar(@{$d->{runs}[0]{results}})')" = "0" ] || fail "5 empty results"
[ "$(json_eval "$D5/out.sarif" 'ref($d->{runs}[0]{tool}{driver}{rules})')" = "ARRAY" ] || fail "5 rules is array"
[ "$(json_eval "$D5/out.sarif" 'scalar(@{$d->{runs}[0]{tool}{driver}{rules}})')" = "0" ] || fail "5 empty rules"
[ "$(json_eval "$D5/out.sarif" '$d->{runs}[0]{tool}{driver}{version}')" = "$EXPECTED_VERSION" ] || fail "5 driver version still present"

# ---- 6) --project-name：写入 run.properties.projectName；未传时不出现该键 ----
bash "$SCRIPT" "$D/report.md" "$D/out/named.sarif" --project-name "演示 项目" > /dev/null
[ "$(json_eval "$D/out/named.sarif" '$d->{runs}[0]{properties}{projectName}')" = "演示 项目" ] || fail "6 properties.projectName"
[ "$(json_eval "$SARIF" 'exists $d->{runs}[0]{properties} ? "HAS" : "NO"')" = "NO" ] || fail "6 properties absent without flag"

# ---- 7) 用法与 IO 错误：exit 1 + ERROR_* 标签 ----
if ERR="$(bash "$SCRIPT" 2>&1)"; then fail "7 missing all args must exit 1"; fi
grep -q 'ERROR_INVALID_ARGS=' <<< "$ERR" || fail "7 no-args error label"
if ERR="$(bash "$SCRIPT" "$D/report.md" 2>&1)"; then fail "7 missing output arg must exit 1"; fi
grep -q 'ERROR_INVALID_ARGS=' <<< "$ERR" || fail "7 missing-output error label"
if ERR="$(bash "$SCRIPT" "$D/report.md" "$D/out/x.sarif" --project-name 2>&1)"; then fail "7 option value missing must exit 1"; fi
grep -q 'ERROR_INVALID_ARGS=' <<< "$ERR" || fail "7 option-value error label"
if ERR="$(bash "$SCRIPT" "$D/report.md" "$D/out/x.sarif" --bogus 2>&1)"; then fail "7 unknown option must exit 1"; fi
grep -q 'ERROR_UNKNOWN_OPTION=' <<< "$ERR" || fail "7 unknown-option error label"
if ERR="$(bash "$SCRIPT" "$TMP_DIR/no-such-report.md" "$D/out/x.sarif" 2>&1)"; then fail "7 missing report must exit 1"; fi
grep -q 'ERROR_REPORT_NOT_FOUND=' <<< "$ERR" || fail "7 missing-report error label"
rc=0; bash "$SCRIPT" "$TMP_DIR/no-such-report.md" "$D/out/x.sarif" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "7 missing report exit code must be exactly 1 (got $rc)"
touch "$TMP_DIR/a-file"
if ERR="$(bash "$SCRIPT" "$D/report.md" "$TMP_DIR/a-file/sub/out.sarif" 2>&1)"; then fail "7 uncreatable dir must exit 1"; fi
grep -q 'ERROR_OUTPUT_DIR_NOT_CREATABLE=' <<< "$ERR" || fail "7 uncreatable-dir error label"
# 不可写目录（root 下 -w 恒真，跳过该子用例）
if [ "$(id -u)" != "0" ]; then
  mkdir -p "$TMP_DIR/nowrite"; chmod 000 "$TMP_DIR/nowrite"
  if ERR="$(bash "$SCRIPT" "$D/report.md" "$TMP_DIR/nowrite/out.sarif" 2>&1)"; then fail "7 unwritable dir must exit 1"; fi
  grep -qE 'ERROR_OUTPUT_DIR_NOT_(WRITABLE|CREATABLE)=' <<< "$ERR" || fail "7 unwritable-dir error label"
  chmod 755 "$TMP_DIR/nowrite"
fi

# ---- 8) CRLF 报告：结果数与指纹与 LF 版本完全一致 ----
perl -pe 's/\n/\r\n/g' "$D/report.md" > "$D/report-crlf.md"
OUT8="$(bash "$SCRIPT" "$D/report-crlf.md" "$D/out/crlf.sarif")"
grep -qx "SARIF_EXPORTED=$D/out/crlf.sarif RESULTS=5 RULES=4" <<< "$OUT8" || fail "8 crlf stdout"
FP_ALL_LF="$(json_eval "$SARIF" 'join(",", map { $_->{partialFingerprints}{"ccCodeReviewer/v1"} } @{$d->{runs}[0]{results}})')"
FP_ALL_CRLF="$(json_eval "$D/out/crlf.sarif" 'join(",", map { $_->{partialFingerprints}{"ccCodeReviewer/v1"} } @{$d->{runs}[0]{results}})')"
[ "$FP_ALL_CRLF" = "$FP_ALL_LF" ] || fail "8 crlf fingerprints identical to LF"
[ "$(json_eval "$D/out/crlf.sarif" '$d->{runs}[0]{results}[0]{message}{text}')" = "认证缺失导致 RCE — 补充权限校验并统一走网关鉴权" ] || fail "8 crlf message clean"

# ---- 9) 标题中（上轮已报）后缀逐字节保留 ----
MSG2="$(json_eval "$SARIF" '$d->{runs}[0]{results}[2]{message}{text}')"
[ "$MSG2" = "循环内重复查询（上轮已报） — 批量预加载" ] || fail "9 title suffix byte-faithful"

# ---- 10) 真实报告格式边角：编号表头 P0-N / 待确认-N、全角冒号行号、未闭合围栏、输出路径是目录 ----
D10="$TMP_DIR/edges"; mkdir -p "$D10/isdir"
cat > "$D10/report.md" <<'MD'
# 代码审查报告 - demo

### P0-1 | [维度5-安全] 编号表头示例
- 文件：src/A.java：12
- 证据：
  ```java
  unclosed evidence
- 建议：x

### 待确认-3 | 无维度编号
- 文件：src/B.java
MD
OUT10="$(bash "$SCRIPT" "$D10/report.md" "$D10/out.sarif")"
grep -qx "SARIF_EXPORTED=$D10/out.sarif RESULTS=2 RULES=2" <<< "$OUT10" || fail "10 stdout"
[ "$(json_eval "$D10/out.sarif" '$d->{runs}[0]{results}[0]{message}{text}')" = "编号表头示例 — x" ] || fail "10 numbered header title"
[ "$(json_eval "$D10/out.sarif" '$d->{runs}[0]{results}[0]{locations}[0]{physicalLocation}{region}{startLine}')" = "12" ] || fail "10 full-width colon line"
[ "$(json_eval "$D10/out.sarif" '$d->{runs}[0]{results}[1]{ruleId}')" = "unknown-dimension" ] || fail "10 numbered 待确认 without dim"
[ "$(json_eval "$D10/out.sarif" 'length($d->{runs}[0]{results}[0]{partialFingerprints}{"ccCodeReviewer/v1"})')" = "64" ] || fail "10 unclosed fence still yields sha256 fingerprint"
rc=0; bash "$SCRIPT" "$D10/report.md" "$D10/isdir" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "10 output path is a directory must exit exactly 1 (got $rc)"

echo "PASS: core export-sarif"
