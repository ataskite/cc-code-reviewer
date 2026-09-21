#!/bin/bash
set -euo pipefail

# validate-security-report.sh 契约：
# - 完整合规报告（控制覆盖章节 + 对账 + 台账 + 问题块字段）→ exit 0 + 单行 stdout
# - 控制行缺失/重复、范围外引用、状态非法、计数对账不符、confirmed 无正式问题块、
#   映射漂移、缺标准映射/检测方式字段、适用控制标 not_applicable → exit 1 + ERROR_*
# - 报告无控制覆盖章节 → exit 1（结构无效）
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT_DIR/scripts/core/validate-security-report.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec-report.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL(sec-report): $*" >&2; exit 1; }

# 冻结 controls：两个适用控制 + 一个排除控制
cat > "$TMP/controls.json" <<'JSON'
{
  "schema_version": 1,
  "security_profile": ["node-api", "node-bff"],
  "controls": [
    { "id": "CCR-NODE-SSRF-001", "applicability": "applicable", "matched_signals": ["outbound-http-client"] },
    { "id": "CCR-NODE-CSRF-001", "applicability": "applicable", "matched_signals": ["session-usage"] }
  ],
  "excluded_controls": [
    { "id": "CCR-NODE-CMD-001", "reason": "冻结输入未命中所需信号: child-process" }
  ]
}
JSON

# 合规报告（SSRF confirmed 带 P0 块；CSRF checked_no_finding；CMD 以 not_applicable 行披露）
cat > "$TMP/report-ok.md" <<'MD'
# 审查报告

## 执行摘要

- P0 1 / P1 0

## 🔐 授权面覆盖（仅 Security 模式强制）

- 授权面台账：共 3 行；已绑定 2 / 未绑定 1 / 外部证据缺失 0 / 不适用 0，且 `N = A + B + C + D`。

## 🛡️ Security 控制覆盖（仅 Security 模式强制）

- 适用控制：2
- 已发现问题：1
- 已检查无发现：1
- 外部证据缺失：0
- 静态不可验证：0
- 不适用：1
- 对账：N = A + B + C + D

| 控制 ID | 标题 | 标准映射 | 检测方式 | 状态 | 证据或限制 |
|---|---|---|---|---|---|
| CCR-NODE-SSRF-001 | 用户可控数据进入服务端外发请求目标 | OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / v5.0.0-V4.2.5 / CWE-918 | taint | finding_confirmed | 见 P0-1 |
| CCR-NODE-CSRF-001 | Cookie 会话写接口缺少 CSRF 控制 | OWASP A01:2025 / API8:2023 / ASVS v5.0.0-V3.3.2 / CWE-352 | config | checked_no_finding | 写接口校验 Origin + SameSite=Lax |
| CCR-NODE-CMD-001 | 用户输入进入 child_process | OWASP A05:2025 / ASVS v5.0.0-V1.2.5 / CWE-78 | pattern | not_applicable | 冻结输入无 child_process 信号 |

## 🔴 P0 严重问题 (Critical Issues)

### P0-1 | [维度6-安全] webhook URL 无校验直连 fetch 导致 SSRF

- 文件：app.js:12
- **安全规则 ID**：CCR-NODE-SSRF-001
- **标准映射**：OWASP A01:2025 / API7:2023 / API10:2023 / ASVS v5.0.0-V1.3.6 / v5.0.0-V4.2.5 / CWE-918
- **检测方式**：taint
- **证据状态**：静态已证实
- **主体/资源/决策链**：不适用
- **未授权路径与防护**：不适用
- 问题与证据（略）

---

## ✅ 最佳实践亮点

无
MD

OUT="$(bash "$VALIDATOR" "$TMP/report-ok.md" "$TMP/controls.json")" || fail "validator rejected a compliant report: $OUT"
printf '%s\n' "$OUT" | grep -Eq '^SECURITY_REPORT_OK=.*/report-ok\.md CONTROLS=2 FINDINGS=1 PENDING=0$' \
  || fail "stdout contract violated: $OUT"

# 变体断言辅助：复制报告后做单点破坏
mutate() { # <name> <perl-pi-expression>
  cp "$TMP/report-ok.md" "$TMP/report-$1.md"
  perl -0pi -e "$2" "$TMP/report-$1.md"
}

expect_fail() { # <name> <stderr-tag>
  if bash "$VALIDATOR" "$TMP/report-$1.md" "$TMP/controls.json" >/dev/null 2>"$TMP/err-$1.txt"; then
    fail "variant $1 must fail"
  fi
  grep -q "$2" "$TMP/err-$1.txt" || fail "variant $1 stderr lacks $2: $(cat "$TMP/err-$1.txt")"
}

# 1. 台账行缺失
mutate no-row 's/\| CCR-NODE-CSRF-001[^\n]*\n//'
expect_fail no-row ERROR_SECURITY_REPORT_ROW_MISSING

# 2. 台账行重复
mutate dup-row 's/^(\| CCR-NODE-SSRF-001[^\n]*)$/$1\n$1/m'
expect_fail dup-row ERROR_SECURITY_REPORT_ROW_DUPLICATED

# 3. 范围外控制引用
mutate out-of-scope 's/CCR-NODE-CSRF-001 \| Cookie/CCR-NODE-DESER-001 | Cookie/'
expect_fail out-of-scope ERROR_SECURITY_REPORT_ID_OUT_OF_SCOPE

# 4. 状态非法
mutate bad-status 's/\| config \| checked_no_finding/| config | probably_ok/'
expect_fail bad-status ERROR_SECURITY_REPORT_STATUS_INVALID

# 5. 计数对账不符（已发现问题写 2）
mutate recon 's/^- 已发现问题：1$/- 已发现问题：2/m'
expect_fail recon ERROR_SECURITY_REPORT_RECON_MISMATCH

# 6. finding_confirmed 无对应问题块
mutate no-block 's/\*\*安全规则 ID\*\*：CCR-NODE-SSRF-001/**安全规则 ID**：/'
expect_fail no-block ERROR_SECURITY_REPORT_BLOCK_MISSING

# 7. 映射漂移（标准映射改成别的 ID）
mutate mapping 's/- \*\*标准映射\*\*：OWASP A01:2025 \/ API7:2023 \/ API10:2023 \/ ASVS v5\.0\.0-V1\.3\.6 \/ v5\.0\.0-V4\.2\.5 \/ CWE-918/- **标准映射**：OWASP A05:2025 \/ ASVS v5.0.0-V1.2.5 \/ CWE-78/'
expect_fail mapping ERROR_SECURITY_REPORT_MAPPING_DRIFT

# 8. 检测方式字段缺失
mutate no-detect 's/- \*\*检测方式\*\*：taint\n//'
expect_fail no-detect ERROR_SECURITY_REPORT_BLOCK_DETECT_MISSING

# 9. 适用控制标 not_applicable
mutate app-na 's/\| taint \| finding_confirmed/| taint | not_applicable/'
expect_fail app-na ERROR_SECURITY_REPORT_APPLICABLE_NA

# 10. 缺控制覆盖章节
mutate no-section 's/^## 🛡️ Security 控制覆盖/## Security 控制覆盖（另一写法）/m'
expect_fail no-section ERROR_SECURITY_REPORT_SECTION_MISSING

echo "PASS: security report validator contract"
