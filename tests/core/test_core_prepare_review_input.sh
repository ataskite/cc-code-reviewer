#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/core-prepare-review-input.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
SCRIPT="$ROOT_DIR/scripts/core/prepare-review-input.sh"

new_repo() {
  REPO="$TMP_DIR/$1"; mkdir -p "$REPO/src"; cd "$REPO"
  git init -q; git config user.email test@example.com; git config user.name test
}

# 1. 增量：空格与中文文件名、rename、delete、added 的 numstat 与 diff 指纹齐全。
new_repo spaces
printf 'a\n' > "src/with space.java"; printf 'b\n' > "src/中文 类.java"; printf 'c\n' > src/gone.java; printf 'd\n' > src/keep.java
git add .; git commit -qm init
printf 'a2\n' > "src/with space.java"
printf 'b2\n' > "src/中文 类.java"
git mv src/keep.java src/kept.java
rm src/gone.java
printf 'new\n' > src/fresh.java
git add .; git commit -qm change

# 用 git 包装器守卫批量实现：无论特殊路径多少，增量输入只允许固定 3 次 diff
#（numstat + raw fingerprint + name-status），不得逐文件 fallback。
REAL_GIT="$(command -v git)"
GIT_WRAPPER_DIR="$TMP_DIR/git-wrapper"; mkdir -p "$GIT_WRAPPER_DIR"
cat > "$GIT_WRAPPER_DIR/git" <<'SH'
#!/bin/bash
# 统计一切 diff 子命令调用（兼容 -C / -c 等前置参数）。
for ((i = 1; i <= $#; i++)); do
  if [ "${!i}" = "diff" ]; then printf '%s\n' "$*" >> "$GIT_DIFF_COUNTER"; break; fi
done
exec "$REAL_GIT" "$@"
SH
chmod +x "$GIT_WRAPPER_DIR/git"
: > "$TMP_DIR/git-diff.calls"
INPUT_OUT="$(PATH="$GIT_WRAPPER_DIR:$PATH" REAL_GIT="$REAL_GIT" GIT_DIFF_COUNTER="$TMP_DIR/git-diff.calls" \
  bash "$SCRIPT" "$REPO" java incremental 1 "" "$TMP_DIR/inc.json")"
grep -q '^REVIEW_INPUT_ITEM_COUNT=5$' <<< "$INPUT_OUT"
grep -q '^REVIEW_INPUT_SELECTED_COUNT=4$' <<< "$INPUT_OUT"
grep -q '^REVIEW_INPUT_SELECTED_LINE_COUNT=4$' <<< "$INPUT_OUT"
[ "$(wc -l < "$TMP_DIR/git-diff.calls" | tr -d ' ')" -eq 3 ]
jq -e '.items | (map(select(.change == "renamed"))[0] | .path == "src/kept.java" and .old_path == "src/keep.java" and .selected == true and (.fingerprint | length == 64)) and (map(select(.change == "deleted"))[0] | .selected == false and .exclude_reason == "deleted-source" and .deletions == 1) and (map(select(.path == "src/with space.java"))[0] | .insertions == 1 and .deletions == 1 and (.fingerprint | length == 64)) and (map(select(.path == "src/中文 类.java"))[0] | .insertions == 1 and .deletions == 1 and (.fingerprint | length == 64)) and (map(select(.path == "src/fresh.java"))[0] | .change == "added" and .insertions == 1)' "$TMP_DIR/inc.json" >/dev/null

# 2. CRLF manifest 在 full 模式逐字节命中（\r 不得破坏匹配）。
printf '%s\r\n' "$REPO/src/kept.java" "$REPO/src/fresh.java" > "$TMP_DIR/crlf.manifest"
bash "$SCRIPT" "$REPO" java full 0 "$TMP_DIR/crlf.manifest" "$TMP_DIR/crlf.json" >/dev/null
jq -e '.selected_item_count == 2 and (.items | all(.selected == true))' "$TMP_DIR/crlf.json" >/dev/null

# 2b. CRLF manifest 用作增量过滤器时，未列入的变更文件标记 outside-source-manifest。
printf '%s\r\n' "$REPO/src/fresh.java" > "$TMP_DIR/crlf-one.manifest"
bash "$SCRIPT" "$REPO" java incremental 1 "$TMP_DIR/crlf-one.manifest" "$TMP_DIR/crlf-one.json" >/dev/null
jq -e '.items | (map(select(.selected)) | length == 1) and (map(select(.exclude_reason == "outside-source-manifest")) | length == 3)' "$TMP_DIR/crlf-one.json" >/dev/null

# 3. COMMIT_COUNT=0（无 diff 区间）退化为内容 sha256 指纹。
bash "$SCRIPT" "$REPO" java incremental 0 "" "$TMP_DIR/zero.json" >/dev/null
jq -e '(.base_ref == "" and .head_ref == "") and (.items | length == 0)' "$TMP_DIR/zero.json" >/dev/null

# 4. 非 git 项目 full 模式仍按文件 sha256 冻结指纹。
NOGIT="$TMP_DIR/nogit"; mkdir -p "$NOGIT/src"; printf 'x\ny\n' > "$NOGIT/src/A.java"
printf '%s\n' "$NOGIT/src/A.java" > "$TMP_DIR/nogit.manifest"
bash "$SCRIPT" "$NOGIT" java full 0 "$TMP_DIR/nogit.manifest" "$TMP_DIR/nogit.json" >/dev/null
jq -e '(.git_repository == false and .selected_line_count == 2) and (.items[0].fingerprint | length == 64)' "$TMP_DIR/nogit.json" >/dev/null

# 5. LOC 必须保持 wc -l 口径：末行无换行符不计入行数。
printf 'no trailing newline' > "$NOGIT/src/NoNewline.java"
printf '%s\n' "$NOGIT/src/NoNewline.java" > "$TMP_DIR/no-newline.manifest"
bash "$SCRIPT" "$NOGIT" java full 0 "$TMP_DIR/no-newline.manifest" "$TMP_DIR/no-newline.json" >/dev/null
jq -e '.selected_item_count == 1 and .selected_line_count == 0' "$TMP_DIR/no-newline.json" >/dev/null

# 5b. 含换行符的文件名由 planner 的 find -print0 管线承载（见
# test_core_common_batch_wc.sh 的 NUL 记录契约）；本脚本的 manifest 与内部
# TSV 均为按行协议，换行路径从未可表达，无端到端用例。

# 5c. SHA-256 仓库：--abbrev=64 输出全长对象 ID；审查区间覆盖根提交时
# 必须使用当前对象格式的空 tree OID，指纹照常生成且两次运行一致。
SHA256_REPO="$TMP_DIR/sha256"
if git init -q --object-format=sha256 "$SHA256_REPO" 2>/dev/null; then
  cd "$SHA256_REPO"
  git config user.email test@example.com; git config user.name test
  mkdir -p src; printf 'one\n' > src/A.java; git add .; git commit -qm init
  printf 'one\ntwo\n' > src/A.java; git add .; git commit -qm change
  RAW_LEN="$(git diff --raw --abbrev=64 HEAD~1 HEAD | awk 'NR==1{print length($3); exit}')"
  [ "$RAW_LEN" -eq 64 ] || { echo "SHA256_ABBREV_NOT_FULL: $RAW_LEN" >&2; exit 1; }
  SHA1_LEN="$(cd "$REPO" && git diff --raw --abbrev=64 HEAD~1 HEAD | awk 'NR==1{print length($3); exit}')"
  [ "$SHA1_LEN" -eq 40 ] || { echo "SHA1_ABBREV_NOT_CAPPED: $SHA1_LEN" >&2; exit 1; }
  bash "$SCRIPT" "$SHA256_REPO" java incremental 2 "" "$TMP_DIR/sha256-a.json" >/dev/null
  bash "$SCRIPT" "$SHA256_REPO" java incremental 2 "" "$TMP_DIR/sha256-b.json" >/dev/null
  jq -e '.items | length == 1 and .[0].change == "added" and .[0].insertions == 2 and (.[0].fingerprint | length == 64)' "$TMP_DIR/sha256-a.json" >/dev/null
  diff <(jq '.items[0].fingerprint' "$TMP_DIR/sha256-a.json") \
       <(jq '.items[0].fingerprint' "$TMP_DIR/sha256-b.json") >/dev/null
  cd "$REPO"
fi

# 6. 性能回归守卫：800 文件 × 800 行 manifest 的 full 模式必须在 60 秒内完成
#    （修复前为 O(N²) manifest 扫描 + 逐文件 wc，远超该预算）。
PERF="$TMP_DIR/perf"; mkdir -p "$PERF/src"
for i in $(seq 1 800); do
  {
    printf 'class C%d {\n' "$i"
    for j in $(seq 1 798); do printf '  int v%d_%d = %d;\n' "$i" "$j" "$j"; done
    printf '}\n'
  } > "$PERF/src/C$i.java"
done
find "$PERF/src" -name '*.java' | sort > "$TMP_DIR/perf.manifest"
START="$(date +%s)"
bash "$SCRIPT" "$PERF" java full 0 "$TMP_DIR/perf.manifest" "$TMP_DIR/perf.json" >/dev/null
ELAPSED=$(( $(date +%s) - START ))
[ "$ELAPSED" -le 60 ] || { echo "PERF_REGRESSION: full mode took ${ELAPSED}s (budget 60s)" >&2; exit 1; }
jq -e '.selected_item_count == 800 and .selected_line_count == 640000' "$TMP_DIR/perf.json" >/dev/null

# 7. secret-path 强制排除（吸收自 OpenCodeReview v1.12.3）：
#    `.env`/`.env.*`（example/sample/template 仅在未命中其他规则时豁免）、`.ssh/**`、id_* 私钥、
#    .netrc/_netrc/.npmrc/.pypirc/.dockercfg 一律 selected=false +
#    exclude_reason=secret-path；rename 的 old_path 为密钥路径同样排除；
#    `.ssh/.env.example|sample|template` 仍须排除；full 模式下即使 manifest
#    明确列出也强制排除（优先级高于 manifest 命中）。
new_repo secrets
mkdir -p .ssh nested/.SSH config deploy src
printf 'K=1\n' > .env.production
printf 'old-ssh-template\n' > .ssh/.env.template
printf 'ok\n' > src/App.java
git add .; git commit -qm init
printf 'K=2\n' > .env                          # 新增密钥文件
printf 'K=${K2}\n' > .env.example              # 模板正常新增
printf 'K=${K3}\n' > .env.sample               # 模板正常新增
printf 'K=${K4}\n' > .env.template             # 模板正常新增
printf 'LOCAL=1\n' > config/.Env.Local        # 大小写不敏感（内容与 .env.production 错开，避免 rename 配对干扰）
printf 'x\n' > .ssh/config
printf 'ssh-example\n' > .ssh/.env.example      # 模板豁免不能绕过 .ssh/**
printf 'ssh-sample\n' > .ssh/.env.sample
mkdir -p .ssh/templates
printf 'ssh-template\n' > .ssh/templates/.env.template
printf 'ssh-case\n' > nested/.SSH/.ENV.EXAMPLE  # 组合规则同样大小写不敏感
printf 'x\n' > deploy/.npmrc
printf 'x\n' > src/id_ed25519
printf 'ok2\n' > src/App.java
git mv .env.production src/main-env.txt        # 密钥路径改名逃逸：old_path 判定
git mv .ssh/.env.template src/ssh-template.txt # 模板路径也不得通过 rename 逃逸
git add .; git commit -qm touch-secrets
bash "$SCRIPT" "$REPO" java incremental 1 "" "$TMP_DIR/sec.json" >/dev/null
jq -e '.items |
  (map(select(.path == ".env"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == "src/main-env.txt"))[0] | .selected == false and .exclude_reason == "secret-path" and .old_path == ".env.production") and
  (map(select(.path == "config/.Env.Local"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == ".ssh/config"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == ".ssh/.env.example"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == ".ssh/.env.sample"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == ".ssh/templates/.env.template"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == "src/ssh-template.txt"))[0] | .selected == false and .exclude_reason == "secret-path" and .old_path == ".ssh/.env.template") and
  (map(select(.path == "nested/.SSH/.ENV.EXAMPLE"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == "deploy/.npmrc"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == "src/id_ed25519"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == ".env.example"))[0] | .selected == true) and
  (map(select(.path == ".env.sample"))[0] | .selected == true) and
  (map(select(.path == ".env.template"))[0] | .selected == true) and
  (map(select(.path == "src/App.java"))[0] | .selected == true)
' "$TMP_DIR/sec.json" >/dev/null || { echo "FAIL: secret-path incremental exclusion" >&2; exit 1; }

# full 模式：manifest 列入 .env 或 .ssh 内模板也必须被 secret-path 覆盖；
# 仓库根模板仍可进入范围。
new_repo secrets-full
mkdir -p src .ssh
printf 'ok\n' > src/App.java
printf 'K=1\n' > .env
printf 'template\n' > .env.template
printf 'ssh-template\n' > .ssh/.env.template
printf '%s\n' "$REPO/src/App.java" "$REPO/.env" "$REPO/.env.template" "$REPO/.ssh/.env.template" > "$TMP_DIR/sec.manifest"
bash "$SCRIPT" "$REPO" java full 0 "$TMP_DIR/sec.manifest" "$TMP_DIR/sec-full.json" >/dev/null
jq -e '.items |
  (map(select(.path == ".env"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == ".ssh/.env.template"))[0] | .selected == false and .exclude_reason == "secret-path") and
  (map(select(.path == ".env.template"))[0] | .selected == true) and
  (map(select(.path == "src/App.java"))[0] | .selected == true)
' "$TMP_DIR/sec-full.json" >/dev/null || { echo "FAIL: secret-path must override manifest membership in full mode" >&2; exit 1; }

echo "PASS: core prepare-review-input (O(N) lookup, NUL-safe git metadata, batched LOC, perf guard)"
