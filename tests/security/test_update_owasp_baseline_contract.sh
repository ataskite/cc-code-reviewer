#!/bin/bash
set -euo pipefail

# update-owasp-baseline.sh 维护契约（全部离线；--fetch 的真实下载不在本测试范围）：
# - 用法错误 exit 1（ERROR_OWASP_BASELINE_*）
# - --fetch 缺 --version/--revision → 拒绝；staging 已含该源 meta → 拒绝覆盖
#   （两者都必须在任何网络动作之前失败）
# - --emit-manifest 拒绝 license=UNVERIFIED；缺 NOTICE.md → ERROR_NOTICE_MISSING
# - --verify-only 对完整 staging 通过；对被篡改 staging fail closed
# - 不写仓库：所有产物只落在显式 staging 目录
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MAINT="$ROOT_DIR/scripts/maintenance/update-owasp-baseline.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/owasp-maint.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL(owasp-maint): $*" >&2; exit 1; }

# ---- 用法错误 ----
if bash "$MAINT" >/dev/null 2>&1; then fail "no-args must exit 1"; fi
if bash "$MAINT" --fetch owasp-asvs --version 5.0.0 --staging "$TMP/s1" >/dev/null 2>"$TMP/e1.txt"; then
  fail "--fetch without --revision must fail"
fi
grep -q 'ERROR_OWASP_BASELINE' "$TMP/e1.txt" || fail "fetch usage error tag missing"

# ---- 拒绝覆盖：staging 已含该源 meta（在任何网络动作前失败）----
mkdir -p "$TMP/s2/.source-meta"
printf '{"id":"owasp-asvs","version":"5.0.0","source_url":"u","source_revision":"r","license":"UNVERIFIED"}' \
  > "$TMP/s2/.source-meta/owasp-asvs.json"
if PATH=/usr/bin:/bin bash "$MAINT" --fetch owasp-asvs --version 5.0.0 --revision v5.0.0_release --staging "$TMP/s2" >/dev/null 2>"$TMP/e2.txt"; then
  fail "--fetch must refuse overwriting existing meta"
fi
grep -q '拒绝覆盖' "$TMP/e2.txt" || fail "refuse-overwrite message missing"

# ---- emit-manifest 拒绝 UNVERIFIED license ----
mkdir -p "$TMP/s3/.source-meta"
for m in owasp-asvs owasp-top10 owasp-api-top10; do
  printf '{"id":"%s","version":"1","source_url":"https://github.com/OWASP/x","source_revision":"r","license":"UNVERIFIED"}' "$m" \
    > "$TMP/s3/.source-meta/$m.json"
done
printf '{"id":"owasp-nodejs-cheat-sheet","version":"rolling","source_url":"https://github.com/OWASP/y","source_revision":"0123456789abcdef0123456789abcdef01234567","license":"CC-BY-SA-4.0"}' \
  > "$TMP/s3/.source-meta/owasp-nodejs-cheat-sheet.json"
if bash "$MAINT" --emit-manifest --staging "$TMP/s3" >/dev/null 2>"$TMP/e3.txt"; then
  fail "emit-manifest must refuse UNVERIFIED license"
fi
grep -q '许可证未核验' "$TMP/e3.txt" || fail "UNVERIFIED refusal message missing"

# ---- emit-manifest 缺 NOTICE → ERROR_NOTICE_MISSING ----
perl -pi -e 's/UNVERIFIED/CC-BY-SA-4.0/' "$TMP/s3/.source-meta/"*.json
mkdir -p "$TMP/s3/asvs/1" "$TMP/s3/top10/1" "$TMP/s3/api-top10/1" "$TMP/s3/nodejs-cheat-sheet/0123456789ab"
printf 'content\n' > "$TMP/s3/asvs/1/a.json"
printf 'content\n' > "$TMP/s3/top10/1/A01.md"
printf 'content\n' > "$TMP/s3/api-top10/1/API1.md"
printf 'content\n' > "$TMP/s3/nodejs-cheat-sheet/0123456789ab/Nodejs_Security_Cheat_Sheet.md"
for n in top10/1 api-top10/1 nodejs-cheat-sheet/0123456789ab; do printf '# NOTICE placeholder\n- Source URL: https://github.com/OWASP/x\n- Revision: r\n' > "$TMP/s3/$n/NOTICE.md"; done
if bash "$MAINT" --emit-manifest --staging "$TMP/s3" >/dev/null 2>"$TMP/e4.txt"; then
  fail "emit-manifest must refuse missing NOTICE"
fi
grep -q 'ERROR_NOTICE_MISSING' "$TMP/e4.txt" || fail "NOTICE_MISSING tag missing"

# ---- verify-only：完整 staging 通过（用仓库内快照副本构造）----
S5="$TMP/s5"
cp -R "$ROOT_DIR/references/security/upstream/." "$S5/"
bash "$MAINT" --verify-only "$S5" >/dev/null 2>&1 || fail "verify-only must pass on intact snapshot copy"

# ---- verify-only：篡改 staging → fail closed ----
S6="$TMP/s6"
cp -R "$ROOT_DIR/references/security/upstream/." "$S6/"
printf '\n' >> "$S6/top10/2025/A01.md"
if bash "$MAINT" --verify-only "$S6" >/dev/null 2>"$TMP/e6.txt"; then
  fail "verify-only must fail on tampered staging"
fi

# ---- verify-only：不存在目录 → 用法错误 ----
if bash "$MAINT" --verify-only "$TMP/no-such" >/dev/null 2>&1; then fail "verify-only must reject missing dir"; fi

# ---- 不写仓库：维护流程不在 references/ 下产生任何新文件 ----
[ -z "$(git -C "$ROOT_DIR" status --porcelain -- references/security/upstream 2>/dev/null)" ] \
  || fail "maintenance flow must not touch repo upstream tree"

echo "PASS: update-owasp-baseline maintenance contract"
