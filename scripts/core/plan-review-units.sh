#!/bin/bash
set -euo pipefail

# Build deterministic, conservative cross-file units.  Only direct relative
# imports (frontend/Python) and unambiguous Java class imports are grouped;
# every other file stays a one-file unit.  This keeps the association signal
# useful without inventing framework semantics in the shared kernel.

PROJECT_DIR="${1:?请输入项目路径}"
LANGUAGE_ID="${2:?请输入语言 ID}"
SOURCE_MANIFEST="${3:?请输入 source manifest 路径}"
OUTPUT_PATH="${4:?请输入输出路径}"
[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
[ -r "$SOURCE_MANIFEST" ] || { echo "SOURCE_MANIFEST_NOT_READABLE=$SOURCE_MANIFEST" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
mkdir -p "$(dirname "$OUTPUT_PATH")"

perl -MJSON::PP -MFile::Basename=dirname,basename -MFile::Spec -MCwd=abs_path -e '
  use strict; use warnings;
  my ($project,$lang,$manifest,$out)=@ARGV;
  open my $mf,"<",$manifest or die $!; my @f=grep { chomp; $_ ne "" } <$mf>; close $mf;
  @f = map { abs_path($_) || $_ } @f;
  my (%idx,%parent,%bybase); for my $i (0..$#f) { $idx{$f[$i]}=$i; $parent{$i}=$i; push @{$bybase{basename($f[$i])}},$i; }
  sub root { my $x=shift; while ($parent{$x} != $x) { $x=$parent{$x}; } return $x; }
  sub joinset { my ($a,$b)=@_; $a=root($a); $b=root($b); $parent{$b}=$a if $a!=$b; }
  sub candidate { my ($base,$stem)=@_; for my $ext (qw(.ts .tsx .js .jsx .vue .mjs .cjs .py .java)) { return "$base$ext" if exists $idx{"$base$ext"}; return "$base/index$ext" if exists $idx{"$base/index$ext"}; } return ""; }
  for my $i (0..$#f) {
    open my $fh,"<",$f[$i] or next; my $content=""; $content .= $_ while <$fh>; close $fh;
    my $dir=dirname($f[$i]);
    while ($content =~ /(?:from\s+|import\s*(?:[^;]*?\s+from\s+)?)[\x27"](\.{1,2}\/[^\x27"]+)[\x27"]/g) { my $c=candidate(File::Spec->canonpath("$dir/$1"),$1); joinset($i,$idx{$c}) if $c ne ""; }
    if ($lang eq "python") { while ($content =~ /^\s*from\s+\.(\w+(?:\.\w+)*)\s+import/mg) { my $c="$dir/" . ($1 =~ s!\.!/!gr) . ".py"; joinset($i,$idx{$c}) if exists $idx{$c}; } }
    if ($lang eq "java") { while ($content =~ /^\s*import\s+([\w.]+)\s*;/mg) { my $b=$1; $b =~ s!.*\.!!; my $arr=$bybase{"$b.java"}; joinset($i,$arr->[0]) if $arr && @$arr == 1; } }
  }
  my %groups; push @{$groups{root($_)}}, $_ for 0..$#f;
  my @units; my $n=0; for my $r (sort { $f[$groups{$a}[0]] cmp $f[$groups{$b}[0]] } keys %groups) { $n++; my @members=sort map {$f[$_]} @{$groups{$r}}; push @units,{unit_id=>sprintf("unit-%03d",$n),files=>\@members}; }
  open my $of,">",$out or die $!; print $of JSON::PP->new->canonical->pretty->encode({schema_version=>1,association_enabled=>JSON::PP::true,language_id=>$lang,units=>\@units});
' "$PROJECT_DIR" "$LANGUAGE_ID" "$SOURCE_MANIFEST" "$OUTPUT_PATH"

echo "REVIEW_UNITS_PATH=$OUTPUT_PATH"
echo "REVIEW_UNIT_COUNT=$(perl -MJSON::PP -e 'local $/; print scalar @{decode_json(<>)->{units}}' "$OUTPUT_PATH")"
