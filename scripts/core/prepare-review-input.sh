#!/bin/bash
set -euo pipefail

# Freeze the formal input of one review run.  This is deliberately independent
# from an agent prompt: later planners, agents and reports consume the same
# file list instead of rediscovering it themselves.
#
# Usage:
#   prepare-review-input.sh PROJECT_DIR LANGUAGE_ID MODE [COMMIT_COUNT] [SOURCE_MANIFEST] [OUTPUT_PATH]
# MODE: incremental | full | scoped

PROJECT_DIR="${1:?请输入项目路径}"
LANGUAGE_ID="${2:?请输入语言 ID}"
MODE="${3:?请输入审查输入模式}"
COMMIT_COUNT="${4:-0}"
SOURCE_MANIFEST="${5:-}"
OUTPUT_PATH="${6:-}"

[ -d "$PROJECT_DIR" ] || { echo "PROJECT_DIR_NOT_FOUND=$PROJECT_DIR" >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

case "$MODE" in incremental|full|scoped) ;; *) echo "REVIEW_INPUT_MODE_INVALID=$MODE" >&2; exit 1 ;; esac
case "$COMMIT_COUNT" in ''|*[!0-9]*) echo "COMMIT_COUNT_INVALID=$COMMIT_COUNT" >&2; exit 1 ;; esac
[ -z "$SOURCE_MANIFEST" ] || [ -r "$SOURCE_MANIFEST" ] || { echo "SOURCE_MANIFEST_NOT_READABLE=$SOURCE_MANIFEST" >&2; exit 1; }

