#!/bin/bash
set -euo pipefail

# Derive structural review units from the immutable selected input. This
# adapter intentionally knows nothing about security semantics: association is
# delegated to plan-review-units.sh and remains purely structural.

PROJECT_DIR="${1:?请输入项目路径}"
LANGUAGE_ID="${2:?请输入语言 ID}"
REVIEW_INPUT_PATH="${3:?请输入审查输入路径}"
OUTPUT_PATH="${4:?请输入输出路径}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
[ -r "$REVIEW_INPUT_PATH" ] || { echo "REVIEW_INPUT_NOT_READABLE=$REVIEW_INPUT_PATH" >&2; exit 1; }
case "$LANGUAGE_ID" in
  java|frontend|python) ;;
  *) echo "UNSUPPORTED_LANGUAGE_ID=$LANGUAGE_ID" >&2; exit 1 ;;
esac

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
mkdir -p "$(dirname "$OUTPUT_PATH")"

MANIFEST="$(mktemp "${TMPDIR:-/tmp}/cc-review-context.XXXXXX")"
trap 'rm -f "$MANIFEST"' EXIT

perl -MJSON::PP -MFile::Spec -e '
  use strict; use warnings;
  my ($project, $input) = @ARGV;
  local $/;
  open my $fh, "<", $input or die "REVIEW_INPUT_NOT_READABLE=$input\n";
  my $data = decode_json(<$fh>);
  close $fh;
  for my $item (@{$data->{items} || []}) {
    next unless $item->{selected};
    my $relative = $item->{path} // "";
    die "INVALID_REVIEW_INPUT_PATH=$relative\n"
      if $relative eq "" || File::Spec->file_name_is_absolute($relative) || $relative =~ m{(?:^|/)\.\.(?:/|$)};
    my $absolute = File::Spec->catfile($project, split m{/}, $relative);
    die "SELECTED_REVIEW_FILE_NOT_FOUND=$relative\n" unless -f $absolute;
    print "$absolute\n";
  }
' "$PROJECT_DIR" "$REVIEW_INPUT_PATH" > "$MANIFEST"

[ -s "$MANIFEST" ] || { echo "NO_SELECTED_REVIEW_FILES=$REVIEW_INPUT_PATH" >&2; exit 1; }

bash "$SCRIPT_DIR/plan-review-units.sh" \
  "$PROJECT_DIR" "$LANGUAGE_ID" "$MANIFEST" "$OUTPUT_PATH"
