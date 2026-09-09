#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-lib-findings.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

LIB_DIR="$ROOT_DIR/scripts/core/lib"
fail() { echo "FAIL: core lib CCR/Findings: $*" >&2; exit 1; }

# pm_eval <perl expr>：在 :all 导入下执行断言表达式，stdout 为比较输出。
# 表达式须自足（用字面量构造输入），失败由调用方 fail 捕获。
pm() {
  perl -I "$LIB_DIR" -MCCR::Findings=:all -Mutf8 -CS -e "$1"
}

# ============ 1) norm_line：证据行归一化 ============
# CRLF：结尾 \r 必剥；首尾空白剥；一个 +/- diff 前缀剥；双前缀只剥一个。
OUT="$(pm '
  print norm_line("  +  foo();  \r"), "\n";
  print norm_line("\t- bar();\r"), "\n";
  print norm_line("++x"), "\n";
  print norm_line("--y"), "\n";
  print norm_line("   \t  "), "[EMPTY]\n";
  print norm_line(""), "[EMPTY2]\n";
  print "[", norm_line(undef), "]\n";
')"
expect_eq() { [ "$1" = "$2" ] || fail "$3 (got '$1' want '$2')"; }
expect_line_at() { got="$(printf '%s\n' "$OUT" | sed -n "$1p")"; expect_eq "$got" "$2" "$3"; }
expect_line_at 1 "foo();" "norm_line CRLF+diff prefix+indent"
expect_line_at 2 "bar();" "norm_line minus prefix with tab indent"
expect_line_at 3 "+x" "norm_line strips only one leading +"
expect_line_at 4 "-y" "norm_line strips only one leading -"
expect_line_at 5 "[EMPTY]" "norm_line whitespace-only -> empty"
expect_line_at 6 "[EMPTY2]" "norm_line empty string -> empty"
expect_line_at 7 "[]" "norm_line undef-safe -> empty"

# ============ 2) collapse_ws：连续空白折叠 + 首尾 trim ============
OUT="$(pm 'print collapse_ws("  a\t b   c \n "), "|", collapse_ws(""), "|", collapse_ws("x"), "\n"')"
expect_eq "$OUT" "a b c||x" "collapse_ws collapse and trim"

# ============ 3) parse_dim_tag：第一个 [...] 内层文本 ============
OUT="$(pm '
  print "[", parse_dim_tag("### P0-1 | [维  度5-安全] 标题"), "]\n";
  print "[", parse_dim_tag("### P1 无括号"), "]\n";
  print "[", parse_dim_tag("### P2 | [第一] [第二] x"), "]\n";
')"
expect_line_at 1 "[维 度5-安全]" "parse_dim_tag inner ws collapsed"
expect_line_at 2 "[]" "parse_dim_tag missing brackets -> empty"
expect_line_at 3 "[第一]" "parse_dim_tag first bracket pair only"

# ============ 4) dim_info：(是否含括号, 折叠标签) 元组 ============
OUT="$(pm '
  my @a = dim_info("### P0-1 | [维度5-安全] x"); print "$a[0]/$a[1]\n";
  my @b = dim_info("### P1 x"); print "$b[0]/$b[1]\n";
')"
expect_line_at 1 "1/维度5-安全" "dim_info with bracket"
expect_line_at 2 "0/" "dim_info without bracket"

# ============ 5) first_location_path：同轮口径（只剥一个点锚） ============
# 历史行为断言：:([0-9]+)$ 无法匹配 ":5-9"（冒号后不是纯数字到行尾），
# 区间路径原样保留（"a.java:5-9" 不剥、也不剥成 "a.java:5-"）。
OUT="$(pm '
  print "[", first_location_path("- 文件：src/main/A.java:12"), "]\n";
  print "[", first_location_path("- 文件：src/main/A.java：12"), "]\n";
  print "[", first_location_path("- 文件：a.java:5-9"), "]\n";
  print "[", first_location_path("- 文件：a.java：5-9"), "]\n";
  print "[", first_location_path("- 文件： win\\path\\X.java:7 "), "]\n";
  print "[", first_location_path("- 建议：无文件行"), "]\n";
  print "[", first_location_path("- 文件：  "), "]\n";
