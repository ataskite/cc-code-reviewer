#!/bin/bash
set -euo pipefail

# Freeze the formal input of one review run.  This is deliberately independent
# from an agent prompt: later planners, agents and reports consume the same
# file list instead of rediscovering it themselves.
#
# Secret-path protection (absorbed from OpenCodeReview v1.12.3): credential-
# looking paths (.env family, .ssh/**, id_* private keys, .netrc/_netrc/
# .npmrc/.pypirc/.dockercfg) are force-excluded with exclude_reason=secret-path
# at the highest precedence — manifest membership never re-includes them and
# rename old_path is checked too.
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# sha256_file / sha256_text（三级回退链）统一来自共享库 scripts/core/lib/common.sh。
. "$SCRIPT_DIR/lib/common.sh"

case "$MODE" in incremental|full|scoped) ;; *) echo "REVIEW_INPUT_MODE_INVALID=$MODE" >&2; exit 1 ;; esac
case "$COMMIT_COUNT" in ''|*[!0-9]*) echo "COMMIT_COUNT_INVALID=$COMMIT_COUNT" >&2; exit 1 ;; esac
[ -z "$SOURCE_MANIFEST" ] || [ -r "$SOURCE_MANIFEST" ] || { echo "SOURCE_MANIFEST_NOT_READABLE=$SOURCE_MANIFEST" >&2; exit 1; }

json_escape() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'; }
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
LOOKUP_TSV="$(mktemp "${TMPDIR:-/tmp}/cc-review-lookup.XXXXXX")"
SELECTED_PATHS_NUL="$(mktemp "${TMPDIR:-/tmp}/cc-review-selected.XXXXXX")"
# LOOKUP_TSV 是一次性构建的查找表（M=manifest 键集 / N=numstat / F=diff 指纹），
# 避免在每文件循环里线性扫描 manifest 或重复计算整个 BASE..HEAD diff（O(N²) 热点）。
: > "$LOOKUP_TSV"
trap 'rm -f "$ITEMS_TSV" "$ITEMS_TSV.sorted" "$ITEMS_TSV.enriched" "$LOOKUP_TSV" "$SELECTED_PATHS_NUL"' EXIT

BASE_REF=""; HEAD_REF=""; GIT_REPO=false
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_REPO=true
  HEAD_REF="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)"
fi

# 增量模式下 numstat 与 raw blob identity 各只计算一次全量 diff，再拆成
# per-path 映射。两者都使用 -z/NUL 协议，路径不经过 Git 引号或八进制转义；
# 指纹由 old/new blob、mode、status 与 rename 路径共同生成，无逐文件 fallback。
build_git_lookup() {
  [ -n "$BASE_REF" ] && [ -n "$HEAD_REF" ] || return 0
  git -C "$PROJECT_DIR" diff --numstat -z --find-renames "$BASE_REF" "$HEAD_REF" 2>/dev/null |
    perl -0e '
      my @v = split(/\0/, do { local $/; <STDIN> });
      pop @v if @v && $v[-1] eq "";
      while (@v) {
        my $head = shift @v;
        my ($ins, $del, $path) = split(/\t/, $head, 3);
        die "INVALID_NUMSTAT_RECORD\n" unless defined $path;
        if ($path eq "") {
          shift @v;             # rename/copy old path
          $path = shift @v;     # rename/copy new path
        }
        $ins = 0 unless defined($ins) && $ins =~ /^\d+$/;
        $del = 0 unless defined($del) && $del =~ /^\d+$/;
        print "N\x1e$path\x1e$ins\x1e$del\n";
      }
    ' >> "$LOOKUP_TSV"
  # --abbrev=64 固定 blob sha 全长：SHA-1 仓库自动截到 40 位、SHA-256 仓库保留
  # 64 位；默认缩写长度会随仓库对象数自动伸缩，同一区间在不同 clone 上会得出
  # 不同指纹。
  git -C "$PROJECT_DIR" diff --raw -z --no-ext-diff --abbrev=64 --find-renames "$BASE_REF" "$HEAD_REF" 2>/dev/null |
    perl -0 -MDigest::SHA -e '
      my @v = split(/\0/, do { local $/; <STDIN> });
      pop @v if @v && $v[-1] eq "";
      while (@v) {
        my $meta = shift @v;
        my ($status) = $meta =~ / ([A-Z][0-9]*)\z/ or die "INVALID_RAW_RECORD=$meta\n";
        my $kind = substr($status, 0, 1);
        my ($old, $new) = ("", "");
        if ($kind eq "R" || $kind eq "C") {
          $old = shift @v;
          $new = shift @v;
        } else {
          $new = shift @v;
        }
        my $d = Digest::SHA->new(256);
        $d->add(join("\0", $meta, $old, $new));
        print "F\x1e$new\x1e", $d->hexdigest, "\n";
      }
    ' >> "$LOOKUP_TSV"
}

