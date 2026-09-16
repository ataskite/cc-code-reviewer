#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-common-batch-wc.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

. "$ROOT_DIR/scripts/core/lib/common.sh"

# 输出协议：NUL 分隔记录 <原始路径><RS(0x1e)><换行数>。路径字节原样透传，
# 不解析任何文本列；含换行符 / 前导空格 / 名为 total 的路径都必须逐条对位。
printf 'a\nb\n' > "$TMP_DIR/ leading.java"
printf 'x\n' > "$TMP_DIR/total"
printf 'y\ny\ny\n' > "$TMP_DIR/norm.java"
printf 'z\nz\n' > "$TMP_DIR/we
ird.java"

OUT="$TMP_DIR/out.bin"
printf '%s\0' "$TMP_DIR/ leading.java" "$TMP_DIR/total" "$TMP_DIR/norm.java" "$TMP_DIR/we
ird.java" | batch_wc_lines_nul > "$OUT"

perl -e '
  my ($out) = @ARGV;
  my $raw = do { local $/; open my $h, "<", $out or die; <$h> };
  my @recs = grep { length } split(/\0/, $raw, -1);
  die "RECORD_COUNT_MISMATCH: " . scalar(@recs) . "\n" unless @recs == 4;
  my %expected = (
    $ARGV[1] . "/ leading.java" => 2,
    $ARGV[1] . "/total" => 1,
    $ARGV[1] . "/norm.java" => 3,
    $ARGV[1] . "/we\nird.java" => 2,
  );
  for my $rec (@recs) {
    my ($p, $c) = $rec =~ /\A(.*)\x1e(\d+)\z/s or die "MALFORMED_RECORD: $rec\n";
    die "UNEXPECTED_PATH: $p\n" unless exists $expected{$p};
    die "COUNT_MISMATCH: $p got $c want $expected{$p}\n" unless $c == $expected{$p};
    delete $expected{$p};
  }
  die "MISSING_RECORDS: " . join(",", keys %expected) . "\n" if %expected;
' "$OUT" "$TMP_DIR" || { echo "BATCH_WC_CONTENT_MISMATCH" >&2; exit 1; }

# 输出必须与 wc -l 口径一致：末行无换行符不计入行数。
printf 'no newline' > "$TMP_DIR/no-newline.java"
OUT2="$TMP_DIR/out2.bin"
printf '%s\0' "$TMP_DIR/no-newline.java" | batch_wc_lines_nul > "$OUT2"
printf '%s\x1e0\0' "$TMP_DIR/no-newline.java" > "$TMP_DIR/expected2.bin"
cmp "$OUT2" "$TMP_DIR/expected2.bin" || { echo "BATCH_WC_NEWLINE_SEMANTICS_MISMATCH" >&2; exit 1; }

# 空输入零输出零退出码。
OUT3="$TMP_DIR/out3.bin"
: | batch_wc_lines_nul > "$OUT3"
[ "$(wc -c < "$OUT3" | tr -d ' ')" -eq 0 ] || { echo "BATCH_WC_EMPTY_MISMATCH" >&2; exit 1; }

# 缺失文件必须 fail-loud，禁止静默错位。
if printf '%s\0' "$TMP_DIR/norm.java" "$TMP_DIR/missing.java" | batch_wc_lines_nul >/dev/null 2>&1; then
  echo "BATCH_WC_MISSING_FILE_MUST_FAIL" >&2; exit 1
fi

# 大文件分块读取不丢换行（超过 1 MiB sysread 块边界）。
SEQ_FILE="$TMP_DIR/big.java"
perl -e 'print "x\n" x 800000' > "$SEQ_FILE"
OUT4="$TMP_DIR/out4.bin"
printf '%s\0' "$SEQ_FILE" | batch_wc_lines_nul > "$OUT4"
printf '%s\x1e800000\0' "$SEQ_FILE" > "$TMP_DIR/expected4.bin"
cmp "$OUT4" "$TMP_DIR/expected4.bin" || { echo "BATCH_WC_CHUNKED_READ_MISMATCH" >&2; exit 1; }

echo "PASS: core common.sh batch_wc_lines_nul (NUL records, newline paths, wc -l semantics, fail-loud)"
