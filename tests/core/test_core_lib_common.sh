#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-lib-common.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

COMMON="$ROOT_DIR/scripts/core/lib/common.sh"
fail() { echo "FAIL: core lib common.sh: $*" >&2; exit 1; }

[ -f "$COMMON" ] || fail "common.sh missing"

# 主 shell 也 source 一份，后续断言直接调用真实函数（等价于调用方脚本行为）。
. "$COMMON"

# 测试 oracle 固定使用 Perl Digest::SHA：它不经 common.sh 的函数或 PATH 回退链，
# 因而能在没有 shasum 的 Linux 上给出确定的字节级 SHA-256 期望值。
oracle_sha256_file() {
  perl -MDigest::SHA -e 'my $f = shift; my $d = Digest::SHA->new(256); $d->addfile($f); print $d->hexdigest, "\n"' "$1"
}
oracle_sha256_text() {
  perl -MDigest::SHA -e 'my $d = Digest::SHA->new(256); while (read(STDIN, my $buf, 65536)) { $d->add($buf); } print $d->hexdigest, "\n"'
}

# 隔离 PATH，分别让公共 seam 只能看到回退链中的一个实现。
# shasum / sha256sum 在宿主不存在时跳过对应分支；Perl 兜底始终必须可用。
verify_hash_route() {
  local route="$1" file="$2" route_dir got want route_path awk_path
  route_path="$(command -v "$route" || true)"
  if [ -z "$route_path" ]; then
    echo "SKIP: $route fallback unavailable on this host"
    return 0
  fi
  route_dir="$TMP_DIR/path-$route"
  mkdir "$route_dir"
  ln -s "$route_path" "$route_dir/$route"
  if [ "$route" != "perl" ]; then
    awk_path="$(command -v awk)"
    ln -s "$awk_path" "$route_dir/awk"
  fi

  got="$(PATH="$route_dir" /bin/bash -c '. "$1"; sha256_file "$2"' bash "$COMMON" "$file")"
  want="$(oracle_sha256_file "$file")"
  expect_eq "$got" "$want" "sha256_file must use the $route fallback correctly"

  got="$(PATH="$route_dir" /bin/bash -c '. "$1"; sha256_text < "$2"' bash "$COMMON" "$file")"
  want="$(oracle_sha256_file "$file")"
  expect_eq "$got" "$want" "sha256_text must use the $route fallback correctly"
}

# ============ 1) source 无副作用，且在 set -euo pipefail 下可用 ============
# 用子 shell 模拟严格的调用方环境：source 后立即断言函数已定义、无其他输出。
OUT="$(set -euo pipefail; . "$COMMON"; type -t sha256_file; type -t sha256_text)"
expect_eq() { [ "$1" = "$2" ] || fail "$3 (got '$1' want '$2')"; }
expect_eq "$OUT" "function
function" "source defines exactly the two functions under set -euo pipefail"

# ============ 2) sha256_file 与独立 SHA-256 oracle 一致（含中文与二进制字节） ============
printf 'hello world\n' > "$TMP_DIR/plain.txt"
printf '中文内容 UTF-8\n\001\002\003 binary-ish\n' > "$TMP_DIR/utf8.txt"
head -c 64 /dev/urandom > "$TMP_DIR/rand.bin"

for f in plain.txt utf8.txt rand.bin; do
  GOT="$(sha256_file "$TMP_DIR/$f")"
  WANT="$(oracle_sha256_file "$TMP_DIR/$f")"
  expect_eq "$GOT" "$WANT" "sha256_file($f) must equal the SHA-256 oracle"
done

# 路径含空格也可用（引号契约）。
SPACED="$TMP_DIR/with space.txt"
printf 'spaced\n' > "$SPACED"
GOT="$(sha256_file "$SPACED")"
WANT="$(oracle_sha256_file "$SPACED")"
expect_eq "$GOT" "$WANT" "sha256_file path with spaces"