append_item() {
  local path="$1" change="$2" old_path="${3:-}" fingerprint
  [ -n "$path" ] || return 0
  if [ -n "$BASE_REF" ] && [ -n "$HEAD_REF" ]; then
    fingerprint=""  # 由 LOOKUP_TSV 的单次 raw diff 映射填充
  elif [ -f "$PROJECT_DIR/$path" ]; then
    fingerprint="$(sha256_file "$PROJECT_DIR/$path")"
  else
    fingerprint=""
  fi
  printf '%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\n' "$path" "$change" "$old_path" "" "" "" "" "$fingerprint" >> "$ITEMS_TSV"
}

if [ "$MODE" = incremental ]; then
  [ "$GIT_REPO" = true ] || { echo "INCREMENTAL_REQUIRES_GIT=true" >&2; exit 1; }
  if [ -n "$SOURCE_MANIFEST" ]; then
    while IFS= read -r entry; do
      entry="${entry%$'\r'}"
      [ -n "${entry//[[:space:]]/}" ] || continue
      printf 'M\036%s\n' "$(relative_path "$entry")" >> "$LOOKUP_TSV"
    done < "$SOURCE_MANIFEST"
  fi
  TOTAL_COMMITS="$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo 0)"
  [ "$COMMIT_COUNT" -le "$TOTAL_COMMITS" ] || COMMIT_COUNT="$TOTAL_COMMITS"
  if [ "$COMMIT_COUNT" -eq 0 ]; then
    BASE_REF=""; HEAD_REF=""
  elif [ "$COMMIT_COUNT" -ge "$TOTAL_COMMITS" ]; then
    BASE_REF="$(git_empty_tree_oid "$PROJECT_DIR")"
  else
    BASE_REF="$(git -C "$PROJECT_DIR" rev-parse "HEAD~$COMMIT_COUNT")"
  fi
  build_git_lookup
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
    # Keep the manifest path byte-for-byte intact apart from CRLF cleanup.
    absolute="${absolute%$'\r'}"
    [ -n "${absolute//[[:space:]]/}" ] || continue
    rel="$(relative_path "$absolute")"
    printf 'M\036%s\n' "$rel" >> "$LOOKUP_TSV"
    append_item "$rel" "existing" ""
  done < "$SOURCE_MANIFEST"
fi

