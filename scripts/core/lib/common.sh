#!/bin/bash
# 共享 shell 助手（由 scripts/core 与 scripts/languages/* 的脚本 source）。
# 本文件只定义函数、无任何副作用，在 `set -euo pipefail` 调用方下安全；
# 不得重复实现本地副本——需要 sha256 时一律 source 本库。
#
# sha256 三级回退链（全仓库唯一实现，历史出处 validate-resume-input.sh）：
#   1) shasum -a 256（macOS 自带）
#   2) sha256sum（Linux 发行版常见）
#   3) perl -MDigest::SHA（核心模块，最后兜底）
# 计算对象恒为字节本身：sha256_file 取文件路径参数；sha256_text 哈希 stdin。

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else perl -MDigest::SHA -e 'my $f = shift; my $d = Digest::SHA->new(256); $d->addfile($f); print $d->hexdigest, "\n"' "$1"; fi
}

sha256_text() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else perl -MDigest::SHA -e 'my $d = Digest::SHA->new(256); while (read(STDIN, my $buf, 65536)) { $d->add($buf); } print $d->hexdigest, "\n"'; fi
}