# ============ 3) sha256_text（stdin）与独立 oracle 一致（含多行与空输入） ============
GOT="$(printf 'hello world\n' | sha256_text)"
WANT="$(printf 'hello world\n' | oracle_sha256_text)"
expect_eq "$WANT" "a948904f2f0f479b8f8197694b30184b0d2ed1c1cd2a1ec0fb85d299a192a447" "oracle known vector"
expect_eq "$GOT" "$WANT" "sha256_text stdin text"

GOT="$(printf '第一行\nsecond line\n' | sha256_text)"
WANT="$(printf '第一行\nsecond line\n' | oracle_sha256_text)"
expect_eq "$GOT" "$WANT" "sha256_text stdin utf-8"

GOT="$(printf '' | sha256_text)"
WANT="$(printf '' | oracle_sha256_text)"
expect_eq "$GOT" "$WANT" "sha256_text empty stdin"

# 无尾换行 / 大块输入（> 64KiB 单次 read 缓冲，验证分块累加正确）。
GOT="$(printf 'no trailing newline' | sha256_text)"
WANT="$(printf 'no trailing newline' | oracle_sha256_text)"
expect_eq "$GOT" "$WANT" "sha256_text no trailing newline"
BIG="$TMP_DIR/big.bin"
head -c 200000 /dev/urandom > "$BIG"
GOT="$(cat "$BIG" | sha256_text)"
WANT="$(oracle_sha256_file "$BIG")"
expect_eq "$GOT" "$WANT" "sha256_text 200KiB streamed equal to file hash"

# ============ 4) 输出形态：单行 64 位十六进制 ============
GOT="$(printf 'x' | sha256_text)"
case "$GOT" in
  *[!0-9a-f]*|'') fail "sha256_text must emit lowercase hex only (got '$GOT')" ;;
esac
[ "${#GOT}" -eq 64 ] || fail "sha256_text must emit 64 hex chars (got ${#GOT})"

# ============ 5) 三条回退路径：每条都在隔离 PATH 下验证 file + stdin ============
for ROUTE in shasum sha256sum perl; do
  verify_hash_route "$ROUTE" "$TMP_DIR/plain.txt"
done

# ============ 6) 组合冒烟：与脚本真实调用形态一致（命令替换 + 管道前置） ============
(
  set -euo pipefail
  . "$COMMON"
  A="$(printf 'pipe into cmdsubst\n' | sha256_text)"
  B="$(printf 'pipe into cmdsubst\n' | oracle_sha256_text)"
  [ "$A" = "$B" ] || exit 1
  C="$(sha256_file "$TMP_DIR/plain.txt")"
  D="$(cat "$TMP_DIR/plain.txt" | sha256_text)"
  [ "$C" = "$D" ] || exit 1
) || fail "combined smoke under set -euo pipefail"

# ============ 7) 空 tree OID 随 Git 对象格式变化 ==========
SHA1_REPO="$TMP_DIR/git-sha1"
git init -q "$SHA1_REPO"
SHA1_EMPTY="$(git_empty_tree_oid "$SHA1_REPO")"
expect_eq "$SHA1_EMPTY" "4b825dc642cb6eb9a060e54bf8d69288fbee4904" "SHA-1 empty tree oid"

SHA256_REPO="$TMP_DIR/git-sha256"
if git init -q --object-format=sha256 "$SHA256_REPO" 2>/dev/null; then
  SHA256_EMPTY="$(git_empty_tree_oid "$SHA256_REPO")"
  [ "${#SHA256_EMPTY}" -eq 64 ] || fail "SHA-256 empty tree oid must have 64 hex chars"
  [ "$SHA256_EMPTY" != "$SHA1_EMPTY" ] || fail "SHA-256 empty tree oid must differ from SHA-1"
fi

echo "PASS: core lib common.sh sha256 回退链与 Git 空 tree OID"
