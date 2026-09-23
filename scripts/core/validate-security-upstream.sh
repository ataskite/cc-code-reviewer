#!/bin/bash
set -euo pipefail

# Offline integrity gate for the frozen OWASP baseline. This is used by the
# catalog validator during Security runtime; it never reads or fetches URLs.
if [ "$#" -gt 1 ]; then
  echo "ERROR_SECURITY_UPSTREAM_USAGE=参数须为可选 <upstream_root>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_ROOT="${1:-${CC_CODE_REVIEWER_UPSTREAM_DIR:-$(cd "$SCRIPT_DIR/../../references/security/upstream" && pwd)}}"
[ -d "$UPSTREAM_ROOT" ] || { echo "ERROR_SECURITY_UPSTREAM_NOT_FOUND=$UPSTREAM_ROOT" >&2; exit 1; }
UPSTREAM_ROOT="$(cd "$UPSTREAM_ROOT" && pwd -P)"

perl -MJSON::PP -MDigest::SHA -MCwd=abs_path -MFile::Spec -e '
  use strict; use warnings;
  my ($root) = @ARGV;
  sub failx { die "ERROR_SECURITY_UPSTREAM_@_\n"; }
  sub slurp { my ($p)=@_; open my $f,"<:raw",$p or failx("READ",$p); local $/; my $s=<$f>; close $f; return $s; }
  sub sha256_file { my ($p)=@_; my $d=Digest::SHA->new(256); $d->addfile($p,"b"); return $d->hexdigest; }
  sub under_root { my ($path)=@_; my $a=abs_path($path); return defined($a) && ($a eq $root || index($a, "$root/") == 0); }

  my $manifest_path = "$root/manifest.json";
  failx("MANIFEST_MISSING", $manifest_path) unless -f $manifest_path && under_root($manifest_path);
  my $manifest = eval { decode_json(slurp($manifest_path)) };
  failx("MANIFEST_INVALID", $manifest_path) if $@ || ref($manifest) ne "HASH";
  failx("SCHEMA_INVALID", "schema_version must be 1") unless ($manifest->{schema_version} // 0) == 1;
  my $sources = $manifest->{sources};
  failx("SOURCES_INVALID", "sources must be a non-empty array") unless ref($sources) eq "ARRAY" && @$sources;

  my %expected = map { $_ => 1 } qw(owasp-asvs owasp-top10 owasp-api-top10 owasp-nodejs-cheat-sheet);
  my (%seen_source, %all_paths, %files_by_root);
  my $file_count = 0;
  for my $source (@$sources) {
    failx("SOURCE_INVALID", "entry must be an object") unless ref($source) eq "HASH";
    my $id = $source->{id} // "";
    failx("SOURCE_INVALID", "duplicate or unknown source: $id") if !$expected{$id} || $seen_source{$id}++;
    my $local_root = $source->{local_root} // "";
    failx("PATH_INVALID", "local_root=$local_root") if !length($local_root) || File::Spec->file_name_is_absolute($local_root) || $local_root =~ m{(^|/)\.\.(/|$)};
    my $files = $source->{files};
    failx("FILES_INVALID", "source=$id") unless ref($files) eq "ARRAY" && @$files;
    for my $entry (@$files) {
      failx("FILE_INVALID", "source=$id") unless ref($entry) eq "HASH";
      my $rel = $entry->{path} // "";
      my $hash = $entry->{sha256} // "";
      failx("PATH_INVALID", "path=$rel") if !length($rel) || File::Spec->file_name_is_absolute($rel) || $rel =~ m{(^|/)\.\.(/|$)};
      failx("HASH_INVALID", "path=$rel") unless $hash =~ /^[0-9a-f]{64}$/;
      failx("DUPLICATE_PATH", $rel) if $all_paths{$rel}++;
      my $path = File::Spec->catfile($root, split m{/}, $rel);
      failx("FILE_MISSING", $rel) unless -f $path && under_root($path);
      my $actual = sha256_file($path);
      failx("HASH_MISMATCH", "$rel expected=$hash actual=$actual") unless $actual eq $hash;
      my $sum_root = File::Spec->catfile($root, $local_root);
      my $base = $rel; $base =~ s{^.*/}{};
      $files_by_root{$sum_root}{$base} = $hash;
      $file_count++;
    }
  }
  failx("SOURCES_INVALID", "manifest must declare all four pinned sources") unless keys(%seen_source) == 4;

  for my $sum_root (sort keys %files_by_root) {
    failx("SOURCE_ROOT_MISSING", $sum_root) unless -d $sum_root && under_root($sum_root);
    my $sums_path = "$sum_root/SHA256SUMS";
    my $notice_path = "$sum_root/NOTICE.md";
    failx("SUMS_MISSING", $sums_path) unless -f $sums_path && under_root($sums_path);
    failx("NOTICE_MISSING", $notice_path) unless -f $notice_path && under_root($notice_path);
    my %actual;
    for my $line (split /\n/, slurp($sums_path)) {
      next if $line =~ /^\s*$/;
      $line =~ /^([0-9a-f]{64})  (\S.*)$/ or failx("SUMS_FORMAT", "$sums_path: $line");
      my ($hash,$name)=($1,$2);
      failx("SUMS_DUPLICATE", "$sums_path: $name") if $actual{$name}++;
      exists $files_by_root{$sum_root}{$name} or failx("SUMS_UNDECLARED", "$sums_path: $name");
      $files_by_root{$sum_root}{$name} eq $hash or failx("SUMS_MISMATCH", "$sums_path: $name");
    }
    for my $name (keys %{ $files_by_root{$sum_root} }) {
      $actual{$name} or failx("SUMS_ENTRY_MISSING", "$sums_path: $name");
    }
  }
  print "SECURITY_UPSTREAM_OK=SOURCES=" . scalar(keys %seen_source) . " FILES=$file_count\n";
' "$UPSTREAM_ROOT"
