#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:?请输入项目路径}"
REVIEW_INPUT_PATH="${2:?请输入冻结审查输入路径}"
OUTPUT_PATH="${3:?请输入语义分组输出路径}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
[ -r "$REVIEW_INPUT_PATH" ] || { echo "REVIEW_INPUT_NOT_READABLE=$REVIEW_INPUT_PATH" >&2; exit 1; }

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
mkdir -p "$(dirname "$OUTPUT_PATH")"
TMP_OUTPUT="${OUTPUT_PATH}.tmp.$$"
trap 'rm -f "$TMP_OUTPUT"' EXIT

perl -MJSON::PP -MFile::Spec -e '
  use strict;
  use warnings;
  use utf8;

  my ($project, $input, $output) = @ARGV;
  open my $fh, "<:raw", $input or die "REVIEW_INPUT_READ_ERROR=$input\n";
  local $/;
  my $data = eval { decode_json(<$fh>) };
  die "REVIEW_INPUT_JSON_INVALID=$input\n" unless defined $data && ref($data) eq "HASH";
  my $items = $data->{items};
  die "REVIEW_INPUT_ITEMS_INVALID=$input\n" unless ref($items) eq "ARRAY";

  my @selected = grep { ref($_) eq "HASH" && $_->{selected} } @$items;
  open my $out, ">:encoding(UTF-8)", $output or die "SEMANTIC_GROUPS_WRITE_ERROR=$output\n";
  # 三个及以下变更文件不生成分组，避免为小变更制造额外上下文结构。
  if (@selected <= 3) {
    close $out or die "SEMANTIC_GROUPS_WRITE_ERROR=$output\n";
    exit 0;
  }

  sub relative_path {
    my ($path) = @_;
    return "" unless defined $path && length $path;
    return "" if File::Spec->file_name_is_absolute($path);
    $path =~ s#^\./##;
    return "" if $path eq "" || $path =~ m#(?:^|/)\.\.(?:/|$)#;
    return $path;
  }

  sub family_stem {
    my ($path) = @_;
    my ($name) = $path =~ m#([^/]+)$#;
    return "" unless defined $name;
    $name =~ s/\.(?:tsx?|jsx?|vue|py|java|kt|go|rb)$//i;
    # 同一文件族的实现、测试和规格变体共享一个稳定 stem。
    $name =~ s/(?:[._-]?(?:test|tests|spec|specs|impl|implementation))$//i;
    return $name;
  }

  my %groups;
  for my $item (@selected) {
    my $path = relative_path($item->{path});
    next unless length $path;
    my $stem = family_stem($path);
    next unless length $stem;
    my ($parent) = $path =~ m#^(.*)/[^/]+$#;
    $parent //= "";
    my $key = "group:$parent/$stem";
    $key =~ s/[\t\r\n]+/_/g;
    push @{$groups{$key}}, $path;
  }

  for my $key (sort keys %groups) {
    my %seen;
    my @paths = sort grep { !$seen{$_}++ } @{$groups{$key}};
    next unless @paths >= 2;
    print {$out} "$key\t$_\n" for @paths;
  }
  close $out or die "SEMANTIC_GROUPS_WRITE_ERROR=$output\n";
' "$PROJECT_DIR" "$REVIEW_INPUT_PATH" "$TMP_OUTPUT"

mv "$TMP_OUTPUT" "$OUTPUT_PATH"
trap - EXIT
echo "SEMANTIC_GROUPS_PATH=$OUTPUT_PATH"