json_escape() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'; }
sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}
sha256_text() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  else sha256sum | awk '{print $1}'; fi
}
relative_path() {
  local candidate="$1" canonical
  if [ -e "$candidate" ]; then
    canonical="$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")"
    candidate="$canonical"
  fi
  case "$candidate" in "$PROJECT_DIR"/*) printf '%s\n' "${candidate#"$PROJECT_DIR"/}" ;; *) printf '%s\n' "$candidate" ;; esac
}

RUN_STAMP="${CC_CODE_REVIEWER_RUN_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
if [ -z "$OUTPUT_PATH" ]; then
  OUTPUT_PATH="$PROJECT_DIR/.cc-code-reviewer/inputs/review-input-$RUN_STAMP-$LANGUAGE_ID-$MODE.json"
fi
mkdir -p "$(dirname "$OUTPUT_PATH")"

ITEMS_TSV="$(mktemp "${TMPDIR:-/tmp}/cc-review-input.XXXXXX")"
trap 'rm -f "$ITEMS_TSV" "$ITEMS_TSV.sorted"' EXIT

BASE_REF=""; HEAD_REF=""; GIT_REPO=false
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_REPO=true
  HEAD_REF="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)"
fi

manifest_has_path() {
  local candidate="$1" entry
  [ -n "$SOURCE_MANIFEST" ] || return 0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ "$(relative_path "$entry")" = "$candidate" ] && return 0
  done < "$SOURCE_MANIFEST"
  return 1
}

append_item() {
  local path="$1" change="$2" old_path="${3:-}" selected reason insertions deletions fingerprint
  [ -n "$path" ] || return 0
  selected=true; reason=""
  if [ -n "$SOURCE_MANIFEST" ] && ! manifest_has_path "$path"; then
    selected=false; reason="outside-source-manifest"
  fi
  if [ "$change" = deleted ]; then
    selected=false; reason="deleted-source"
  fi
  insertions=0; deletions=0
  if [ "$GIT_REPO" = true ] && [ -n "$BASE_REF" ] && [ -n "$HEAD_REF" ]; then
    read -r insertions deletions <<EOF
$(git -C "$PROJECT_DIR" diff --numstat "$BASE_REF" "$HEAD_REF" -- "$path" 2>/dev/null | awk -F '\t' '{a+=$1; d+=$2} END {print a+0, d+0}')
EOF
    fingerprint="$(git -C "$PROJECT_DIR" diff --no-ext-diff --binary "$BASE_REF" "$HEAD_REF" -- "$path" 2>/dev/null | sha256_text)"
  elif [ -f "$PROJECT_DIR/$path" ]; then
    fingerprint="$(sha256_file "$PROJECT_DIR/$path")"
  else
    fingerprint=""
  fi
  printf '%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\n' "$path" "$change" "$old_path" "$selected" "$reason" "$insertions" "$deletions" "$fingerprint" >> "$ITEMS_TSV"
}

if [ "$MODE" = incremental ]; then
  [ "$GIT_REPO" = true ] || { echo "INCREMENTAL_REQUIRES_GIT=true" >&2; exit 1; }
  TOTAL_COMMITS="$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo 0)"
  [ "$COMMIT_COUNT" -le "$TOTAL_COMMITS" ] || COMMIT_COUNT="$TOTAL_COMMITS"
  if [ "$COMMIT_COUNT" -eq 0 ]; then
    BASE_REF=""; HEAD_REF=""
  elif [ "$COMMIT_COUNT" -ge "$TOTAL_COMMITS" ]; then
    BASE_REF="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  else
    BASE_REF="$(git -C "$PROJECT_DIR" rev-parse "HEAD~$COMMIT_COUNT")"
  fi
  if [ -n "$BASE_REF" ] && [ -n "$HEAD_REF" ]; then
    # Git -z preserves spaces and rename pairs. Use the ASCII record separator
    # between fields so an empty old-path is not collapsed by Bash IFS.
    git -C "$PROJECT_DIR" diff --name-status -z --find-renames "$BASE_REF" "$HEAD_REF" |
      perl -0e '
        my @v = split(/\0/, do { local $/; <STDIN> }); pop @v if @v && $v[-1] eq "";
        while (@v) {
          my $s = shift @v; last unless defined $s;
          my $kind = substr($s,0,1);
          if ($kind eq "R" || $kind eq "C") { my $old=shift @v; my $new=shift @v; print "$kind\x1e$old\x1e$new\n"; }
          else { my $p=shift @v; print "$kind\x1e\x1e$p\n"; }
        }
      ' | while IFS="$(printf '\036')" read -r status old_path new_path; do
        case "$status" in A) change=added ;; M) change=modified ;; D) change=deleted ;; R) change=renamed ;; C) change=copied ;; *) change=modified ;; esac
        append_item "$new_path" "$change" "$old_path"
      done
  fi
else
  [ -n "$SOURCE_MANIFEST" ] || { echo "SOURCE_MANIFEST_REQUIRED_FOR_$MODE=true" >&2; exit 1; }
  while IFS= read -r absolute; do
    [ -n "$absolute" ] || continue
    rel="$(relative_path "$absolute")"
    append_item "$rel" "existing" ""
  done < "$SOURCE_MANIFEST"
fi

sort -t "$(printf '\036')" -k1,1 -u "$ITEMS_TSV" > "$ITEMS_TSV.sorted"
ITEM_COUNT="$(awk 'END{print NR+0}' "$ITEMS_TSV.sorted")"
SELECTED_COUNT="$(awk -F "$(printf '\036')" '$4 == "true" {n++} END{print n+0}' "$ITEMS_TSV.sorted")"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  printf '{\n  "schema_version": 1,\n'
  printf '  "selection_mode": "%s",\n' "$(json_escape "$MODE")"
  printf '  "project_dir": "%s",\n' "$(json_escape "$PROJECT_DIR")"
  printf '  "language_id": "%s",\n' "$(json_escape "$LANGUAGE_ID")"
  printf '  "git_repository": %s,\n' "$GIT_REPO"
  printf '  "base_ref": "%s",\n' "$(json_escape "$BASE_REF")"
  printf '  "head_ref": "%s",\n' "$(json_escape "$HEAD_REF")"
  printf '  "source_manifest": "%s",\n' "$(json_escape "$SOURCE_MANIFEST")"
  printf '  "item_count": %s,\n  "selected_item_count": %s,\n' "$ITEM_COUNT" "$SELECTED_COUNT"
  printf '  "created_at": "%s",\n  "items": [' "$CREATED_AT"
  first=1
  while IFS="$(printf '\036')" read -r path change old_path selected reason ins del fingerprint; do
    [ "$first" -eq 1 ] || printf ','
    printf '\n    {"path":"%s","change":"%s","old_path":"%s","selected":%s,"exclude_reason":"%s","insertions":%s,"deletions":%s,"fingerprint":"%s"}' \
      "$(json_escape "$path")" "$(json_escape "$change")" "$(json_escape "$old_path")" "$selected" "$(json_escape "$reason")" "$ins" "$del" "$(json_escape "$fingerprint")"
    first=0
  done < "$ITEMS_TSV.sorted"
  [ "$first" -eq 1 ] || printf '\n  '
  printf ']\n}\n'
} > "$OUTPUT_PATH.tmp"
mv "$OUTPUT_PATH.tmp" "$OUTPUT_PATH"

echo "REVIEW_INPUT_PATH=$OUTPUT_PATH"
echo "REVIEW_INPUT_ITEM_COUNT=$ITEM_COUNT"
echo "REVIEW_INPUT_SELECTED_COUNT=$SELECTED_COUNT"
