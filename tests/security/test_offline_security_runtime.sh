#!/bin/bash
set -euo pipefail

# 断网运行测试（offline security runtime）：
# - 在「网络替身全部立即失败 + 不可达代理」的环境里运行 Security 运行链路——
#   upstream 校验、catalog 校验、适用控制解析、攻击面生成、报告校验、SARIF 导出
#   ——全部成功且网络替身调用次数为 0。
# - 静态扫描 active runtime 脚本（scripts/core + scripts/languages），禁止出现
#   运行时 curl/wget http(s)/open URL 形态；references/security/upstream 的
#   NOTICE/来源文件与 scripts/maintenance/**（显式维护态）不在禁止范围。
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec-offline.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL(offline): $*" >&2; exit 1; }

# ---- 网络替身：记录任何调用并失败 ----
STUB="$TMP/netbin"; mkdir -p "$STUB"
NETLOG="$TMP/netcalls.log"; : > "$NETLOG"
for tool in curl wget npx; do
  cat > "$STUB/$tool" <<EOF
#!/bin/bash
echo "$tool \$*" >> "$NETLOG"
exit 1
EOF
  chmod +x "$STUB/$tool"
done
cat > "$STUB/git" <<'EOF'
#!/bin/bash
case "$1" in
  fetch|pull|clone|push|ls-remote|remote-update)
    echo "git-network $*" >> "$NETLOG"
    exit 1
    ;;
esac
exec /usr/bin/git "$@"
EOF
chmod +x "$STUB/git"

run_offline() { # 在断网环境中执行命令
  PATH="$STUB:/usr/bin:/bin" \
  HTTP_PROXY="http://127.0.0.1:1" HTTPS_PROXY="http://127.0.0.1:1" \
  ALL_PROXY="http://127.0.0.1:1" NO_PROXY="" \
  bash -c "$1"
}

# ---- fixture：Vue + express BFF（供 resolver/surface/report/SARIF 链路）----
D="$TMP/bff"; mkdir -p "$D/src/views"
cat > "$D/package.json" <<'JSON'
{"name":"offline-bff","main":"app.js","dependencies":{"vue":"^2.6.10","express":"^4.16.0","axios":"^0.27.0"}}
JSON
echo '<template><div/></template>' > "$D/src/views/Home.vue"
cat > "$D/app.js" <<'JS'
const express = require('express');
const axios = require('axios');
const app = express();
app.post('/relay', function (req, res) {
  axios.post('http://upstream-svc.internal/api', req.body, { headers: req.headers });
});
app.listen(8080);
JS

perl -MJSON::PP -e '
  my ($out, @files) = @ARGV;
  my @items = map { +{ path => $_, change => "added", old_path => "", selected => "true", exclude_reason => "", insertions => 1, deletions => 0, fingerprint => "" } } @files;
  open my $fh, ">", $out or die; print {$fh} JSON::PP->new->canonical->utf8->encode({ schema_version => 1, language_id => "frontend", items => \@items }), "\n"; close $fh;
' "$TMP/in.json" "$D/package.json" "$D/src/views/Home.vue" "$D/app.js"

# ---- 断网链路：六步全部成功 ----
run_offline "bash '$ROOT_DIR/tests/security/test_security_upstream.sh'" || fail "upstream check needs network"
run_offline "bash '$ROOT_DIR/scripts/core/validate-security-control-catalog.sh'" >/dev/null || fail "catalog validation needs network"
run_offline "bash '$ROOT_DIR/scripts/core/resolve-security-controls.sh' '$D' auto '$TMP/in.json' '$TMP/controls.json'" >/dev/null || fail "resolver needs network"
run_offline "bash '$ROOT_DIR/scripts/languages/frontend/prepare-security-surface.sh' '$D' '$TMP/in.json' '$TMP/controls.json' '$TMP/surface.json'" >/dev/null || fail "surface needs network"

cat > "$TMP/report.md" <<'MD'
# 报告

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：1
- 已发现问题：1
- 已检查无发现：0
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：0
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-BFFHEADER-001 | t | m | taint | finding_confirmed | 见 P0-1 |

### P0-1 | [维度6-安全] 头透传

- 文件：app.js:5
- **安全规则 ID**：CCR-NODE-BFFHEADER-001
- **标准映射**：OWASP A07:2025 / API2:2023 / ASVS v5.0.0-V4.1.3 / CWE-290
- **检测方式**：taint
- **证据状态**：静态已证实
- 证据：示例
- 建议：白名单逐头构造
MD
# controls fixture（单控制，与报告对账一致）
printf '{"controls":[{"id":"CCR-NODE-BFFHEADER-001"}],"excluded_controls":[]}' > "$TMP/controls-one.json"
run_offline "bash '$ROOT_DIR/scripts/core/validate-security-report.sh' '$TMP/report.md' '$TMP/controls-one.json'" >/dev/null || fail "report validation needs network"
run_offline "bash '$ROOT_DIR/scripts/core/export-sarif.sh' '$TMP/report.md' '$TMP/report.sarif'" >/dev/null || fail "sarif export needs network"

# ---- 网络替身调用必须为 0 ----
NETCOUNT="$(grep -c . "$NETLOG" || true)"
[ "$NETCOUNT" = "0" ] || fail "offline chain made network attempts: $(cat "$NETLOG")"

# ---- 静态扫描：active runtime 脚本禁止运行时网络形态 ----
BAD="$(grep -rnE 'curl[[:space:]]+https?://|wget[[:space:]]+https?://|open[[:space:]]+https?://' \
  "$ROOT_DIR/scripts/core" "$ROOT_DIR/scripts/languages" 2>/dev/null || true)"
[ -z "$BAD" ] || fail "runtime scripts contain network-fetch patterns: $BAD"

# 维护脚本（scripts/maintenance/**）是唯一显式联网面，允许 curl，但必须只在维护态出现
grep -q 'curl' "$ROOT_DIR/scripts/maintenance/update-owasp-baseline.sh" || fail "maintenance script expected to own the only curl usage"

echo "PASS: offline security runtime (zero network attempts)"
