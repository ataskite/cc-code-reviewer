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
#
# YAML subset: only the fixed shape above is supported — top-level `version`,
# a `rules:` list whose entries each have `name`, `paths` (glob list),
# `instruction` (single-line string) and optional `merge_language_rule`.
# Block scalars, multi-line instructions, anchors, flow sequences and inline
# `#` comments inside values are NOT supported; malformed input is rejected.
# Keep instructions on one line; use `;` or `。` to separate points.
#
# Filetype checklists (additive overlay): scripts/core/filetype-rule-map.json
# maps ordered path patterns onto focused inspection checklists stored in
# references/review-checklists/<checklist>.md.  Patterns use the same
# normalized glob semantics as project rules (`**`, `*`, `?`, case
# insensitive; `{a,b}` brace alternation is added) and match against the same
# input file list as project rules (manifest lines or review-input
# selected=true items).  The FIRST matching pattern wins per file, so each
# file lands in at most one group.  Matched groups are emitted additively as
# "filetype_checklists" — only groups with >= 1 matched file appear, ordered
# deterministically by first pattern occurrence in the map.  Each group
# carries the absolute checklist doc path plus the inline doc text as
# "content", so sub-agents stay single-read.  Missing/broken map file,
# unreadable doc, disabled patterns or zero matches all fail open: the field
# is omitted and every legacy output byte stays exactly what pre-overlay runs
# produced.

PROJECT_DIR="${1:?请输入项目路径}"
SOURCE_INPUT="${2:?请输入 source manifest 或 review-input.json 路径}"
OUTPUT_PATH="${3:?请输入输出路径}"
RULES_PATH="${4:-$PROJECT_DIR/.cc-code-reviewer/review-rules.yml}"
INPUT_KIND="${5:-manifest}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
[ -r "$SOURCE_INPUT" ] || { echo "SOURCE_INPUT_NOT_READABLE=$SOURCE_INPUT" >&2; exit 1; }
case "$INPUT_KIND" in manifest|review-input) ;; *) echo "RULE_INPUT_KIND_INVALID=$INPUT_KIND" >&2; exit 1 ;; esac
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# Map/checklists live beside the plugin itself so resolution never depends on
# cwd; tests may point CC_CODE_REVIEWER_FILETYPE_MAP_PATH elsewhere.
PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
CHECKLISTS_DIR="$PLUGIN_ROOT/references/review-checklists"
FILETYPE_MAP="${CC_CODE_REVIEWER_FILETYPE_MAP_PATH:-$PLUGIN_ROOT/scripts/core/filetype-rule-map.json}"
mkdir -p "$(dirname "$OUTPUT_PATH")"

if [ ! -f "$RULES_PATH" ] && [ ! -f "$FILETYPE_MAP" ]; then
  printf '{"schema_version":1,"rules_path":"","rule_count":0,"files":[]}\n' > "$OUTPUT_PATH"
  echo "REVIEW_RULES_PATH="; echo "REVIEW_RULES_COUNT=0"; echo "REVIEW_RULES_RESOLVED_PATH=$OUTPUT_PATH"
  exit 0
fi