')"
expect_line_at 1 "[src/main/A.java]" "first_location_path strips :12"
expect_line_at 2 "[src/main/A.java]" "first_location_path strips full-width :12"
expect_line_at 3 "[a.java:5-9]" "first_location_path keeps range :5-9 byte-intact (historical)"
expect_line_at 4 "[a.java：5-9]" "first_location_path keeps full-width range intact"
expect_line_at 5 "[win/path/X.java]" "first_location_path backslash unification + trim"
expect_line_at 6 "[]" "first_location_path no location line -> empty"
expect_line_at 7 "[]" "first_location_path blank path -> empty"

# ============ 6) compare_path：跨轮口径（点/区间锚全剥） ============
OUT="$(pm '
  print "[", compare_path(" a.java:5-9 "), "]\n";
  print "[", compare_path("a.java：5-9"), "]\n";
  print "[", compare_path("a.java:12"), "]\n";
  print "[", compare_path("a.java：12"), "]\n";
  print "[", compare_path(" win\\p\\A.java:3 "), "]\n";
  print "[", compare_path("   "), "]\n";
')"
expect_line_at 1 "[a.java]" "compare_path strips :5-9"
expect_line_at 2 "[a.java]" "compare_path strips full-width :5-9"
expect_line_at 3 "[a.java]" "compare_path strips :12"
expect_line_at 4 "[a.java]" "compare_path strips full-width :12"
expect_line_at 5 "[win/p/A.java]" "compare_path backslash unification"
expect_line_at 6 "[]" "compare_path blank -> empty"
# 两条路径口径有意不同（跨轮比同轮剥得更彻底），不得合并。
if [ "$(pm 'print first_location_path("- 文件：a.java:5-9")')" = "$(pm 'print compare_path("a.java:5-9")')" ]; then
  fail "first_location_path and compare_path must stay intentionally divergent"
fi

# ============ 7) evidence_lines / evidence_count：围栏扫描 ============
OUT="$(pm '
  my @a = evidence_lines("- 证据：", "  ```java", "  +alpha();", "", "  -beta();", "  ```", "- 建议：x");
  print scalar(@a), ":$a[0]:$a[1]\n";
  my @b = evidence_lines("```", "unclosed", "code");
  print scalar(@b), "\n";
  my @c = evidence_lines("```java", "   ", "```");
  print scalar(@c), "\n";
  my @d = evidence_lines("无围栏体行");
  print scalar(@d), "\n";
  print evidence_count("- 证据：", "  ```java", "  +alpha();", "beta();", "  ```", "- 建议：x"), "\n";
  print evidence_count("- 证据：", "```", "unclosed"), "\n";
')"
expect_line_at 1 "2:alpha();:beta();" "evidence_lines indented fence + lang tag + normalization + blank dropped"
expect_line_at 2 "0" "evidence_lines unclosed fence -> empty"
expect_line_at 3 "0" "evidence_lines fence with only blank content -> empty"
expect_line_at 4 "0" "evidence_lines no fence -> empty"
expect_line_at 5 "2" "evidence_count equals evidence_lines count"
expect_line_at 6 "0" "evidence_count unclosed -> 0 (never undef)"

# ============ 8) 块边界谓词真值表 ============
OUT="$(pm '
  print (is_issue_heading("### P0-1 | [x] y") ? "Y" : "N");
  print (is_issue_heading("### 待确认-5 | [x] y") ? "Y" : "N");
  print (is_issue_heading("### P3 z") ? "Y" : "N");
  print (is_issue_heading("### batch-001 - 模块") ? "Y" : "N");
  print (is_issue_heading("#### P0 nested") ? "Y" : "N");
  print (is_issue_heading("## P0 章节") ? "Y" : "N");
  print "\n";
  print (is_block_terminator("## 其他") ? "Y" : "N");
  print (is_block_terminator("### P1-2 | [x] y") ? "Y" : "N");
  print (is_block_terminator("#### 非 h2/h3") ? "Y" : "N");
  print (is_block_terminator("普通行") ? "Y" : "N");
  print "\n";
')"
expect_line_at 1 "YYYNNN" "is_issue_heading truth table (batch separator is not a finding)"
expect_line_at 2 "YYNN" "is_block_terminator truth table"