# 一次性回填：selected/exclude_reason（manifest 哈希查找）+ numstat + raw 指纹。
# secret-path 保护（吸收自 OpenCodeReview v1.12.3 secret exclude）：与上游同口径的
# 纯路径密钥文件判定（大小写不敏感、不看内容）——`.env` 与 `.env.*`（example/
# sample/template 仅在未命中其他敏感路径规则时豁免）、`.ssh/**` 下任意文件、id_rsa/id_dsa/id_ecdsa/
# id_ed25519 私钥、.netrc/_netrc/.npmrc/.pypirc/.dockercfg。优先级最高：即使
# 命中 source manifest 也强制 selected=false（exclude_reason=secret-path），
# rename 的 old_path 同样参与判定（内容来自密钥路径的改名不因换名进入范围），
# 且不被任何用户清单选择覆盖。
awk -F "$(printf '\036')" -v OFS="$(printf '\036')" -v has_manifest="$([ -n "$SOURCE_MANIFEST" ] && echo 1 || echo 0)" \
  '
  function is_secret_path(p,  q, b) {
    q = tolower(p)
    b = q; sub(/.*\//, "", b)
    # 无条件敏感路径优先于 .env 模板豁免：例如 .ssh/.env.example 仍必须排除。
    if (q ~ /(^|\/)\.ssh\//) return 1
    if (b == "id_rsa" || b == "id_dsa" || b == "id_ecdsa" || b == "id_ed25519") return 1
    if (b == ".netrc" || b == "_netrc" || b == ".npmrc" || b == ".pypirc" || b == ".dockercfg") return 1
    if (b == ".env.example" || b == ".env.sample" || b == ".env.template") return 0
    if (b == ".env" || index(b, ".env.") == 1) return 1
    return 0
  }
  NR == FNR {
    if ($1 == "M") m[$2] = 1
    else if ($1 == "N") { ni[$2] = $3 + 0; nd[$2] = $4 + 0 }
    else if ($1 == "F") fp[$2] = $3
    next
  }
  {
    selected = "true"; reason = ""
    if (has_manifest && !($1 in m)) { selected = "false"; reason = "outside-source-manifest" }
    if ($2 == "deleted") { selected = "false"; reason = "deleted-source" }
    if (is_secret_path($1) || ($3 != "" && is_secret_path($3))) { selected = "false"; reason = "secret-path" }
    ins = ($1 in ni) ? ni[$1] : 0
    del = ($1 in nd) ? nd[$1] : 0
    f = ($1 in fp) ? fp[$1] : $8
    print $1, $2, $3, selected, reason, ins, del, f
  }' "$LOOKUP_TSV" "$ITEMS_TSV" > "$ITEMS_TSV.enriched"
mv "$ITEMS_TSV.enriched" "$ITEMS_TSV"

sort -t "$(printf '\036')" -k1,1 -u "$ITEMS_TSV" > "$ITEMS_TSV.sorted"
ITEM_COUNT="$(awk 'END{print NR+0}' "$ITEMS_TSV.sorted")"
SELECTED_COUNT="$(awk -F "$(printf '\036')" '$4 == "true" {n++} END{print n+0}' "$ITEMS_TSV.sorted")"
# 先生成 NUL 路径流，再单进程批量统计；保持 wc -l 语义（末行无换行符不计入），
# 输出为 NUL 分隔记录，含换行符的路径也能逐条对位求和。
CCR_PROJECT_DIR="$PROJECT_DIR" perl -F'\x1e' -ane '
  next unless defined $F[3] && $F[3] eq "true";
  my $f = $F[0];
  $f = "$ENV{CCR_PROJECT_DIR}/$f" unless $f =~ m{^/};
  print "$f\0" if -f $f;
' "$ITEMS_TSV.sorted" > "$SELECTED_PATHS_NUL"
SELECTED_LINE_COUNT="$(batch_wc_lines_nul < "$SELECTED_PATHS_NUL" |
  perl -0ne '
    /\x1e(\d+)/ or die "BATCH_WC_RECORD_MALFORMED: $_\n";
    $total += $1;
    END { print $total + 0, "\n" }
  ')"
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
  printf '  "item_count": %s,\n  "selected_item_count": %s,\n  "selected_line_count": %s,\n' "$ITEM_COUNT" "$SELECTED_COUNT" "$SELECTED_LINE_COUNT"
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
echo "REVIEW_INPUT_SELECTED_LINE_COUNT=$SELECTED_LINE_COUNT"