perl -MJSON::PP -MCwd=abs_path -e '
  use strict; use warnings;
  my ($project,$input,$rules,$out,$input_kind,$ft_map,$cl_dir)=@ARGV;
  my $rules_missing = (-f $rules) ? 0 : 1;
  my @rules; my $cur; my $in_paths=0; my $seen_rules=0;
  if (!$rules_missing) {
    open my $rf, "<", $rules or die "read rules: $!";
    while (my $line=<$rf>) {
      chomp $line; $line =~ s/\r$//;
      next if $line =~ /^\s*(?:#|$)/;
      if (!$cur && $line =~ /^\s*version:\s*1\s*$/) { next; }
      if (!$cur && $line =~ /^\s*rules:\s*$/) { $seen_rules=1; next; }
      if ($line =~ /^\s*-\s+name:\s*(.+?)\s*$/) {
        die "rules header required\n" unless $seen_rules;
        push @rules,$cur if $cur;
        $cur={name=>unquote($1),paths=>[],instruction=>"",merge_language_rule=>JSON::PP::true};
        $in_paths=0;
        next;
      }
      die "unsupported YAML syntax: $line\n" unless $cur;
      if ($line =~ /^\s*paths:\s*$/) { $in_paths=1; next; }
      if ($line =~ /^\s*paths:\s*\[/) { die "flow sequences are not supported\n"; }
      if ($in_paths && $line =~ /^\s*-\s+(.+?)\s*$/) {
        my $raw=$1; my $path=unquote($raw);
        die "anchors are not supported\n" if $raw =~ /^\s*[&*][A-Za-z_]/;
        die "flow sequences are not supported\n" if $raw =~ /^\s*[\[\{]/;
        die "inline comments are not supported\n" if $path =~ /#/;
        push @{$cur->{paths}}, $path;
        next;
      }
      $in_paths=0;
      if ($line =~ /^\s*instruction:\s*(.+?)\s*$/) {
        my $raw=$1; my $instruction=unquote($raw);
        die "anchors are not supported\n" if $raw =~ /^\s*[&*][A-Za-z_]/;
        die "block scalars are not supported\n" if $instruction eq "|" || $instruction eq ">";
        die "inline comments are not supported\n" if $instruction =~ /#/;
        $cur->{instruction}=$instruction;
        next;
      }
      if ($line =~ /^\s*merge_language_rule:\s*(true|false)\s*$/i) { $cur->{merge_language_rule}=lc($1) eq "true" ? JSON::PP::true : JSON::PP::false; next; }
      die "unsupported YAML syntax: $line\n";
    }
    close $rf;
  }
  push @rules,$cur if $cur;
  for my $r (@rules) { die "rule name required\n" unless $r->{name}; die "rule $r->{name} needs paths\n" unless @{$r->{paths}}; die "rule $r->{name} needs instruction\n" unless $r->{instruction}; }
  my @files;
  if ($input_kind eq "review-input") {
    open my $inf,"<",$input or die "read review input: $!"; local $/; my $d=decode_json(<$inf>); close $inf;
    for my $item (@{$d->{items}||[]}) {
      next unless ref($item) eq "HASH" && $item->{selected};
      my $path=$item->{path}//next;
      push @files, ($path =~ m!^/! ? $path : "$project/$path");
    }
  } else {
    open my $mf,"<",$input or die "read manifest: $!";
    @files=grep { chomp; s/\r$//; /\S/ } <$mf>; close $mf;
  }
  my @mapped;
  for my $abs (@files) {
    my $real=abs_path($abs) || $abs; my $rel=$real; $rel =~ s/^\Q$project\E\/?//;
    my @hits;
    for my $r (@rules) { push @hits,{name=>$r->{name},instruction=>$r->{instruction},merge_language_rule=>$r->{merge_language_rule}} if grep { glob_match($_,$rel) } @{$r->{paths}}; }
    push @mapped,{path=>$rel,absolute_path=>$abs,rules=>\@hits};
  }

  # Built-in filetype checklist overlay.  Every failure mode fails open: an
  # unreadable map, invalid JSON, disabled/empty entries, unreadable docs, or
  # unmatched inputs simply yield zero groups and omit the additive key.
  my @ft_groups;
  eval { @ft_groups = build_filetype_groups(\@mapped, $ft_map, $cl_dir); };
  undef $@;

  open my $of,">",$out or die "write output: $!";
  if ($rules_missing && !@ft_groups) {
    # Legacy byte shape: no project rules file and no checklist hit anywhere.
    print $of qq{{"schema_version":1,"rules_path":"","rule_count":0,"files":[]}\n};
  } else {
    my %payload=(schema_version=>1,rules_path=>$rules_missing?"":$rules,rule_count=>scalar(@rules),files=>\@mapped);
    $payload{filetype_checklists}=\@ft_groups if @ft_groups;
    print $of JSON::PP->new->canonical->pretty->encode(\%payload);
  }
  close $of;

  sub build_filetype_groups {
    my ($mapped,$map_path,$checklist_dir)=@_;
    return () unless defined $map_path && length $map_path && -f $map_path;
    local $/;
    open my $mapfh,"<",$map_path or return ();
    my $map_raw=<$mapfh>;
    close $mapfh;
    my $doc=decode_json($map_raw);
    return () unless ref($doc) eq "HASH";
    my $entries=$doc->{patterns};
    return () unless ref($entries) eq "ARRAY" && @$entries;
    my @compiled;
    for my $ent (@$entries) {
      next unless ref($ent) eq "HASH";
      my $pat=$ent->{pattern}//"";
      my $checklist=$ent->{checklist}//"";
      $pat =~ s/\s+$//; $pat =~ s/^\s+//;
      next unless length $pat && length $checklist;
      next if defined $ent->{enabled} && !$ent->{enabled};
      push @compiled,{pattern=>$pat,checklist=>$checklist,res=>compile_ft_globs($pat)};
    }
    return () unless @compiled;
    my %by_pattern; my @order;
    for my $f (@$mapped) {
      my $rel=$f->{path};
      next unless defined $rel && length $rel;
      for my $c (@compiled) {
        next unless grep { $rel =~ $_ } @{$c->{res}};
        unless (exists $by_pattern{$c->{pattern}}) {
          $by_pattern{$c->{pattern}}={pattern=>$c->{pattern},checklist=>$c->{checklist},files=>[]};
          push @order,$c->{pattern};
        }
        push @{$by_pattern{$c->{pattern}}{files}}, $rel;
        last;
      }
    }
    my @groups;
    for my $key (@order) {
      my $g=$by_pattern{$key};
      next unless @{$g->{files}};
      my $doc_path="$checklist_dir/$g->{checklist}.md";
      next unless -r $doc_path;
      my $content;
      {
        local $/;
        open my $dfh,"<",$doc_path or next;
        $content=<$dfh>;
        close $dfh;
      }
      next unless defined $content;
      push @groups,{pattern=>$g->{pattern},checklist=>$g->{checklist},doc=>$doc_path,content=>$content,files=>[sort @{$g->{files}}]};
    }
    return @groups;
  }

  # Glob compiler for filetype patterns: normalized like glob_match (** /
  # * / ?, case insensitive, evaluated against "/"-separated relative
  # paths), with two additions:
  #   - `{a,b}` brace alternation expands before compilation;
  #   - a leading "a/**/" or "**/" segment also matches with ZERO directory
  #     levels, so root-level files such as pom.xml satisfy "**/pom.xml"
  #     (the legacy per-rule matcher keeps its historical semantics).
  sub expand_braces {
    my ($p)=@_;
    if ($p =~ /^([^{}]*)\{([^{}]+)\}(.*)$/s) {
      my @out;
      for my $alt (split /,/,$2) { push @out,@{expand_braces("$1$alt$3")}; }
      return \@out;
    }
    return [$p];
  }

  sub compile_ft_globs {
    my ($p)=@_;
    my @rx;
    for my $alt (@{expand_braces($p)}) {
      my $q=quotemeta($alt);
      # quotemeta("\*\*\/") 为 \*\*\/：先整体替换带尾随反斜杠斜杠的片段，
      # 让 a/**/y 与开头 **/ 同样允许零层目录（根级 pom.xml 满足 **/pom.xml）。
      $q =~ s{\\\*\\\*\\/}{(?:[^\/]+\/)*}g;
      $q =~ s{\\\*\\\*}{.*}g;               # 剩余裸 ** 跨目录
      $q =~ s{\\\*}{[^\/]*}g;
      $q =~ s{\\\?}{[^\/]}g;
      push @rx, qr/^$q$/i;
    }
    return \@rx;
  }

  sub unquote { my $x=shift; $x =~ s/^\s+|\s+$//g; $x =~ s/^(["\x27])|(["\x27])$//g; return $x; }
  sub glob_match { my ($p,$s)=@_; my $q=quotemeta($p); $q =~ s/\\\*\\\*/.*/g; $q =~ s/\\\*/[^\/]*/g; $q =~ s/\\\?/[^\/]/g; return $s =~ /^$q$/i; }
' "$PROJECT_DIR" "$SOURCE_INPUT" "$RULES_PATH" "$OUTPUT_PATH" "$INPUT_KIND" "$FILETYPE_MAP" "$CHECKLISTS_DIR"

RULE_COUNT="$(perl -MJSON::PP -e 'local $/; print decode_json(<>)->{rule_count}' "$OUTPUT_PATH")"
# Legacy stdout contract: a missing rules file echoes an empty REVIEW_RULES_PATH.
if [ -f "$RULES_PATH" ]; then
  echo "REVIEW_RULES_PATH=$RULES_PATH"
else
  echo "REVIEW_RULES_PATH="
fi
echo "REVIEW_RULES_COUNT=$RULE_COUNT"
echo "REVIEW_RULES_RESOLVED_PATH=$OUTPUT_PATH"