# ============ 9) finding_fingerprint：与独立 SHA-256 oracle 交叉验证（含中文维度） ============
# (a) ASCII 路径 + 中文维度 + 多行证据：用 shell 侧 printf 构造完全相同的字节
#     （路径 \0 维度 \0 证据）交给 Perl Digest::SHA 独立计算，必须逐字节相等。
DIM="维度5-安全"
PATH_A="src/main/java/Order.java"
EVID='if (token == null) {
    return false;
}'
GOT_FP="$(pm 'print finding_fingerprint("src/main/java/Order.java", "维度5-安全", "if (token == null) {\n    return false;\n}");')"
WANT_FP="$(printf '%s\0%s\0%s' "$PATH_A" "$DIM" "$EVID" | perl -MDigest::SHA -e 'my $d = Digest::SHA->new(256); while (read(STDIN, my $buf, 65536)) { $d->add($buf); } print $d->hexdigest, "\n"')"
expect_eq "$WANT_FP" "b4f6f2e0d1ce9fe46416294c60c9bde1139aedc389f67830e362ed7026e711e3" "fingerprint oracle known vector"
expect_eq "$GOT_FP" "$WANT_FP" "finding_fingerprint equals independent NUL-joined SHA-256 oracle (UTF-8 dimension)"
# (b) 空证据/空维度兜底形态与公式一致（全空 join 也必须可复现）。
GOT_FP2="$(pm 'print finding_fingerprint("", "", "");')"
WANT_FP2="$(printf '%s\0%s\0%s' "" "" "" | perl -MDigest::SHA -e 'my $d = Digest::SHA->new(256); while (read(STDIN, my $buf, 65536)) { $d->add($buf); } print $d->hexdigest, "\n"')"
expect_eq "$WANT_FP2" "96a296d224f285c67bee93c30f8a309157f0daa35dc5b87e410b78630a09cfc7" "empty fingerprint oracle known vector"
expect_eq "$GOT_FP2" "$WANT_FP2" "finding_fingerprint empty components still follow the formula"
# (c) 参数顺序敏感：路径与维度交换必须得到不同指纹。
GOT_FP3="$(pm 'print finding_fingerprint("维度5-安全", "src/main/java/Order.java", "x");')"
if [ "$GOT_FP3" = "$GOT_FP" ]; then fail "finding_fingerprint must be order-sensitive"; fi

# ============ 10) read_text / slurp_raw / atomic_write_text：die 标签与原子写 ============
printf 'hello\n' > "$TMP_DIR/t1.txt"
OUT="$(pm 'print slurp_raw("'"$TMP_DIR"'/t1.txt"), "|"')"
expect_eq "$OUT" "hello
|" "slurp_raw returns raw bytes"
OUT="$(pm 'print slurp_raw("'"$TMP_DIR"'/missing.txt") . "UNDEFOK"')"
expect_eq "$OUT" "UNDEFOK" "slurp_raw missing file -> undef"
printf '内容 OK\n' > "$TMP_DIR/t2.txt"
OUT="$(pm 'print read_text("'"$TMP_DIR"'/t2.txt", "X_READ_ERROR")')"
expect_eq "$OUT" "内容 OK" "read_text decodes UTF-8"
ERR_OUT="$(pm 'read_text("'"$TMP_DIR"'/missing.txt", "NEW_REPORT_READ_ERROR")' 2>&1 >/dev/null || true)"
expect_eq "$ERR_OUT" "NEW_REPORT_READ_ERROR=$TMP_DIR/missing.txt" "read_text dies with the exact complete caller tag"
# 原子写：内容 / 权限位 / 返回临时名。
printf 'old\n' > "$TMP_DIR/t3.txt"
chmod 640 "$TMP_DIR/t3.txt"
OUT="$(pm 'my $t = atomic_write_text("'"$TMP_DIR"'/t3.txt", "新内容\n", ".test.\$\$"); print $t;')"
case "$OUT" in
  "$TMP_DIR/t3.txt.test."*) ;;
  *) fail "atomic_write_text returns the tmp path (got '$OUT')" ;;
esac
grep -qx '新内容' "$TMP_DIR/t3.txt" || fail "atomic_write_text content"
PERM="$(stat -f '%Lp' "$TMP_DIR/t3.txt" 2>/dev/null || stat -c '%a' "$TMP_DIR/t3.txt")"
expect_eq "$PERM" "640" "atomic_write_text preserves mode bits"
# 原子写 die 标签：向不可写目录写临时文件必须报 TMP_WRITE_ERROR。
ERR_OUT="$(pm 'atomic_write_text("'"$TMP_DIR"'/no-such-dir/x.txt", "y", ".tmp.\$\$")' 2>&1 >/dev/null || true)"
case "$ERR_OUT" in
  "TMP_WRITE_ERROR=$TMP_DIR/no-such-dir/x.txt.tmp."*) ;;
  *) fail "atomic_write_text die tag (got '$ERR_OUT')" ;;
esac

echo "PASS: core lib CCR/Findings 发现内核单元契约"
