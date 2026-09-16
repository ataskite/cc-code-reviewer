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

# 返回当前 Git 仓库对象格式对应的空 tree OID。禁止硬编码 SHA-1 的
# 4b825d...：SHA-256 仓库的空 tree OID 为 64 位且值不同。
git_empty_tree_oid() {
  local project_dir="${1:?project directory required}"
  printf '' | git -C "$project_dir" hash-object -t tree --stdin
}

# 从 stdin 读取 NUL 分隔的文件路径，输出 NUL 分隔的记录：<原始路径><RS(0x1e)><换行符数量>。
# 行数在单个 perl 进程内按 \n 字节计数：与 wc -l 口径逐字节一致（末行无换行符不计入），
# 零 fork，也不经过 wc 的文本输出边界——含换行符/前导空格/名为 total 的路径都安全。
# 路径不可读时 fail-loud（BATCH_WC_OPEN_FAILED / BATCH_WC_READ_FAILED），禁止静默错位。
batch_wc_lines_nul() {
  perl -e '
    my $raw = do { local $/; <STDIN> };
    for my $path (grep { length } split(/\0/, $raw, -1)) {
      open(my $fh, "<", $path) or die "BATCH_WC_OPEN_FAILED: $path: $!\n";
      binmode($fh);
      my $count = 0;
      while (1) {
        my $n = sysread($fh, my $buf, 1048576);
        die "BATCH_WC_READ_FAILED: $path: $!\n" unless defined $n;
        last if $n == 0;
        $count += ($buf =~ tr/\n//);
      }
      close($fh);
      print $path, "\x1e", $count, "\0";
    }
  '
}
