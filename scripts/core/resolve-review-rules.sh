#!/bin/bash
set -euo pipefail

# Resolve the deliberately small project rule format into machine-readable
# per-file instructions.  It is separate from ignore/issues.yml: these rules
# focus review attention; they never suppress findings.
#
# .cc-code-reviewer/review-rules.yml:
# version: 1
# rules:
#   - name: api-boundary
#     paths:
#       - "**/controller/**"
#     instruction: "核对鉴权、输入校验和错误契约"
#     merge_language_rule: true

PROJECT_DIR="${1:?请输入项目路径}"
SOURCE_MANIFEST="${2:?请输入 source manifest 路径}"
OUTPUT_PATH="${3:?请输入输出路径}"
RULES_PATH="${4:-$PROJECT_DIR/.cc-code-reviewer/review-rules.yml}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
[ -r "$SOURCE_MANIFEST" ] || { echo "SOURCE_MANIFEST_NOT_READABLE=$SOURCE_MANIFEST" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
mkdir -p "$(dirname "$OUTPUT_PATH")"

if [ ! -f "$RULES_PATH" ]; then
  printf '{"schema_version":1,"rules_path":"","rule_count":0,"files":[]}\n' > "$OUTPUT_PATH"
  echo "REVIEW_RULES_PATH="; echo "REVIEW_RULES_COUNT=0"; echo "REVIEW_RULES_RESOLVED_PATH=$OUTPUT_PATH"
  exit 0
fi

perl -MJSON::PP -MCwd=abs_path -e '
  use strict; use warnings;
  my ($project,$manifest,$rules,$out)=@ARGV;
  open my $rf, "<", $rules or die "read rules: $!";
  my @rules; my $cur; my $in_paths=0;
  while (my $line=<$rf>) {
    chomp $line; $line =~ s/\r$//;
    next if $line =~ /^\s*(?:#|$)/;
    if ($line =~ /^\s*-\s+name:\s*(.+?)\s*$/) { push @rules,$cur if $cur; $cur={name=>unquote($1),paths=>[],instruction=>"",merge_language_rule=>JSON::PP::true}; $in_paths=0; next; }
    next unless $cur;
    if ($line =~ /^\s*paths:\s*$/) { $in_paths=1; next; }
    if ($in_paths && $line =~ /^\s*-\s+(.+?)\s*$/) { push @{$cur->{paths}}, unquote($1); next; }
    $in_paths=0;
    if ($line =~ /^\s*instruction:\s*(.+?)\s*$/) { $cur->{instruction}=unquote($1); next; }
    if ($line =~ /^\s*merge_language_rule:\s*(true|false)\s*$/i) { $cur->{merge_language_rule}=lc($1) eq "true" ? JSON::PP::true : JSON::PP::false; next; }
  }
  push @rules,$cur if $cur;
  for my $r (@rules) { die "rule name required\n" unless $r->{name}; die "rule $r->{name} needs paths\n" unless @{$r->{paths}}; die "rule $r->{name} needs instruction\n" unless $r->{instruction}; }
  open my $mf,"<",$manifest or die "read manifest: $!"; my @files=grep { chomp; $_ ne "" } <$mf>; close $mf;
  my @mapped;
  for my $abs (@files) {
    my $real=abs_path($abs) || $abs; my $rel=$real; $rel =~ s/^\Q$project\E\/?//;
    my @hits;
    for my $r (@rules) { push @hits,{name=>$r->{name},instruction=>$r->{instruction},merge_language_rule=>$r->{merge_language_rule}} if grep { glob_match($_,$rel) } @{$r->{paths}}; }
    push @mapped,{path=>$rel,absolute_path=>$abs,rules=>\@hits};
  }
  open my $of,">",$out or die "write output: $!";
  print $of JSON::PP->new->canonical->pretty->encode({schema_version=>1,rules_path=>$rules,rule_count=>scalar(@rules),files=>\@mapped});
  sub unquote { my $x=shift; $x =~ s/^\s+|\s+$//g; $x =~ s/^(["\x27])|(["\x27])$//g; return $x; }
  sub glob_match { my ($p,$s)=@_; my $q=quotemeta($p); $q =~ s/\\\*\\\*/.*/g; $q =~ s/\\\*/[^\/]*/g; $q =~ s/\\\?/[^\/]/g; return $s =~ /^$q$/i; }
' "$PROJECT_DIR" "$SOURCE_MANIFEST" "$RULES_PATH" "$OUTPUT_PATH"

RULE_COUNT="$(perl -MJSON::PP -e 'local $/; print decode_json(<>)->{rule_count}' "$OUTPUT_PATH")"
echo "REVIEW_RULES_PATH=$RULES_PATH"
echo "REVIEW_RULES_COUNT=$RULE_COUNT"
echo "REVIEW_RULES_RESOLVED_PATH=$OUTPUT_PATH"
