#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer.md"
FRONTEND_AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
FEISHU_FILE="$ROOT_DIR/references/feishu-integration.md"
REPORT_FORMAT_FILE="$ROOT_DIR/references/report-format.md"
SKILL_FILE="$ROOT_DIR/skills/cc-code-reviewer/SKILL.md"
AGENTS_FILE="$ROOT_DIR/AGENTS.md"
CLAUDE_FILE="$ROOT_DIR/CLAUDE.md"
EXAMPLES_FILE="$ROOT_DIR/references/examples.md"
FIX_WORKFLOW_FILE="$ROOT_DIR/references/fix-workflow.md"
FIX_SKILL_FILE="$ROOT_DIR/skills/cc-code-fixer/SKILL.md"
FIX_REPORT_FILE="$ROOT_DIR/references/fix-report-format.md"
FIX_FEISHU_FILE="$ROOT_DIR/references/fix-feishu-integration.md"
FIX_EXAMPLES_FILE="$ROOT_DIR/references/fix-examples.md"
IGNORE_SKILL_FILE="$ROOT_DIR/skills/cc-code-ignore/SKILL.md"
IGNORE_WORKFLOW_FILE="$ROOT_DIR/references/ignore-workflow.md"
ARCHITECTURE_PNG="$ROOT_DIR/docs/assets/architecture-overview.png"
ARCHITECTURE_SVG="$ROOT_DIR/docs/assets/architecture-overview.svg"
PLUGIN_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
MARKETPLACE_FILE="$ROOT_DIR/.claude-plugin/marketplace.json"
PLUGIN_FILE="$ROOT_DIR/.claude-plugin/plugin.json"
DD="--"
MODE_BYPASS_TOKEN="FAST_""MODE"
PARAMS_BYPASS_TOKEN="FAST_""PARAMS"
QUICK_START_CN="快速""启动"
BYPASS_PHRASES_CN="无需人工""交互|跳过所有""交互|参数校验""失败|禁止降级为交互式""模式"
SCAN_BYPASS_PATTERN="${MODE_BYPASS_TOKEN}|${PARAMS_BYPASS_TOKEN}|${QUICK_START_CN}|${BYPASS_PHRASES_CN}|${DD}type|${DD}scope|${DD}upload|${DD}branch|${DD}concurrency"

require_literal() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

# require_match <message> <pattern> <file> [file...]
# 带失败信息的 grep 断言：message 必须作为第一个参数，便于定位失败契约。
# 失败时输出原因、期望 pattern 和第一个未命中的文件。
require_match() {
  local message="$1"
  local pattern="$2"
  shift 2
  local file
  for file in "$@"; do
    [ -n "$file" ] || continue
    if ! grep -Eq "$pattern" "$file"; then
      echo "$message: 未匹配 /$pattern/ in $file" >&2
      exit 1
    fi
  done
}

grep -q "### 第六步：持久化报告文件" "$AGENT_FILE"
grep -q "REPORT_FILENAME" "$AGENT_FILE"
grep -q "所有上传和本地输出都必须复用同一个 Markdown 文件" "$AGENT_FILE"

if grep -q 'field-create .*"name":"备注","type":"text"' "$FEISHU_FILE"; then
  echo "默认主字段会重命名为备注，不应再创建重复的备注字段" >&2
  exit 1
fi

grep -q 'field-update .*"name":"备注","type":"text"' "$FEISHU_FILE"
require_match "飞书集成文档必须声明字段总数" "共 17 个字段" "$FEISHU_FILE"
if grep -q "负责人" "$FEISHU_FILE"; then
  echo "scan-stage Feishu Base schema must not include 负责人" >&2
  exit 1
fi

grep -q "### 第一步：提取项目路径" "$SKILL_FILE"
grep -q "优先提取 Git URL" "$SKILL_FILE"
require_literal "$SKILL_FILE" "### 第三步：语言探测与路由" "language detection must be the third explicit step before language-specific pre-scan"
require_literal "$SKILL_FILE" "### 第四步：按语言执行项目预扫描" "language-specific pre-scan must be explicitly routed after language detection"
if grep -q "### 第三步之后：语言探测与路由" "$SKILL_FILE"; then
  echo "language detection must not be documented after Java pre-scan" >&2
  exit 1
fi
LANG_DETECT_LINE="$(grep -n 'scripts/core/detect-language.sh' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
JAVA_SCAN_LINE="$(grep -n 'scripts/languages/java/project-scan.sh' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$LANG_DETECT_LINE" ] || [ -z "$JAVA_SCAN_LINE" ] || [ "$LANG_DETECT_LINE" -ge "$JAVA_SCAN_LINE" ]; then
  echo "detect-language must run before Java project-scan in the scan skill" >&2
  exit 1
fi

for scan_contract_file in "$SKILL_FILE" "$EXAMPLES_FILE" "$AGENTS_FILE" "$CLAUDE_FILE"; do
  if grep -qE "$SCAN_BYPASS_PATTERN" "$scan_contract_file"; then
    echo "scan contract must be interaction-only; remove command-parameter bypass compatibility from $scan_contract_file" >&2
    exit 1
  fi
done

grep -q "🧩 技术栈扫描" "$SKILL_FILE"
grep -q "识别数量" "$SKILL_FILE"
grep -q "| 技术栈 | 识别证据 | 建议维度 | 专项规则 |" "$SKILL_FILE"
grep -q "dependency:file:" "$SKILL_FILE"
grep -q "另有 {N} 个" "$SKILL_FILE"
grep -q "完整结果已注入子 agent" "$SKILL_FILE"
grep -q "preview-recent-commits" "$SKILL_FILE"
grep -q "最近提交概览" "$SKILL_FILE"
grep -q "prompt: 注入审查参数表 + 审查参考文件路径 + 项目概况 + 增量数据" "$SKILL_FILE"
grep -q "| 审查框架路径 | {REVIEW_FRAMEWORK_PATH} |" "$SKILL_FILE"
grep -q "| 报告格式路径 | {REPORT_FORMAT_PATH} |" "$SKILL_FILE"
require_literal "$SKILL_FILE" '| 审查输入清单 | {REVIEW_INPUT_PATH} |' "single-agent prompt must inject immutable review input"
require_literal "$SKILL_FILE" '| 项目审查规则解析结果 | {REVIEW_RULES_RESOLVED_PATH} |' "single-agent prompt must inject resolved project rules"
require_literal "$SKILL_FILE" 'scripts/core/resolve-review-rules.sh' "single-agent flow must resolve project review rules"
require_literal "$SKILL_FILE" 'review-input >/dev/null' "single-agent rule resolution must consume selected files from immutable review input"
if grep -q 'Java 单 agent 自行 Glob' "$SKILL_FILE"; then
  echo "single-agent Java must consume immutable review input instead of rediscovering files" >&2
  exit 1
fi
grep -q 'REVIEW_FRAMEWORK_PATH=.*references/languages/java/review-framework.md' "$SKILL_FILE"
grep -q 'REPORT_FORMAT_PATH=.*references/report-format.md' "$SKILL_FILE"
GLOBAL_REFERENCE_LINE="$(grep -n "### 第六步之前：准备审查参考文件路径" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
TASK_LAUNCH_LINE="$(grep -n "### 第七步：调用子 agent 执行代码审查" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$GLOBAL_REFERENCE_LINE" ] || [ -z "$TASK_LAUNCH_LINE" ] || [ "$GLOBAL_REFERENCE_LINE" -ge "$TASK_LAUNCH_LINE" ]; then
  echo "review reference path preparation must be a global pre-Task step before launching the reviewer agent" >&2
  exit 1
fi

grep -q "REVIEW_FRAMEWORK_PATH" "$AGENT_FILE"
grep -q "REPORT_FORMAT_PATH" "$AGENT_FILE"
grep -q "优先读取主 agent 注入的绝对路径" "$AGENT_FILE"
if grep -q "| 飞书上传选项 |" "$AGENT_FILE"; then
  echo "review agent must not document FEISHU_UPLOAD_OPTION as an injected parameter; main skill owns upload handling" >&2
  exit 1
fi
require_literal "$AGENT_FILE" "报告保存方式不注入本子 agent" "review agent must explicitly state report handling is not injected"
grep -q "IGNORE_RULES_PATH" "$AGENT_FILE"
grep -q "IGNORE_RULES_CONTENT" "$AGENT_FILE"
grep -q "先应用项目 ignore 规则" "$AGENT_FILE"
grep -q "命中 ignore.skip_when 的同类问题，不得输出" "$AGENT_FILE"
require_literal "$SKILL_FILE" "已忽略 {IGNORE_RULE_COUNT} 个问题" "scan preflight summary must show project ignore issue count"
require_literal "$SKILL_FILE" '只统计 `ignore:` 下缩进 2 个空格的 `- name:`' "ignore count must exclude nested applies_to list items"
require_literal "$AGENT_FILE" "不包含 applies_to 下的子列表项" "agent ignore count docs must exclude nested applies_to list items"
require_literal "$EXAMPLES_FILE" "已忽略 2 个问题" "scan examples must show project ignore issue count"
require_literal "$AGENT_FILE" "P0 五项硬门槛（必须全部满足）" "review agent must define all mandatory P0 gates"
require_literal "$AGENT_FILE" "生产可达" "P0 must require a production-reachable path"
require_literal "$AGENT_FILE" "置信度必须为高" "P0 must require high confidence"
require_literal "$AGENT_FILE" "事故级影响" "P0 must require incident-level impact"
require_literal "$AGENT_FILE" "缺少有效防护" "P0 must account for effective mitigations"
require_literal "$AGENT_FILE" "阻断发布" "P0 must be release-blocking"
require_literal "$AGENT_FILE" "证据成立但影响未达到事故级" "confirmed non-P0 findings must downgrade to P1"
require_literal "$AGENT_FILE" "归入待确认" "unproven high-risk findings must move to pending confirmation"
require_literal "$AGENT_FILE" "不得因为未通过 P0 门槛而静默丢弃" "non-fast modes must preserve downgraded findings"
require_literal "$AGENT_FILE" "fast 模式无条件只输出满足 P0 五项硬门槛的 P0；P1、P2、P3 和待确认均不输出" "fast mode must output only fully qualified P0 findings"
if grep -Fq "置信度不影响级别判断" "$AGENT_FILE"; then
  echo "confidence must participate in severity classification; remove the obsolete rule" >&2
  exit 1
fi

require_literal "$REPORT_FORMAT_FILE" '### P0-N | [维度名称] {问题一句话标题}' "report format must use third-level headings for issue entries"
require_literal "$REPORT_FORMAT_FILE" '### P1-N | [维度名称] {问题一句话标题}' "report format must use third-level headings for P1 issue entries"
require_literal "$REPORT_FORMAT_FILE" '### 待确认-N | [维度名称] {问题一句话标题}' "report format must use third-level headings for pending issue entries"
require_literal "$REPORT_FORMAT_FILE" 'P0 为 0 时仍必须保留本节' "report format must require an explicit empty P0 section"
require_literal "$REPORT_FORMAT_FILE" '本次未发现满足 P0 五项硬门槛的问题' "report format must state when no P0 findings were found"
require_literal "$AGENT_FILE" 'P0 为 0 时也必须输出 P0 章节' "review agent must not omit an empty P0 section"
require_literal "$FRONTEND_AGENT_FILE" 'P0 为 0 时也必须输出 P0 章节' "frontend agent must not omit an empty P0 section"
if grep -qE '^## P[0-3]-N \|' "$REPORT_FORMAT_FILE" || grep -qE '^## 待确认-N \|' "$REPORT_FORMAT_FILE"; then
  echo "issue entries must not use the same heading level as severity sections" >&2
  exit 1
fi
if grep -qE '^\*\*问题编号\*\*：P[0-3]-N' "$REPORT_FORMAT_FILE"; then
  echo "report format must not allow legacy bold 问题编号 entries for scan findings" >&2
  exit 1
fi
require_literal "$AGENT_FILE" '三级标题 `### {编号} | [维度] 标题`' "review agent must instruct third-level issue headings"
require_literal "$FRONTEND_AGENT_FILE" '三级标题 `### {问题编号} | [维度名称] {问题一句话标题}`' "frontend agent must follow shared third-level issue headings"

BATCH_P0_TEMPLATE="$(awk '
  /^## Batch 发现清单输出格式$/ { in_batch_format = 1; next }
  in_batch_format && /^### P0 \|/ { in_p0_template = 1 }
  in_p0_template && /^### P[1-3] \|/ { exit }
  in_p0_template { print }
' "$AGENT_FILE")"
if [ -z "$BATCH_P0_TEMPLATE" ]; then
  echo "batch finding format must contain a structured P0 template" >&2
  exit 1
fi
for batch_p0_field in \
  "置信度：高" \
  "生产可达路径：" \
  "事故级影响：" \
  "有效防护核查：" \
  "阻断发布理由："; do
  if ! printf '%s\n' "$BATCH_P0_TEMPLATE" | grep -Fq -- "$batch_p0_field"; then
    echo "batch P0 template must include audit field: $batch_p0_field" >&2
    exit 1
  fi
done

require_literal "$EXAMPLES_FILE" "高置信已证实：生产订单请求参数直达未参数化 SQL，无有效校验或绑定防护，可破坏关键订单数据，必须阻断发布" "large-repo SQL injection P0 example must summarize all five gates"
require_literal "$EXAMPLES_FILE" "高置信已证实：生产支付链路发生部分提交，无回滚或补偿防护，可造成资金错误，必须阻断发布" "large-repo transaction P0 example must summarize all five gates"
require_literal "$ROOT_DIR/references/languages/java/review-framework.md" "P0 五项硬门槛" "review framework must share the strict P0 contract"
require_literal "$ROOT_DIR/references/report-format.md" "P0 证据门槛" "report format must require P0 gate evidence"
require_literal "$ROOT_DIR/references/report-format.md" '**置信度**：高 | **所属维度**：维度名称' "P0 report template must require high confidence"
for performance_contract_file in \
  "$ROOT_DIR/references/languages/java/review-framework.md" \
  "$ROOT_DIR/references/languages/frontend/review-framework.md" \
  "$ROOT_DIR/references/languages/python/review-framework.md" \
  "$AGENT_FILE" \
  "$FRONTEND_AGENT_FILE" \
  "$ROOT_DIR/agents/cc-code-reviewer-python.md"; do
  require_literal "$performance_contract_file" "性能问题分级边界" "performance findings must have explicit severity boundaries"
  require_literal "$performance_contract_file" "关键路径性能风险且已证实会显著影响稳定性：P1" "confirmed critical-path performance risks must map to P1"
  require_literal "$performance_contract_file" "普通性能问题或局部性能风险：P2" "ordinary performance risks must map to P2"
  require_literal "$performance_contract_file" "泛优化建议且缺少明确风险链路：P3" "general performance suggestions must map to P3"
  require_literal "$performance_contract_file" "怀疑很严重但缺少生产路径、调用频率、运行配置、表结构、索引或执行计划证据：待确认" "unproven severe performance risks must map to pending confirmation"
done

for security_contract_file in \
  "$ROOT_DIR/references/languages/java/review-framework.md" \
  "$AGENT_FILE"; do
  require_literal "$security_contract_file" "安全问题分级边界" "security findings must have explicit severity boundaries"
  require_literal "$security_contract_file" "安全问题必须先逐项核验 P0 五项硬门槛" "security findings must preserve the shared five-gate P0 contract"
  require_literal "$security_contract_file" "公网/内网、匿名/已认证" "network location and authentication prerequisites must be treated as evidence"
  require_literal "$security_contract_file" "不得单独决定级别上限" "security prerequisites must not impose an automatic severity ceiling"
  require_literal "$security_contract_file" "网络位置或登录前置条件不自动降级" "authenticated or internal critical vulnerabilities must not be automatically downgraded"
  require_literal "$security_contract_file" "仅“位于内网”或“需要登录”本身不足以判定为 P1" "internal or authenticated reachability alone must not force P1"
  require_literal "$security_contract_file" "泛化安全加固建议、缺少可达路径证据或仅依赖代码形态推测：P2/P3" "general security hardening must map to P2/P3"
  require_literal "$security_contract_file" "怀疑是高危但缺少生产可达性、调用链或运行配置证据：待确认" "unproven severe security risks must map to pending confirmation"
done

for security_invariant_file in \
  "$ROOT_DIR/references/languages/java/review-framework.md" \
  "$ROOT_DIR/references/languages/frontend/review-framework.md" \
  "$ROOT_DIR/references/languages/python/review-framework.md" \
  "$AGENT_FILE" \
  "$FRONTEND_AGENT_FILE" \
  "$ROOT_DIR/agents/cc-code-reviewer-python.md"; do
  require_literal "$security_invariant_file" "高危安全问题必为 P0" "confirmed incident-level security findings must be P0 without probability-based downgrade"
  require_literal "$security_invariant_file" "反向降级必须证明触发路径生产不可达" "security downgrades must require proof of unreachability, not low-probability claims"
  require_literal "$security_invariant_file" "fail-open" "auth fail-open must be treated as authentication bypass"
  require_literal "$security_invariant_file" "认证绕过" "fail-open and trust-boundary defects must map to authentication bypass grading"
  require_literal "$security_invariant_file" "P0 待验证" "trust-boundary defects pending external evidence must be marked as P0-pending"
done

require_literal "$ROOT_DIR/references/languages/java/review-framework.md" 'credentialed request 与 `Access-Control-Allow-Origin: *` 的组合会被浏览器 CORS 校验拒绝' "wildcard ACAO with credentials must be classified as a rejected CORS configuration"
require_literal "$ROOT_DIR/references/languages/java/review-framework.md" '反射任意 `Origin`' "credentialed arbitrary-origin reflection must remain the actionable CORS risk"
require_literal "$ROOT_DIR/references/languages/java/review-framework.md" "个人信息（PII，Personally Identifiable Information" "personal-data review rules must use the standard PII term"

grep -q "collect-fix-metadata" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE"
if [ ! -f "$ARCHITECTURE_PNG" ]; then
  echo "架构总览图缺失: $ARCHITECTURE_PNG" >&2
  exit 1
fi
require_literal "$ROOT_DIR/README.md" "(docs/assets/architecture-overview.png)" "README must reference the versionless architecture overview image"
if grep -q "architecture-overview-v" "$ROOT_DIR/README.md"; then
  echo "README must not reference stale versioned architecture copies (architecture-overview-v*)" >&2
  exit 1
fi
if [ -f "$ARCHITECTURE_SVG" ]; then
  echo "architecture overview is imagegen PNG-only; SVG source should not be kept" >&2
  exit 1
fi

grep -q "🧩 技术栈扫描" "$EXAMPLES_FILE"
grep -q "飞书保存不可用" "$EXAMPLES_FILE"
grep -q "报告已保存到" "$EXAMPLES_FILE"
grep -q "项目 ignore 命中" "$EXAMPLES_FILE"

if [ ! -f "$IGNORE_SKILL_FILE" ]; then echo "ignore skill 缺失: $IGNORE_SKILL_FILE" >&2; exit 1; fi
if [ ! -f "$IGNORE_WORKFLOW_FILE" ]; then echo "ignore workflow 缺失: $IGNORE_WORKFLOW_FILE" >&2; exit 1; fi
require_match "ignore 文档必须声明 AI 指令型语义" "AI 指令型 ignore 文件" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须包含默认文件路径" '\.cc-code-reviewer/ignore/issues\.yml' "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE" "$SKILL_FILE" "$AGENT_FILE"
# 注意：以下断言原本就是 grep -q 多文件"任一命中"语义（skill 与 workflow 措辞不同），
# 不能用 require_match（它要求所有文件命中），故保留 grep -q 但补充失败说明。
if ! grep -q "不存报告编号" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"; then
  echo "ignore 文档必须声明不存报告编号 (skill 与 workflow 任一命中即可)" >&2
  exit 1
fi
require_match "ignore workflow YAML 必须包含 name 字段示例" "name:" "$IGNORE_WORKFLOW_FILE"
require_match "ignore workflow YAML 必须包含 applies_to 字段示例" "applies_to:" "$IGNORE_WORKFLOW_FILE"
require_match "ignore workflow YAML 必须包含 skip_when 字段示例" "skip_when:" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须支持飞书 Base 来源" "飞书 Base" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须支持本地 Markdown 来源" "本地 Markdown" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"
require_match "ignore 文档必须描述用户指定问题编号流程" "用户指定问题编号" "$IGNORE_SKILL_FILE" "$IGNORE_WORKFLOW_FILE"

grep -qx "# Fix Workflow" "$FIX_WORKFLOW_FILE"
grep -qx "## Fix Input Normalization" "$FIX_WORKFLOW_FILE"
grep -qx "## Preflight Sequence" "$FIX_WORKFLOW_FILE"
grep -qx "## Execution Route Selection" "$FIX_WORKFLOW_FILE"
grep -qx "## Direct Fix Flow" "$FIX_WORKFLOW_FILE"
grep -qx "## Superpowers Flow" "$FIX_WORKFLOW_FILE"
grep -qx "## Degraded Mode" "$FIX_WORKFLOW_FILE"
grep -qx "## Fix Scope Rules" "$FIX_WORKFLOW_FILE"
grep -qx "## Workspace Rules" "$FIX_WORKFLOW_FILE"
grep -q "brainstorming" "$FIX_WORKFLOW_FILE"
grep -q "test-driven-development" "$FIX_WORKFLOW_FILE"
grep -q "verification-before-completion" "$FIX_WORKFLOW_FILE"
grep -q "交互确认是硬门禁" "$FIX_WORKFLOW_FILE"
grep -q "Superpowers 可选" "$FIX_WORKFLOW_FILE"
grep -q "直接修复路线必须确认工作区策略" "$FIX_WORKFLOW_FILE"
grep -q "subagent-driven-development" "$FIX_WORKFLOW_FILE"
grep -q "无已归一化问题上下文时必须停止修复" "$FIX_WORKFLOW_FILE" "$FIX_FEISHU_FILE"
grep -q "Other/free-form 中粘贴" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "一次 INTERACT 收集问题清单位置" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "根据输入动态识别" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不得先让用户选择本地 Markdown、飞书云文档或飞书多维表格" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
if grep -q "请提供本次待修复问题确认清单的来源" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "fix flow must collect a single source/path input and infer the source type dynamically" >&2
  exit 1
fi
grep -q "本地 Markdown 必须直接读取文件内容" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "不得使用 Python 脚本读取飞书云文档或飞书多维表格" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_FEISHU_FILE"
grep -q "飞书云文档和飞书多维表格不得调用.*detect-fix-input" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "状态过滤" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_FEISHU_FILE"
grep -q "STATUS_FILTERED_ISSUES" "$FIX_WORKFLOW_FILE"
grep -q "SKIPPED_STATUS_COUNTS" "$FIX_WORKFLOW_FILE"
grep -q "已修复.*已忽略.*不适用" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "已修复项不得出现在表格中" "$FIX_EXAMPLES_FILE"
grep -q "跳过记录不得出现在待确认问题表格" "$FIX_FEISHU_FILE"
grep -q "一个写回原始来源选项" "$FIX_WORKFLOW_FILE"
grep -q "创建独立本地 Markdown 修复报告" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "创建独立飞书云文档修复报告" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "创建独立飞书多维表格修复报告" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "写回原始本地 Markdown" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "写回原始飞书云文档" "$FIX_SKILL_FILE"
grep -q "写回原始飞书多维表格" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不得在修复完成后追加新的回写确认问题" "$FIX_WORKFLOW_FILE"
grep -q "不得修改原始问题清单来源" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_FEISHU_FILE" "$FIX_REPORT_FILE"
grep -q "FIX_COMPLETED_AT" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE"
grep -q "FIX_ACTOR" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE"
grep -q "修复人" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不得再询问用户" "$FIX_SKILL_FILE" "$FIX_WORKFLOW_FILE"
if grep -q "是否把修复状态更新回问题清单源" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "fix flow must not add a separate post-repair writeback INTERACT" >&2
  exit 1
fi
if grep -q "SOURCE_STATUS_WRITEBACK" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE" "$FIX_REPORT_FILE"; then
  echo "source writeback must be folded into OUTPUT_TARGET, not tracked as a separate prompt" >&2
  exit 1
fi
if grep -qE "模型 / effort|MODEL_PREFERENCE|EFFORT_PREFERENCE" "$FIX_WORKFLOW_FILE"; then
  echo "fix workflow must not require model/effort confirmation" >&2
  exit 1
fi
if grep -q "$QUICK_START_CN" "$FIX_WORKFLOW_FILE"; then
  echo "fix workflow must not mention command-parameter bypass flow" >&2
  exit 1
fi

grep -qx "# 修复报告格式规范" "$FIX_REPORT_FILE"
grep -q "## 修复配置快照" "$FIX_REPORT_FILE"
grep -q "## 修复输入摘要" "$FIX_REPORT_FILE"
grep -q "## 已修复问题" "$FIX_REPORT_FILE"
grep -q "## 部分修复问题" "$FIX_REPORT_FILE"
grep -q "## 未修复问题" "$FIX_REPORT_FILE"
grep -q "## 测试变更" "$FIX_REPORT_FILE"
grep -q "## 验证命令与结果" "$FIX_REPORT_FILE"
grep -q "## 代码变更摘要" "$FIX_REPORT_FILE"
grep -q "## 飞书回写结果" "$FIX_REPORT_FILE"
grep -q "## 后续建议" "$FIX_REPORT_FILE"

grep -qx "# Fix Feishu Integration" "$FIX_FEISHU_FILE"
grep -qx "## 读取飞书云文档" "$FIX_FEISHU_FILE"
grep -qx "## 读取飞书多维表格" "$FIX_FEISHU_FILE"
grep -qx "## 更新飞书多维表格" "$FIX_FEISHU_FILE"
grep -qx "## 创建修复报告云文档" "$FIX_FEISHU_FILE"
grep -qx "## 失败降级" "$FIX_FEISHU_FILE"
grep -q "修复状态" "$FIX_FEISHU_FILE"
grep -q "修复时间" "$FIX_FEISHU_FILE"
grep -q "修复分支" "$FIX_FEISHU_FILE"
grep -q "所属维度" "$FIX_FEISHU_FILE"
grep -q "置信度" "$FIX_FEISHU_FILE"
grep -q "证据" "$FIX_FEISHU_FILE"
grep -q "影响" "$FIX_FEISHU_FILE"
grep -q "备注" "$FIX_FEISHU_FILE"
grep -q "lark-cli base" "$FIX_FEISHU_FILE"
grep -q "wiki spaces get_node" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "obj_token" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE" "$FIX_SKILL_FILE"
grep -q "查询参数 .*table" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE"
grep -q "查询参数 .*view" "$FIX_FEISHU_FILE" "$FIX_WORKFLOW_FILE"
grep -q -- "--table-id" "$FIX_FEISHU_FILE" "$FIX_SKILL_FILE"
grep -q "docs +fetch --api-version v2 --doc" "$FIX_FEISHU_FILE"
grep -q "docs +create" "$FIX_FEISHU_FILE"
grep -q -- "--api-version v2" "$FIX_FEISHU_FILE"
grep -q -- "--doc-format markdown" "$FIX_FEISHU_FILE"
grep -q -- "--content @fix-report" "$FIX_FEISHU_FILE"
if grep -q "docs +fetch --url" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "Task 4 fixer docs must use docs +fetch --api-version v2 --doc, not --url" >&2
  exit 1
fi
if grep -A6 "docs +create" "$FIX_FEISHU_FILE" | grep -q -- "--title"; then
  echo "Task 4 fixer docs must not use unsupported docs +create --title" >&2
  exit 1
fi
if grep -q -- "--markdown @" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "Task 4 fixer docs must create docs with docs +create --api-version v2 --doc-format markdown --content" >&2
  exit 1
fi
if grep -q "+record-update" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "Task 4 fixer docs must use base +record-upsert --record-id, not +record-update" >&2
  exit 1
fi
grep -q "+record-upsert" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"

grep -qx "# Fix Examples" "$FIX_EXAMPLES_FILE"
grep -qx "## 本地 Markdown 报告" "$FIX_EXAMPLES_FILE"
grep -qx "## 飞书多维表格" "$FIX_EXAMPLES_FILE"
grep -q "待修复问题确认清单" "$FIX_EXAMPLES_FILE"
grep -q "问题清单位置" "$FIX_EXAMPLES_FILE"
grep -q "| 问题ID | 严重级别 | 维度 | 问题摘要 | 修复建议 |" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"
grep -q "不要输出项目符号列表" "$FIX_SKILL_FILE"
grep -q "问题摘要和修复建议必须压缩成终端可扫读的短句" "$FIX_SKILL_FILE"
if grep -q "| 问题ID | 严重级别 | 维度 | 置信度 | 位置 | 问题摘要 | 修复建议 |" "$FIX_SKILL_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "fix issue confirmation table must use compact terminal table columns, not the old wide table" >&2
  exit 1
fi
if grep -q "$QUICK_START_CN" "$FIX_EXAMPLES_FILE"; then
  echo "fix examples must not document command-parameter bypass flow" >&2
  exit 1
fi

grep -q "模式判定" "$FIX_SKILL_FILE"
grep -q "detect-fix-input" "$FIX_SKILL_FILE"
grep -q "detect-superpowers" "$FIX_SKILL_FILE"
grep -q "修复输入解析完成" "$FIX_SKILL_FILE"
grep -q "INTERACT" "$FIX_SKILL_FILE"
grep -q "待修复问题确认清单" "$FIX_SKILL_FILE"
grep -q "问题清单位置" "$FIX_SKILL_FILE"
grep -q "问题清单表格" "$FIX_SKILL_FILE"
grep -q "执行方式" "$FIX_SKILL_FILE"
grep -q "直接开始修复" "$FIX_SKILL_FILE"
grep -q "使用 Superpowers 修复" "$FIX_SKILL_FILE"
grep -q "SUPERPOWERS_AVAILABLE=true 时才展示" "$FIX_SKILL_FILE"
grep -q "请选择直接修复使用的工作区策略" "$FIX_SKILL_FILE"
grep -q "确认执行计划" "$FIX_SKILL_FILE"
grep -q "brainstorming" "$FIX_SKILL_FILE"
grep -q "subagent-driven-development" "$FIX_SKILL_FILE"
if grep -qE "${MODE_BYPASS_TOKEN}|${PARAMS_BYPASS_TOKEN}|${QUICK_START_CN}|\`${DD}scope\`|\`${DD}workspace\`|\`${DD}strategy\`" "$FIX_SKILL_FILE"; then
  echo "cc-code-fixer must not contain command-parameter bypass syntax" >&2
  exit 1
fi

# Fix agent removed: fix stage delegates to Superpowers (brainstorming → subagent-driven-development)
# Key contracts now live in fix-report-format.md and fix-feishu-integration.md
grep -q "fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$FIX_REPORT_FILE"
grep -q "fix-report-" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"
if grep -qE "minimal|with-tests|目标分支|输出选项|TARGET_BRANCH|OUTPUT_OPTION|fixed|partially fixed|not fixed|not applicable|needs human confirmation|code-fix-report" "$FIX_REPORT_FILE" "$FIX_FEISHU_FILE" "$FIX_EXAMPLES_FILE"; then
  echo "cc-code-fixer contracts must use unified strategy names, Chinese statuses, and fix-report filenames" >&2
  exit 1
fi

PLUGIN_VERSION="$(grep -E '"version":' "$PLUGIN_FILE" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
MARKETPLACE_VERSION="$(grep -E '"version":' "$MARKETPLACE_FILE" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
MARKETPLACE_PLUGIN_VERSION="$(grep -E '"version":' "$MARKETPLACE_FILE" | sed -n 2p | sed 's/.*"version": *"\([^"]*\)".*/\1/')"

# 版本号不再硬编码：只校验三处版本互相一致且非空。
# 发版时只需改 plugin.json + marketplace.json 两个文件，本测试自动跟随。
version_assert() {
  local left="$1" right="$2" label="$3"
  if [ "$left" != "$right" ]; then
    echo "版本不一致 ($label): '$left' != '$right'" >&2
    exit 1
  fi
  if [ -z "$left" ]; then
    echo "版本号为空 ($label)，请检查 plugin.json / marketplace.json 是否包含 \"version\" 字段" >&2
    exit 1
  fi
}
version_assert "$PLUGIN_VERSION" "$MARKETPLACE_VERSION" "plugin.json vs marketplace.json 顶层"
version_assert "$PLUGIN_VERSION" "$MARKETPLACE_PLUGIN_VERSION" "plugin.json vs marketplace.json plugin 条目"
version_assert "$PLUGIN_VERSION" "$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_FILE" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')" "plugin.json 自身可解析"
require_match "plugin.json 必须声明 code-fixer 关键字" "code-fixer" "$PLUGIN_FILE"
require_match "plugin.json 必须声明 code-fix skill" '"code-fix"' "$PLUGIN_FILE"
require_match "marketplace.json 必须声明 code-fix skill" '"code-fix"' "$MARKETPLACE_FILE"
require_match "marketplace.json 描述必须包含 report-driven fixing" "report-driven fixing" "$MARKETPLACE_FILE"

# === Task 1: 三端清单与 VERSION 单一真相源 ===
# 版本同步从 Claude 两处一致扩展为所有平台清单与 VERSION 一致。
VERSION_TRUTH_FILE="$ROOT_DIR/VERSION"
[ -f "$VERSION_TRUTH_FILE" ] || { echo "VERSION 单一真相源缺失" >&2; exit 1; }
VERSION_TRUTH="$(tr -d '[:space:]' < "$VERSION_TRUTH_FILE")"
[ -n "$VERSION_TRUTH" ] || { echo "VERSION 内容为空" >&2; exit 1; }
version_assert "$PLUGIN_VERSION" "$VERSION_TRUTH" "plugin.json vs VERSION"
# Codex / ZCode 原生清单必须与 VERSION 一致；Codex marketplace 版本由 source 指向的 plugin.json 提供。
CODEX_PLUGIN_FILE="$ROOT_DIR/.codex-plugin/plugin.json"
CODEX_MARKET_FILE="$ROOT_DIR/.agents/plugins/marketplace.json"
ZCODE_PLUGIN_FILE="$ROOT_DIR/.zcode-plugin/plugin.json"
for t1_manifest in "$CODEX_PLUGIN_FILE" "$ZCODE_PLUGIN_FILE"; do
  [ -f "$t1_manifest" ] || { echo "三端清单缺失: $t1_manifest" >&2; exit 1; }
  t1_ver="$(grep -E '"version":' "$t1_manifest" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')"
  version_assert "$t1_ver" "$VERSION_TRUTH" "$(basename "$(dirname "$t1_manifest")")/$(basename "$t1_manifest") vs VERSION"
done
[ -f "$CODEX_MARKET_FILE" ] || { echo "Codex marketplace 清单缺失: $CODEX_MARKET_FILE" >&2; exit 1; }
# 三端清单 name 必须全部为 cc-code-reviewer
for t1_name_file in "$CODEX_PLUGIN_FILE" "$ZCODE_PLUGIN_FILE"; do
  t1_name="$(grep -E '"name":' "$t1_name_file" | head -1 | sed 's/.*"name": *"\([^"]*\)".*/\1/')"
  [ "$t1_name" = "cc-code-reviewer" ] || { echo "三端清单 name 不一致: $t1_name_file => '$t1_name'" >&2; exit 1; }
done
# 集成校验脚本必须通过
bash "$ROOT_DIR/scripts/core/validate-plugin-manifests.sh" >/dev/null || { echo "validate-plugin-manifests.sh 校验失败" >&2; exit 1; }

# === Batch scanning contracts ===

# === Maven large repository batching contracts ===

grep -q "languages/java/detect-code-intelligence.sh" "$SKILL_FILE"
grep -q "languages/java/plan-large-batches.sh" "$SKILL_FILE"
grep -q "core/merge-batch-results.sh" "$SKILL_FILE"
grep -q "core/show-batch-status.sh" "$SKILL_FILE"

grep -q "Maven 多模块" "$SKILL_FILE"
grep -q "存量审查" "$SKILL_FILE"
grep -q "全量代码" "$SKILL_FILE"
require_literal "$SKILL_FILE" "estimated_tokens > 1000000" "batch trigger must require more than 1M estimated tokens"

grep -q "TARGET_BATCH_LOC = 250000" "$SKILL_FILE"
grep -q "SOFT_MIN_BATCH_LOC = 150000" "$SKILL_FILE"
grep -q "SOFT_MAX_BATCH_LOC = 250000" "$SKILL_FILE"
grep -q "HARD_MAX_BATCH_LOC = 250000" "$SKILL_FILE"
require_literal "$SKILL_FILE" "semantic-cost batching" "large repo strategy must be semantic-cost batching"
require_literal "$SKILL_FILE" "review_cost = java_loc + java_file_count * 25" "review cost formula must be documented"
require_literal "$SKILL_FILE" "TARGET_BATCH_COST = 260000" "fixed 1M target review cost must be documented"
require_literal "$SKILL_FILE" "HARD_MAX_BATCH_COST = 325000" "fixed 1M hard review cost must be documented"
require_literal "$SKILL_FILE" "固定 1M 机制" "SKILL must document fixed 1M batching"
require_literal "$SKILL_FILE" "context_roots" "large repo plan must include bounded context roots"
require_literal "$SKILL_FILE" "context cost" "large repo context cost must be bounded"
require_literal "$SKILL_FILE" "work units" "large repo planner must use work units"
require_literal "$SKILL_FILE" "oversized modules are split before plan emission" "oversized modules must be split, not only marked"
require_literal "$SKILL_FILE" "tiny tail batches" "tiny tail batches must be rebalanced"

require_literal "$AGENT_FILE" "context_roots" "batch agent must understand context roots"
require_literal "$AGENT_FILE" "Formal findings must point to locations inside scan_roots" "batch findings must stay inside scan roots"
require_literal "$AGENT_FILE" "context_roots are read-only context" "agent must not count context roots as reviewed"
require_literal "$AGENT_FILE" '`src/main/java` 生产 Java 文件作为本批正式审查范围' "batch agent must scan only production Java sources"
require_literal "$AGENT_FILE" '`src/test/java` 只能作为测试质量判断的只读上下文' "batch agent must keep test sources contextual"

require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "TARGET_BATCH_COST=260000" "planner must use fixed 1M target cost"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "HARD_MAX_BATCH_COST=325000" "planner must use fixed 1M hard cost"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" 'effective_max_cost="$HARD_MAX_BATCH_COST"' "affinity relaxation must be clamped to the hard cost limit"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "CONTEXT_WINDOW_TOKENS=1000000" "planner must emit fixed 1M context"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "CONTEXT_SCALE=5" "planner must emit fixed context scale metadata"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "review_cost" "planner must compute review cost"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "context_roots" "planner must emit context roots"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "semantic-cost-batching" "planner must emit semantic-cost strategy"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "SELECTED_MODULE_OUTSIDE_PROJECT" "planner must reject selected modules outside project root"
require_match "status 须定义固定 1M 批次成本基准" 'TARGET_REVIEW_COST' "$ROOT_DIR/scripts/core/show-batch-status.sh"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "RUN_BATCH_IDS" "merge must honor the current-run batch set"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "[合并阻塞]" "merge must report blocked current-run batches"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "批次状态总览" "merge report must include all batch statuses"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "report_title" "merge summary must expose a cloud-doc title"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "dedupe_issue_blocks" "merge must dedupe included batch findings"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "INCLUDED_BATCHES" "merge completeness must depend on included batches"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "审查配置快照" "merge report must include config snapshot section"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "覆盖限制与未审查范围" "merge report must disclose coverage limitations"
require_literal "$SKILL_FILE" "合并脚本等待本轮批次进入终态" "skill must document merge waiting"
require_literal "$SKILL_FILE" 'failed`，或 `completed` 但结果文件缺失' "skill must block failed or missing batch results"
require_literal "$SKILL_FILE" "summary.json.report_title" "skill must validate merged cloud-doc title"
require_literal "$SKILL_FILE" "SELECTED_MODULE_OUTSIDE_PROJECT" "skill must document selected-module boundary rejection"
require_literal "$SKILL_FILE" "已纳入合并的批次数" "skill must document staged/full merge based on included batches"
require_literal "$SKILL_FILE" "固定预算门禁" "fixed 1M budget must be validated before batch execution"
if grep -q "进入步骤 5C 选择审查模型" "$SKILL_FILE"; then
  echo "SKILL must not tell agents to choose the review model after batch/concurrency planning." >&2
  exit 1
fi
require_literal "$AGENTS_FILE" "report_title" "AGENTS must document merged report title contract"
require_literal "$CLAUDE_FILE" "report_title" "CLAUDE must document merged report title contract"
require_literal "$AGENTS_FILE" "Selected module paths must be relative paths inside" "AGENTS must document selected-module boundary"
require_literal "$CLAUDE_FILE" "Selected module paths must be relative paths inside" "CLAUDE must document selected-module boundary"
require_literal "$AGENTS_FILE" "HARD_MAX_BATCH_COST=325000" "AGENTS must document affinity hard-cost clamp"
require_literal "$CLAUDE_FILE" "HARD_MAX_BATCH_COST=325000" "CLAUDE must document affinity hard-cost clamp"
require_literal "$AGENTS_FILE" 'stable `item_id` values must remain identical across clone/workspace roots' "AGENTS must document stable coverage IDs"
require_literal "$CLAUDE_FILE" 'stable `item_id` values must remain identical across clone/workspace roots' "CLAUDE must document stable coverage IDs"
require_literal "$AGENTS_FILE" 'Immutable `REVIEW_INPUT_PATH` and `REVIEW_RULES_RESOLVED_PATH`' "AGENTS must document single-agent immutable input injection"
require_literal "$CLAUDE_FILE" 'Immutable `REVIEW_INPUT_PATH` and `REVIEW_RULES_RESOLVED_PATH`' "CLAUDE must document single-agent immutable input injection"
require_literal "$ROOT_DIR/references/report-format.md" "[合并阻塞]" "report format must document blocked merge reports"
require_literal "$ROOT_DIR/references/report-format.md" "分批合并报告格式" "report format must document deterministic merge report shape"

# === v1.6.5: 文件类型专项清单 / 内容指纹去重 / 失败归因枚举 / 续跑准入门禁 ===
# T1 文件类型专项清单：resolver 叠加映射 + 守卫测试落盘
require_literal "$ROOT_DIR/scripts/core/resolve-review-rules.sh" "filetype_checklists" "rule resolver must emit additive filetype_checklists groups"
test -f "$ROOT_DIR/scripts/core/filetype-rule-map.json" || { echo "filetype-rule-map.json 缺失" >&2; exit 1; }
test -f "$ROOT_DIR/tests/core/test_core_filetype_rule_map.sh" || { echo "文件类型专项清单完整性守卫测试缺失" >&2; exit 1; }
require_literal "$SKILL_FILE" "filetype_checklists" "skill must disclose the filetype checklist overlay in resolved rules"
# T2 内容指纹去重：merge 脚本保留 dedupe_issue_blocks（上方既有 pin），并固化 summary 披露口径
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "merged_duplicates" "summary.json must expose cross-batch dedup stats via the dedup object"
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "failed_by_class" "summary.json must expose the failed_by_class attribution object"
require_literal "$SKILL_FILE" "行号不入键" "cross-batch dedup identity must document that line numbers are excluded from the fingerprint key"
require_literal "$ROOT_DIR/references/report-format.md" "跨批次去重：" "report format must document the cross-batch dedup disclosure line"
# README 必须出现 1.6.5 文件类型定向规则清单特性关键词
require_literal "$ROOT_DIR/README.md" "文件类型专项清单" "README must surface the filetype checklist feature keyword"
# T3 失败归因枚举：agents 状态写入 + merge 解析 + 展示前缀与统计行
for fc_agent_file in "$AGENT_FILE" "$FRONTEND_AGENT_FILE" "$ROOT_DIR/agents/cc-code-reviewer-python.md"; do
  require_literal "$fc_agent_file" "\"failure_class\"" "batch agent status JSON must carry failure_class attribution"
  require_literal "$fc_agent_file" "中断归因枚举" "batch agent must define the interruption attribution enum table"
done
require_literal "$ROOT_DIR/scripts/core/merge-batch-results.sh" "resolve_failure_class" "merge must resolve explicit failure_class then fall back to classifier/unknown"
require_literal "$ROOT_DIR/scripts/core/show-batch-status.sh" "失败归因: " "batch status output must include the optional attribution summary line"
require_literal "$ROOT_DIR/references/report-format.md" "失败归因枚举" "report format must document the five-value failure attribution enum"
require_literal "$ROOT_DIR/references/report-format.md" "[短标签]" "report format must document the localized error-column attribution prefix"
require_literal "$ROOT_DIR/references/report-format.md" "\"failed_by_class\"" "report format must document the per-class failure summary object"
# T4 续跑准入门禁：planner 快照字段 + 门禁脚本 + SKILL 接线
require_literal "$ROOT_DIR/scripts/core/plan-file-batches.sh" "rules_snapshot_sha256" "file planner must record the rules snapshot digest"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "rules_snapshot_sha256" "large-repo planner must record the rules snapshot digest"
test -f "$ROOT_DIR/scripts/core/validate-resume-input.sh" || { echo "validate-resume-input.sh 缺失" >&2; exit 1; }
require_literal "$SKILL_FILE" "validate-resume-input.sh" "resume flow must run the admission gate script before listing schedulable batches"
require_match "skill resume flow must invoke the admission gate with --rules" 'validate-resume-input\.sh.*--rules' "$SKILL_FILE"
require_literal "$SKILL_FILE" "不得列出任何可调度批次" "a non-ok resume gate result must block listing any schedulable batches"
require_match "AGENTS/CLAUDE must document the rules-scoped resume gate invocation" 'validate-resume-input\.sh <RUN_DIR> <PROJECT_DIR> --rules' "$AGENTS_FILE" "$CLAUDE_FILE"
require_literal "$AGENTS_FILE" "GATE_OK=" "AGENTS must document the gate's single-line GATE_OK pass contract"
require_literal "$CLAUDE_FILE" "GATE_OK=" "CLAUDE must document the gate's single-line GATE_OK pass contract"

grep -q "pending.*待执行" "$SKILL_FILE"
grep -q "running.*执行中" "$SKILL_FILE"
grep -q "completed.*已完成" "$SKILL_FILE"
grep -q "failed.*失败待重试" "$SKILL_FILE"
grep -q "partial.*部分完成待重跑" "$SKILL_FILE"
# 合法状态枚举固定为 5 值：pending/running/completed/failed/partial。
# partial（部分完成待重跑）是 1.6.4 起的合法终态：中断但已产出 ≥1 条发现时写入，
# 合并时纳入其发现但覆盖保守不计。仍禁止额外状态（stale/skipped/cancelled 等）混入。
FORBIDDEN_BATCH_STATE_DECL_PATTERN='("status"[[:space:]]*:[[:space:]]*"(stale|skipped|cancelled)")|((status[[:space:]_-]*(enum|state|list|value)|batch[[:space:]_-]*status|state[[:space:]_-]*(enum|list|value)|状态(枚举|列表|值)|批次状态)[^[:cntrl:]]{0,80}(stale|skipped|cancelled|中断待确认|已跳过|已取消))|((stale|skipped|cancelled|中断待确认|已跳过|已取消)[^[:cntrl:]]{0,80}(status[[:space:]_-]*(enum|state|list|value)|batch[[:space:]_-]*status|state[[:space:]_-]*(enum|list|value)|状态(枚举|列表|值)|批次状态))'
if grep -qE "$FORBIDDEN_BATCH_STATE_DECL_PATTERN" "$SKILL_FILE" "$AGENT_FILE"; then
  echo "large repo status enum must only use pending/running/completed/failed/partial" >&2
  exit 1
fi
# failure_class 合法值集合守卫（封闭五值）：任一契约文件声明 failure_class 时，
# 五个合法值 context_exhausted / tool_budget_exhausted / output_truncated /
# cancelled / unknown 必须齐全；非法样例 agent_crashed 与裸 tool_budget 不得作为
# 枚举值出现（JSON 值位、表格单元、斜杠罗列三种形态，模仿上方 FORBIDDEN 批次状态守卫）。
for fc_enum_file in "$SKILL_FILE" "$AGENT_FILE" "$FRONTEND_AGENT_FILE" "$ROOT_DIR/agents/cc-code-reviewer-python.md"; do
  if grep -q "failure_class" "$fc_enum_file"; then
    for fc_legal_value in context_exhausted tool_budget_exhausted output_truncated cancelled unknown; do
      grep -q "$fc_legal_value" "$fc_enum_file" || { echo "failure_class declaration must enumerate $fc_legal_value in $fc_enum_file" >&2; exit 1; }
    done
  fi
done
FORBIDDEN_FAILURE_CLASS_VALUE_PATTERN='"failure_class"[[:space:]]*:[[:space:]]*"(agent_crashed|tool_budget)"|\|[[:space:]]*(agent_crashed|tool_budget)[[:space:]]*\||/(agent_crashed|tool_budget)([^_a-z]|$)'
if grep -qE "$FORBIDDEN_FAILURE_CLASS_VALUE_PATTERN" "$SKILL_FILE" "$AGENT_FILE" "$FRONTEND_AGENT_FILE" "$ROOT_DIR/agents/cc-code-reviewer-python.md"; then
  echo "failure_class enum is closed to context_exhausted/tool_budget_exhausted/output_truncated/cancelled/unknown; agent_crashed and bare tool_budget are illegal values" >&2
  exit 1
fi
if awk '
  /pending|running|completed|failed|BATCH_STATUS_PATH|batch status|large repo status|large repository status|large repo v1|status\.json|批次状态|大仓状态|大型仓库状态|状态文件/ {
    for (i = NR - 6; i <= NR + 6; i++) {
      if (i > 0) {
        near_status[i] = 1
      }
    }
  }
  { lines[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++) {
      if (near_status[i]) {
        print lines[i]
      }
    }
  }
' "$SKILL_FILE" "$AGENT_FILE" | grep -qE "reviewed_java_files|remaining_files"; then
  echo "large repo v1 batch status contract must not use file-level reviewed manifests" >&2
  exit 1
fi

grep -q "scan_roots" "$SKILL_FILE"
grep -q "正式问题.*scan_roots" "$SKILL_FILE"
grep -q "jdtls.*跨目录" "$SKILL_FILE"
grep -q "jdtls-lsp 可用时必须使用" "$SKILL_FILE"
grep -q "跨批依赖待复核" "$SKILL_FILE"

grep -q "BATCH_PLAN_PATH" "$AGENT_FILE"
grep -q "BATCH_STATUS_PATH" "$AGENT_FILE"
grep -q "BATCH_RESULT_PATH" "$AGENT_FILE"
grep -q "scan_roots" "$AGENT_FILE"
grep -q "正式问题.*scan_roots" "$AGENT_FILE"
grep -q "jdtls-lsp 可用时必须使用" "$AGENT_FILE"
grep -q "definition、references、implementations、call hierarchy" "$AGENT_FILE"
grep -q "语义增强使用情况" "$AGENT_FILE"
grep -q "跨批依赖待复核" "$AGENT_FILE"

# Agent must support batch output mode
grep -q "审查输出模式" "$AGENT_FILE"
grep -q "仅发现清单" "$AGENT_FILE"
grep -q "完整报告" "$AGENT_FILE"
grep -q "批次编号" "$AGENT_FILE"
grep -q "BATCH_INDEX" "$AGENT_FILE"
grep -q "BATCH_FILE_LIST" "$AGENT_FILE"
grep -q "review-batch-" "$AGENT_FILE"

# Agent must skip stages in batch mode
grep -q "阶段 A.*跳过" "$AGENT_FILE"
grep -q "阶段 B.*跳过" "$AGENT_FILE"

# Skill must distinguish the 1M auto-trigger threshold from the 500k per-batch budget.
grep -q "BATCH_MODE" "$SKILL_FILE"
grep -q "estimated_tokens" "$SKILL_FILE"
require_literal "$SKILL_FILE" "estimated_tokens > 1000000" "batch trigger formula must use the 1M threshold"
require_literal "$SKILL_FILE" 'planner 的默认单批输入预算仍为 `500000`' "file-batch budget must remain distinct from the trigger threshold"
if grep -qE 'estimated_tokens > 500000|ESTIMATED_TOKENS > 500000|REVIEW_LINE_COUNT >= 120000' "$SKILL_FILE"; then
  echo "batch trigger must not retain the old 500k-token or 120k-line gates" >&2
  exit 1
fi
require_literal "$ROOT_DIR/README.md" "12 个前端维度" "README frontend dimension count must match the review framework"
if grep -q "11 个前端维度" "$ROOT_DIR/README.md"; then
  echo "README must not retain the old 11-dimension frontend contract" >&2
  exit 1
fi
if grep -qE 'token > 100,000|estimated_tokens > 500000|不少于 `120000` 行' "$EXAMPLES_FILE"; then
  echo "examples must use the strict 1M-token batch trigger" >&2
  exit 1
fi
require_literal "$EXAMPLES_FILE" 'estimated_tokens > 1000000' "examples must document the strict 1M-token batch trigger"

# Stock review entry must expose full and selected-module choices directly.
require_literal "$SKILL_FILE" 'label: "增量审查"' "review entry must keep incremental review"
require_literal "$SKILL_FILE" 'label: "全量审查"' "review entry must expose full stock review directly"
require_literal "$SKILL_FILE" 'label: "指定模块"' "review entry must expose selected-module stock review directly"
require_literal "$SKILL_FILE" "STOCK_REVIEW_STRATEGY" "stock review flow must capture the selected batching strategy"
require_literal "$SKILL_FILE" "module-sequential" "stock review flow must support per-module sequential batching"
require_literal "$SKILL_FILE" "ai-planned" "stock review flow must support AI planned batching"
require_literal "$SKILL_FILE" "STOCK_REVIEW_STRATEGY=single-agent" "stock review strategy must default to single-agent"
require_literal "$SKILL_FILE" "scripts/core/decide-batch-mode.sh" "batch decision must use the deterministic current-scope gate"
require_literal "$SKILL_FILE" '只有 `STEP_4B_REQUIRED=true` 才执行步骤 4B' "step 4B must only appear after the current-scope size gate"
require_literal "$SKILL_FILE" "小型 Maven 多模块项目即使是全量存量审查" "small Maven multi-module full reviews must remain single-agent"
require_literal "$SKILL_FILE" "按全部模块依次启动" "full review strategy must describe all modules"
require_literal "$SKILL_FILE" "按所选模块依次启动" "stock review strategy must describe per-module execution"
require_literal "$SKILL_FILE" "禁止把全量审查称为“所选模块”" "full review must not claim that modules were selected"
require_literal "$SKILL_FILE" "AI 智能规划分批" "stock review strategy must describe smart batching"
require_literal "$SKILL_FILE" "不得把每个模块都作为 INTERACT option" "module selection must avoid oversized INTERACT payloads"
require_literal "$SKILL_FILE" "最多 3 个固定选项" "module selection INTERACT must stay bounded"
require_literal "$SKILL_FILE" "Other/free-form" "module selection must allow manual free-form module paths"
if grep -q "模块超过 10 个时展示前 9 个" "$SKILL_FILE"; then
  echo "module selection must not dynamically add many module options" >&2
  exit 1
fi
require_literal "$SKILL_FILE" "Maven 多模块项目不得使用内联 Bash 数组分批" "Maven batch planning must use deterministic planner scripts"
require_literal "$SKILL_FILE" "languages/java/plan-large-batches.sh" "Maven batch planning must call plan-large-batches planner"
require_literal "$SKILL_FILE" "languages/java/plan-file-batches.sh" "single-module and non-Maven batching must call deterministic file planner"
require_literal "$SKILL_FILE" 'Maven 多模块存量分批绝不调用 `languages/java/plan-file-batches.sh`' "Maven selected-module batching must never fall back to whole-project file planner"
require_literal "$SKILL_FILE" "即使只选择一个模块" "single selected Maven module must still use the scoped Maven planner"
require_literal "$SKILL_FILE" "简要分批计划" "file batching must show a concise batch plan before concurrency selection"
require_literal "$SKILL_FILE" "BATCH_FILE_LIST_DIR" "file batching must expose batch file list directory for batch agents"
require_literal "$SKILL_FILE" "filter-source-manifest.sh" "frontend selected-directory scope must use the tested manifest filter"
require_literal "$SKILL_FILE" '*/src/{目录名}/' "frontend selected-directory scope must support package-local src roots in monorepos"
if grep -q 'PROJECT_DIR/src/\$sub' "$SKILL_FILE" || grep -q 'PREFIXES_FILE' "$SKILL_FILE"; then
  echo "frontend selected-directory scope must not assume a top-level PROJECT_DIR/src root" >&2
  exit 1
fi
if grep -q "当 BATCH_MODE=true 时，主 skill 在 prompt 中执行以下步骤（不使用脚本）" "$SKILL_FILE"; then
  echo "batch calculation must not instruct the agent to improvise inline shell batching" >&2
  exit 1
fi
if grep -q "current_batch_tokens" "$SKILL_FILE" || grep -q "batch_file_counts" "$SKILL_FILE" || grep -q "python3 << 'EOF'" "$SKILL_FILE"; then
  echo "batch calculation must not contain fragile inline shell array/token batching variables" >&2
  exit 1
fi

MODE_PICK_LINE="$(grep -n 'question: "请选择审查模式"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
UPLOAD_PICK_LINE="$(grep -n 'question: "请选择审查报告的保存方式"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
ENTRY_PICK_LINE="$(grep -n 'question: "请选择本次审查入口"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
MODE_SECTION="$(awk '/### 步骤 1：选择审查模式/{flag=1; next} /### 步骤 2：选择审查报告保存方式/{flag=0} flag {print}' "$SKILL_FILE")"
if printf '%s\n' "$MODE_SECTION" | grep -q "RUN_BATCH_COUNT"; then
  echo "review mode selection must be unconditional and cannot depend on RUN_BATCH_COUNT" >&2
  exit 1
fi
require_literal "$SKILL_FILE" "审查模式选择是固定必问步骤" "review mode selection must be documented as always required"
require_literal "$SKILL_FILE" 'label: "fast（仅输出 P0）"' "fast option must state its P0-only output"
require_literal "$SKILL_FILE" '只报告已证实、足以阻断上线的 P0；P1/P2/P3 和待确认项均不输出' "fast option must explain excluded severities"
require_literal "$SKILL_FILE" 'fast（仅输出 P0） → REVIEW_MODE=fast' "fast option response must normalize to the internal fast enum"
require_literal "$SKILL_FILE" 'standard（推荐） → REVIEW_MODE=standard' "standard option response must normalize to the internal standard enum"
require_literal "$SKILL_FILE" 'deep → REVIEW_MODE=deep' "deep option response must normalize to the internal deep enum"
require_literal "$SKILL_FILE" 'security → REVIEW_MODE=security' "security option response must normalize to the internal security enum"
require_literal "$SKILL_FILE" '输出级别：仅 P0  ← 仅 REVIEW_MODE=fast 时显示' "fast execution plan must repeat the conditional P0-only boundary"
require_literal "$EXAMPLES_FILE" 'fast（仅输出 P0）' "scan examples must show the explicit fast label"
require_literal "$ROOT_DIR/README.md" '仅输出 P0' "README mode table must disclose fast output severity"
require_literal "$AGENTS_FILE" 'fast 模式只输出满足全部 P0 硬门槛的问题' "AGENTS must document fast P0-only behavior"
require_literal "$CLAUDE_FILE" 'fast 模式只输出满足全部 P0 硬门槛的问题' "CLAUDE must document fast P0-only behavior"
if [ -z "$MODE_PICK_LINE" ] || [ -z "$UPLOAD_PICK_LINE" ] || [ -z "$ENTRY_PICK_LINE" ] || [ "$MODE_PICK_LINE" -ge "$UPLOAD_PICK_LINE" ] || [ "$UPLOAD_PICK_LINE" -ge "$ENTRY_PICK_LINE" ]; then
  echo "review mode and report handling must be selected before the review entry" >&2
  exit 1
fi
MODEL_PICK_LINE="$(grep -n 'question: "请选择审查使用的模型档位"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$MODEL_PICK_LINE" ]; then
  echo "model selection INTERACT must exist" >&2
  exit 1
fi
# 模型选择已前移到分批之前（第四步之后段），出现在文档的"执行算法"段。
# 断言改为：模型选择必须存在，且文档中必须声明它发生在分批规划之前。
require_match "SKILL 必须声明模型选择在分批之前（时序前提）" "模型选择放在分批之前" "$SKILL_FILE"
grep -q "MODEL_PROFILE" "$SKILL_FILE"
require_literal "$SKILL_FILE" "报告保存方式为多选" "report handling must document multi-select semantics"
require_literal "$SKILL_FILE" "用户可选择本地 Markdown 报告、飞书云文档和飞书多维表格中的任意一个或多个，支持任意组合多选" "dual Feishu upload must be represented by selecting both upload targets"
UPLOAD_MULTISELECT_BLOCK="$(sed -n "${UPLOAD_PICK_LINE},$((UPLOAD_PICK_LINE + 18))p" "$SKILL_FILE")"
if ! printf '%s\n' "$UPLOAD_MULTISELECT_BLOCK" | grep -q -- "- multiSelect: true"; then
  echo "report handling INTERACT must be multi-select" >&2
  exit 1
fi
if grep -q "同时上传两者" "$SKILL_FILE" "$AGENT_FILE" "$FEISHU_FILE" "$EXAMPLES_FILE"; then
  echo "report handling must remove the old combined upload option" >&2
  exit 1
fi

# Skill must have concurrency step
grep -q "选择并发数" "$SKILL_FILE"
grep -q "CONCURRENCY" "$SKILL_FILE"
grep -q "串行执行" "$SKILL_FILE"
grep -q "2 路并发" "$SKILL_FILE"
grep -q "3 路并发" "$SKILL_FILE"
grep -q '默认 `1`' "$SKILL_FILE"
grep -q '1.*2.*3' "$SKILL_FILE"
require_literal "$SKILL_FILE" "并发数必须小于等于本轮实际执行批次数" "concurrency choices must be capped by selected batch count"
require_literal "$SKILL_FILE" "RUN_BATCH_COUNT=1" "single selected batch must force serial concurrency"
require_literal "$SKILL_FILE" "自动设置 `CONCURRENCY=1`" "single selected batch must not ask for concurrency"
require_literal "$SKILL_FILE" "RUN_BATCH_COUNT=2" "two selected batches must hide 3-way concurrency"
if grep -q "5 路并发" "$SKILL_FILE"; then
  echo "batch concurrency options must be 1/2/3, not 1/3/5" >&2
  exit 1
fi

grep -q 'label: "本地 Markdown 报告"' "$SKILL_FILE"
if grep -q 'label: "仅显示报告"' "$SKILL_FILE"; then
  echo "first review result handling option must be local Markdown report, not only chat display" >&2
  exit 1
fi

BATCH_SHOW_LINE="$(grep -n "core/show-batch-status.sh" "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
BATCH_PICK_LINE="$(grep -n 'question: "请选择本轮执行批次"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
CONCURRENCY_LINE="$(grep -n 'question: "请选择并发扫描策略"' "$SKILL_FILE" | head -1 | cut -d: -f1 || true)"
if [ -z "$BATCH_SHOW_LINE" ] || [ -z "$BATCH_PICK_LINE" ] || [ -z "$CONCURRENCY_LINE" ] || [ "$BATCH_SHOW_LINE" -ge "$BATCH_PICK_LINE" ] || [ "$BATCH_PICK_LINE" -ge "$CONCURRENCY_LINE" ]; then
  echo "large repo flow must show batch status, then select execution batches, then select concurrency" >&2
  exit 1
fi
grep -q "普通助手消息" "$SKILL_FILE"
grep -q "| 批次 | 状态 | 行数 | 文件数 | 模块 |" "$EXAMPLES_FILE"
grep -q "|------|------|------:|------:|------|" "$EXAMPLES_FILE"
grep -q "用户可见的 Markdown 表格" "$SKILL_FILE"
require_literal "$ROOT_DIR/scripts/core/show-batch-status.sh" "| 批次 | 状态 | 行数 | 文件数 | 模块 |" "batch status script must render a Markdown batch table"
require_literal "$ROOT_DIR/scripts/core/show-batch-status.sh" "|------|------|------:|------:|------|" "batch status table separator should match user-facing Markdown table style"
require_literal "$SKILL_FILE" "模块列必须使用缩略名展示" "batch module column must abbreviate common engineering prefixes"
require_literal "$SKILL_FILE" "去掉共同前缀" "batch module abbreviation must remove shared prefixes"
require_literal "$SKILL_FILE" "不得只依赖 Bash 工具输出" "batch status must be visible in assistant message, not only collapsed Bash output"
require_literal "$SKILL_FILE" "普通助手消息" "batch status table must be reprinted as normal assistant content"
require_literal "$SKILL_FILE" "不得放入代码块" "batch status table must render like tech-stack table"
if grep -q "批次 状态 行数 成本 文件 模块 原因" "$EXAMPLES_FILE" "$SKILL_FILE"; then
  echo "large repo batch status examples must use Markdown table syntax" >&2
  exit 1
fi
require_literal "$SKILL_FILE" "必须根据本轮可执行批次数动态生成" "batch execution options must be dynamic"
require_literal "$SKILL_FILE" "RUNNABLE_COUNT=1" "single runnable batch must skip batch-selection question"
require_literal "$SKILL_FILE" "不调用 INTERACT" "single runnable batch must not ask for batch selection"
require_literal "$SKILL_FILE" "但描述里又显示" "batch options must not show impossible fixed limits"
require_literal "$ROOT_DIR/scripts/core/show-batch-status.sh" "display_dynamic_plan_rows" "batch status script must render dynamic execution plans"
require_literal "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" 'RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"' "large planner run dir must be timestamp-branch-mode only"
require_literal "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh" 'RUN_ID="$RUN_TIMESTAMP-$(branch_slug "$BRANCH_NAME")-$REVIEW_MODE"' "file planner run dir must be timestamp-branch-mode only"
require_literal "$SKILL_FILE" '`RUN_DIR` 目录名固定为 `{YYYYMMDD-HHMMSS}-{branch_slug}-{REVIEW_MODE}`' "skill contract must document concise run directory naming"
require_literal "$SKILL_FILE" '审查范围、分批策略和任务类型必须从 `plan.json` 读取' "scope and strategy must live in plan.json instead of run dir name"
if grep -q 'RUN_ID=.*large-maven\|RUN_ID=.*file-batches\|RUN_SCOPE_SLUG\|RUN_STRATEGY_SLUG' "$ROOT_DIR/scripts/languages/java/plan-large-batches.sh" "$ROOT_DIR/scripts/languages/java/plan-file-batches.sh"; then
  echo "run directory name must not include scope, strategy, or batch-type suffixes" >&2
  exit 1
fi
grep -q "自行输入批次号" "$SKILL_FILE"
grep -q "BATCH_SELECTION" "$SKILL_FILE"
grep -q "RUN_BATCH_IDS" "$SKILL_FILE"
grep -q "RUN_BATCH_COUNT" "$SKILL_FILE"
if grep -q '分批并行扫描（{BATCH_COUNT} 批 / {CONCURRENCY} 路并发）' "$SKILL_FILE"; then
  echo "large repo execution copy must distinguish current-run batch count from total batch count" >&2
  exit 1
fi

# Skill must have batch agent orchestration
grep -q "分批并行模式" "$SKILL_FILE"
grep -q "BATCH_FILE_COUNT" "$SKILL_FILE"
grep -q "BATCH_LINE_COUNT" "$SKILL_FILE"
grep -q "飞书保存不可用" "$SKILL_FILE"

# Skill must have report merging
grep -q "报告合并" "$SKILL_FILE"
grep -q "跨批去重" "$SKILL_FILE"
grep -q "聚合同类问题" "$SKILL_FILE"

# Skill batch mode only for stock review
grep -q "仅对存量审查生效" "$SKILL_FILE"

# Skill must show batch info in step 7 execution plan
grep -q "扫描策略" "$SKILL_FILE"
grep -q "分批并行扫描" "$SKILL_FILE"

# === AGENTS.md / CLAUDE.md 同步守卫 ===
# 这两个文件服务不同工具（Codex / Claude Code），除以下两处预期差异外，正文必须逐行一致，
# 防止架构描述在两份拷贝间漂移：
#   - 第 1 行：标题（# AGENTS.md / # CLAUDE.md）
#   - 第 3 行：首句工具引导语（含工具名和域名，Codex.ai/code vs claude.ai/code）
# 第 7 行的 "claudecode" vs "Claude Code" 通过归一化为同一写法后参与比较。
sync_normalize() {
  local file="$1"
  perl -CS -Mutf8 -ne '
    next if $. == 1 || $. == 3;          # 跳过第 1 行标题、第 3 行首句工具引导语
    s/\bclaudecode\b/Claude Code/g;       # 统一第 7 行的工具名写法
    print;
  ' "$file"
}

SYNC_DIFF="$(diff <(sync_normalize "$AGENTS_FILE") <(sync_normalize "$CLAUDE_FILE") || true)"
if [ -n "$SYNC_DIFF" ]; then
  echo "AGENTS.md 与 CLAUDE.md 正文不同步（标题行与首句工具引导语的差异已排除）。请同步两文件后再次运行。" >&2
  echo "差异如下：" >&2
  echo "$SYNC_DIFF" >&2
  echo "提示：修改时请同时编辑 AGENTS.md 和 CLAUDE.md；仅第 1 行标题和第 3 行首句允许不同。" >&2
  exit 1
fi

# === 前端多语言文档同步断言 ===
for f in \
  "scripts/core/detect-language.sh" \
  "scripts/core/validate-scope.sh" \
  "scripts/core/plan-file-batches.sh" \
  "scripts/core/merge-batch-results.sh" \
  "scripts/core/show-batch-status.sh" \
  "scripts/languages/frontend/detect-project.sh" \
  "scripts/languages/frontend/scan-project.sh" \
  "scripts/languages/frontend/collect-source-files.sh" \
  "scripts/languages/frontend/detect-code-intelligence.sh" \
  "scripts/languages/python/detect-project.sh" \
  "scripts/languages/python/scan-project.sh" \
  "scripts/languages/python/collect-source-files.sh" \
  "scripts/languages/python/filter-source-manifest.sh" \
  "scripts/languages/python/detect-code-intelligence.sh" \
  "agents/cc-code-reviewer-frontend.md" \
  "agents/cc-code-reviewer-python.md" \
  "references/language-adapter-contract.md" \
  "references/languages/java/review-framework.md" \
  "references/languages/frontend/source-scope.md" \
  "references/languages/frontend/review-framework.md" \
  "references/languages/frontend/react-rules.md" \
  "references/languages/frontend/vue-rules.md" \
  "references/languages/frontend/node-rules.md" \
  "references/languages/python/source-scope.md" \
  "references/languages/python/review-framework.md" \
  "references/languages/python/django-rules.md" \
  "references/languages/python/fastapi-rules.md"; do
  [ -f "$ROOT_DIR/$f" ] || { echo "MISSING: $f" >&2; exit 1; }
done

if find "$ROOT_DIR/scripts" -maxdepth 1 -type f -name 'phase*.sh' -print -quit | grep -q .; then
  echo "legacy phase wrappers must be removed from scripts/ root" >&2
  exit 1
fi
if grep -qE "phaseN-\*\.sh|Legacy paths|compat forwarding wrappers|兼容转发 wrapper" "$AGENTS_FILE" "$CLAUDE_FILE" "$SKILL_FILE" "$FIX_SKILL_FILE"; then
  echo "active docs must not advertise legacy phase wrappers" >&2
  exit 1
fi

require_literal "$ROOT_DIR/.gitignore" ".superpowers/" "local Superpowers work artifacts must be ignored"

# shared-review-framework.md 必须已删除（过度设计，不再维护公共维度分类法）
if [ -f "$ROOT_DIR/references/shared-review-framework.md" ]; then
  echo "FAIL: shared-review-framework.md 应已删除，审查框架各语言独立" >&2
  exit 1
fi

# 前端审查框架必须使用独立维度集，不得引用 Java 公共维度 ID（D01_CORRECTNESS 等）
FE_FRAMEWORK="$ROOT_DIR/references/languages/frontend/review-framework.md"
if grep -qE 'D(0[1-9]|1[0-5])_[A-Z_]+' "$FE_FRAMEWORK"; then
  echo "FAIL: 前端框架不得引用 Java 公共维度 ID" >&2
  exit 1
fi
# 正向断言：必须包含类型安全维度（中后台 P0 级）
grep -q "类型安全" "$FE_FRAMEWORK" || { echo "FAIL: 前端框架必须包含类型安全维度" >&2; exit 1; }
# 正向断言：必须声明 12 维度（维度 12 设计系统一致性仅 deep；硬断言，防止随意膨胀）
FE_DIM_COUNT=$(grep -cE '^### [0-9]+\. ' "$FE_FRAMEWORK")
if [ "$FE_DIM_COUNT" -ne 12 ]; then
  echo "FAIL: 前端框架必须声明 12 维度，当前 $FE_DIM_COUNT" >&2
  exit 1
fi
# 维度 12「设计系统一致性」只能在 deep 列启用，其余三列必须为 —（防止误开放到 standard/fast/security）
grep -q '^| 12 设计系统一致性 | — | — | ✅ | — |' "$FE_FRAMEWORK" \
  || { echo "FAIL: 维度 12 设计系统一致性必须仅在 deep 启用（fast/standard/security 为 —）" >&2; exit 1; }

# SKILL.md 必须含语言路由分支
grep -q "语言探测与路由" "$SKILL_FILE"
grep -q "CANDIDATE_LANGUAGE:frontend" "$SKILL_FILE"
grep -q "cc-code-reviewer-frontend" "$SKILL_FILE"
# 前端 agent 必须被实际 dispatch（agent_prompt 按 LANGUAGE_ID 选择，不能只硬编码 Java agent）
grep -q 'agents/cc-code-reviewer-frontend.md' "$SKILL_FILE"
# 前端 agent 在 dispatch 点必须按 LANGUAGE_ID 条件化（至少出现 2 次）
FRONTEND_DISPATCH_COUNT="$(grep -c 'agents/cc-code-reviewer-frontend.md' "$SKILL_FILE")"
test "$FRONTEND_DISPATCH_COUNT" -ge 2

# SKILL.md 路径准备必须按 LANGUAGE_ID 分支，前端注入三个专属路径（不能写死 Java 路径）
grep -q 'LANGUAGE_ID.*frontend' "$SKILL_FILE"
grep -q 'REACT_RULES_PATH' "$SKILL_FILE"
grep -q 'VUE_RULES_PATH' "$SKILL_FILE"
grep -q 'NODE_RULES_PATH' "$SKILL_FILE"
grep -q 'SOURCE_SCOPE_PATH' "$SKILL_FILE"
grep -q 'references/languages/frontend/review-framework.md' "$SKILL_FILE"
grep -q 'references/languages/frontend/react-rules.md' "$SKILL_FILE"
grep -q 'references/languages/frontend/vue-rules.md' "$SKILL_FILE"
grep -q 'references/languages/frontend/node-rules.md' "$SKILL_FILE"
grep -q 'references/languages/frontend/source-scope.md' "$SKILL_FILE"

# 前端 agent 必须期望前端专属路径（不能只依赖 Java 的 REVIEW_FRAMEWORK_PATH）
grep -q "前端审查框架路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "React 规则路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "Vue 规则路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "Node 规则路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "源码范围路径" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"

# Vue 检测信号契约：detect-project.sh 必须识别 Vue 专属依赖与内容信号（防止 Vue 项目被拒或误判 React）
FE_DETECT="$ROOT_DIR/scripts/languages/frontend/detect-project.sh"
grep -q '@vue/cli-service' "$FE_DETECT" || { echo "FAIL: detect-project 必须识别 @vue/cli-service（Vue2 CLI 权威信号）" >&2; exit 1; }
grep -q 'vite-plugin-vue2' "$FE_DETECT" || { echo "FAIL: detect-project 必须识别 vite-plugin-vue2" >&2; exit 1; }
grep -qE 'createApp|defineComponent|defineAsyncComponent' "$FE_DETECT" || { echo "FAIL: detect-project 必须含 Vue3 内容信号回退" >&2; exit 1; }
grep -qE 'new Vue|Vue\.extend|Vue\.component' "$FE_DETECT" || { echo "FAIL: detect-project 必须含 Vue2 内容信号回退" >&2; exit 1; }
# collect-source-files.sh 必须复用 detect-project.sh 的 Vue 信号（避免源码根闸门漂移导致 Vue3 hoisted 清单为空）
FE_COLLECT="$ROOT_DIR/scripts/languages/frontend/collect-source-files.sh"
grep -q 'FE_DETECT_SOURCED=1' "$FE_COLLECT" || { echo "FAIL: collect-source-files 必须 source detect-project.sh 复用 Vue 信号" >&2; exit 1; }
# Vue 规则细则必须覆盖高价值缺口（provide/inject 响应性、script setup 顶层 await、history base、动态路由时序）
FE_VUE_RULES="$ROOT_DIR/references/languages/frontend/vue-rules.md"
grep -q 'provide/inject' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 provide/inject 响应性" >&2; exit 1; }
grep -q '顶层 await' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 script setup 顶层 await" >&2; exit 1; }
grep -q 'base 路径' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 Router 4 history base 路径" >&2; exit 1; }
grep -q '动态路由权限时序' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖动态路由权限时序" >&2; exit 1; }
grep -q 'mixin 全局污染' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 Vue2 mixin 全局污染" >&2; exit 1; }
grep -q 'keep-alive' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 keep-alive activated/deactivated" >&2; exit 1; }
grep -q 'vue-class-component' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 Vue2 class component/decorator" >&2; exit 1; }
grep -q '\.sync' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 Vue2 .sync 双向绑定风险" >&2; exit 1; }
grep -q '\$children/\$parent' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 $children/$parent 旧式跨层访问" >&2; exit 1; }
grep -q '\$refs/\$nextTick' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 $refs/$nextTick DOM 时序" >&2; exit 1; }
grep -q 'Element UI' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 Element UI 表单表格场景" >&2; exit 1; }
grep -q '权限按钮' "$FE_VUE_RULES" || { echo "FAIL: vue-rules 必须覆盖 B 端权限按钮/路由 meta 场景" >&2; exit 1; }

# 前端 agent 不得残留旧 15 维度编号（D01-D15）或越界维度 13-15 引用（维度 12 设计系统一致性已合法）
if grep -qE 'D(0[1-9]|1[0-5])[^0-9]|维度 ?1[345]|1-1[345]|1[345] 维度' "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"; then
  echo "FAIL: 前端 agent 残留旧 15 维度编号或越界维度 13-15 引用" >&2
  exit 1
fi

# 前端矩阵与 React 规则必须被前端 Agent 引用
grep -q "review-framework" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "react-rules" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "vue-rules" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"
grep -q "node-rules" "$ROOT_DIR/agents/cc-code-reviewer-frontend.md"

# === Python 审查契约断言 ===
PY_FRAMEWORK="$ROOT_DIR/references/languages/python/review-framework.md"
PY_AGENT_FILE="$ROOT_DIR/agents/cc-code-reviewer-python.md"
# Python 框架不得引用 Java 公共维度 ID
if grep -qE 'D(0[1-9]|1[0-5])_[A-Z_]+' "$PY_FRAMEWORK"; then
  echo "FAIL: Python 框架不得引用 Java 公共维度 ID" >&2
  exit 1
fi
# Python 框架必须包含类型安全维度
grep -q "类型安全" "$PY_FRAMEWORK" || { echo "FAIL: Python 框架必须包含类型安全维度" >&2; exit 1; }
# Python 框架必须声明 12 维度
PY_DIM_COUNT=$(grep -cE '^### [0-9]+\. ' "$PY_FRAMEWORK")
if [ "$PY_DIM_COUNT" -ne 12 ]; then
  echo "FAIL: Python 框架必须声明 12 维度，当前 $PY_DIM_COUNT" >&2
  exit 1
fi
# Python 框架必须含 P0 五项硬门槛
grep -q "P0 五项硬门槛" "$PY_FRAMEWORK" || { echo "FAIL: Python 框架必须含 P0 五项硬门槛" >&2; exit 1; }
# Python 框架必须含依赖风险结论规则
grep -q "依赖风险结论规则" "$PY_FRAMEWORK" || { echo "FAIL: Python 框架必须含依赖风险结论规则" >&2; exit 1; }
# SKILL.md 必须含 Python 路由
grep -q "CANDIDATE_LANGUAGE:python" "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 CANDIDATE_LANGUAGE:python" >&2; exit 1; }
grep -q "cc-code-reviewer-python" "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须引用 cc-code-reviewer-python" >&2; exit 1; }
grep -q "agents/cc-code-reviewer-python.md" "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 python agent_prompt dispatch" >&2; exit 1; }
# dispatch 点至少出现 2 次
PYTHON_DISPATCH_COUNT="$(grep -c 'agents/cc-code-reviewer-python.md' "$SKILL_FILE")"
test "$PYTHON_DISPATCH_COUNT" -ge 2 || { echo "FAIL: python dispatch 必须 >=2 次，当前 $PYTHON_DISPATCH_COUNT" >&2; exit 1; }
# SKILL.md 路径准备必须按 LANGUAGE_ID 分支，Python 注入专属路径
grep -q 'LANGUAGE_ID.*python' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 LANGUAGE_ID python 分支" >&2; exit 1; }
grep -q 'DJANGO_RULES_PATH' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 DJANGO_RULES_PATH" >&2; exit 1; }
grep -q 'FASTAPI_RULES_PATH' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 FASTAPI_RULES_PATH" >&2; exit 1; }
grep -q 'references/languages/python/review-framework.md' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须引用 python review-framework" >&2; exit 1; }
# Python agent 必须期望 Python 框架路径和 Django/FastAPI 规则路径
grep -q "review-framework" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须引用 review-framework" >&2; exit 1; }
grep -q "django-rules" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须引用 django-rules" >&2; exit 1; }
grep -q "fastapi-rules" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须引用 fastapi-rules" >&2; exit 1; }
grep -q "source-scope" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须引用 source-scope" >&2; exit 1; }
# Python agent 必须含 source manifest / BATCH_FILE_LIST / BATCH_PLAN_PATH 参数（与前端 agent 对齐）
grep -q "source manifest" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须含 source manifest 参数" >&2; exit 1; }
grep -q "BATCH_FILE_LIST" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须含 BATCH_FILE_LIST 参数" >&2; exit 1; }
grep -q "BATCH_PLAN_PATH" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须含 BATCH_PLAN_PATH 参数" >&2; exit 1; }
# SKILL.md 必须含 source manifest 注入（单 agent 路径 A，仅 frontend/python）
grep -q "source manifest" "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 source manifest 注入说明" >&2; exit 1; }
# SKILL.md 必须含文件级分批模式与 Maven 大仓库模式的边界区分
grep -q "文件级分批模式" "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须区分文件级分批模式" >&2; exit 1; }
grep -q "Maven 大仓库模式" "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须区分 Maven 大仓库模式" >&2; exit 1; }
# Python scan-project.sh 必须区分可正式发现的配置与只读上下文
grep -q "FORMAL_CONFIG_FILE:" "$ROOT_DIR/scripts/languages/python/scan-project.sh" || { echo "FAIL: Python scan-project.sh 必须含 FORMAL_CONFIG_FILE 输出" >&2; exit 1; }
grep -q "FORMAL_CONFIG_FILE:" "$ROOT_DIR/scripts/languages/frontend/scan-project.sh" || { echo "FAIL: frontend scan-project.sh 必须含 FORMAL_CONFIG_FILE 输出" >&2; exit 1; }
grep -q 'batch-001.*FORMAL_CONFIG_FILE' "$FRONTEND_AGENT_FILE" || { echo "FAIL: frontend agent 必须限定 batch-001 唯一审查正式配置" >&2; exit 1; }
grep -q "CONTEXT_ROOT" "$ROOT_DIR/scripts/languages/python/scan-project.sh" || { echo "FAIL: Python scan-project.sh 必须含 CONTEXT_ROOT 输出" >&2; exit 1; }
grep -q "FORMAL_CONFIG_FILE:" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须允许显式正式配置产生发现" >&2; exit 1; }
if grep -q 'FORMAL_CONFIG_FILE.*不得作为正式问题位置' "$PY_AGENT_FILE"; then
  echo "FAIL: Python agent 不得把 FORMAL_CONFIG_FILE 降级为只读上下文" >&2
  exit 1
fi
# Python 必须具备指定包目录流程，且 Python/前端文件级分批不得落入 Java planner。
grep -q '指定模块 + Python' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 Python 指定包目录流程" >&2; exit 1; }
grep -q 'LANGUAGE_ID=python.*BATCH_MODE=true' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须含 Python core file-batch planner 分支" >&2; exit 1; }
grep -q '仅当 `LANGUAGE_ID=java`、`PROJECT_TYPE` 不是 Maven 多模块' "$SKILL_FILE" || { echo "FAIL: Java file-batch planner 必须显式限定 LANGUAGE_ID=java" >&2; exit 1; }
# 单 agent manifest 仅收敛存量目录；增量审查不得误用提交范围字符串过滤 manifest。
grep -Fq 'if [ "$REVIEW_TYPE" = "存量审查" ] && [ "${REVIEW_SCOPE:-全量代码}" != "全量代码" ]; then' "$SKILL_FILE" || { echo "FAIL: 单 agent manifest 过滤必须限定存量审查" >&2; exit 1; }
# 文件级分批必须从当前 BATCH_ID 派生真实清单路径，不能只注入占位符。
grep -Fq 'BATCH_FILE_LIST="$RUN_DIR/batches/$BATCH_ID.files"' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须显式派生 BATCH_FILE_LIST" >&2; exit 1; }
grep -q 'NO_${LANGUAGE_ID}_SOURCE_FILES_IN_SCOPE' "$SKILL_FILE" || { echo "FAIL: 指定范围过滤为空时必须阻断" >&2; exit 1; }
# 三类 agent 都必须按 batch plan 内容分流，并落同一 results/status 契约。
grep -q 'strategy=file-token-batching' "$AGENT_FILE" || { echo "FAIL: Java agent 必须识别 file-token-batching 计划" >&2; exit 1; }
grep -q '不得仅凭路径参数存在就假定为 Maven 大仓库模式' "$AGENT_FILE" || { echo "FAIL: Java agent 不得把所有 BATCH_PLAN_PATH 当成 Maven 大仓库" >&2; exit 1; }
grep -q 'strategy=file-token-batching' "$FRONTEND_AGENT_FILE" || { echo "FAIL: 前端 agent 必须识别 file-token-batching 计划" >&2; exit 1; }
grep -q 'BATCH_FILE_LIST.*不得查找 `scan_roots`' "$FRONTEND_AGENT_FILE" || { echo "FAIL: 前端文件批次必须使用 BATCH_FILE_LIST" >&2; exit 1; }
grep -q 'strategy=file-token-batching' "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须识别 file-token-batching 计划" >&2; exit 1; }
for batch_agent in "$AGENT_FILE" "$FRONTEND_AGENT_FILE" "$PY_AGENT_FILE"; do
  grep -q 'BATCH_RESULT_PATH' "$batch_agent" || { echo "FAIL: batch agent 缺 BATCH_RESULT_PATH: $batch_agent" >&2; exit 1; }
  grep -q 'BATCH_STATUS_PATH' "$batch_agent" || { echo "FAIL: batch agent 缺 BATCH_STATUS_PATH: $batch_agent" >&2; exit 1; }
done
# Python CLI 与 LSP provider 必须分离，防止上层宣称不存在的 definition/references 能力。
grep -q 'CODE_INTELLIGENCE_PROVIDER=pyright-cli' "$ROOT_DIR/scripts/languages/python/detect-code-intelligence.sh" || { echo "FAIL: pyright CLI 必须使用独立 provider" >&2; exit 1; }
grep -q 'SEMANTIC_LEVEL=pyright-cli' "$SKILL_FILE" || { echo "FAIL: SKILL.md 必须声明 pyright-cli 仅 diagnostics 语义" >&2; exit 1; }
# Bash fenced block 中禁止 Unicode 智能引号；它们会成为路径/参数的一部分。
if awk '/^```bash[[:space:]]*$/ { in_bash=1; next } /^```/ { in_bash=0 } in_bash { print }' "$SKILL_FILE" | grep -q '[“”]'; then
  echo "FAIL: SKILL.md Bash 代码块包含 Unicode 智能引号" >&2
  exit 1
fi
# Python agent 不得残留旧 15 维度编号或越界维度 13-15 引用
if grep -qE 'D(0[1-9]|1[0-5])[^0-9]|维度 ?1[345]|1-1[345]|1[345] 维度' "$PY_AGENT_FILE"; then
  echo "FAIL: Python agent 残留旧 15 维度编号或越界维度 13-15 引用" >&2
  exit 1
fi
# Python 框架和 agent 必须含性能分级边界（已在上方循环断言，此处补 P0 门槛）
grep -q "P0 五项硬门槛" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须含 P0 五项硬门槛" >&2; exit 1; }
# Python agent 必须含 Batch 发现清单输出格式段（对齐 Java/前端 agent）
PY_BATCH_P0_TEMPLATE="$(awk '
  /^## Batch 发现清单输出格式$/ { in_batch_format = 1; next }
  in_batch_format && /^### P0 \|/ { in_p0_template = 1 }
  in_p0_template && /^### P[1-3] \|/ { exit }
  in_p0_template { print }
' "$PY_AGENT_FILE")"
if [ -z "$PY_BATCH_P0_TEMPLATE" ]; then
  echo "FAIL: Python agent 必须含 Batch 发现清单输出格式段及 P0 模板" >&2
  exit 1
fi
for py_batch_p0_field in \
  "置信度：高" \
  "生产可达路径：" \
  "事故级影响：" \
  "有效防护核查：" \
  "阻断发布理由："; do
  if ! printf '%s\n' "$PY_BATCH_P0_TEMPLATE" | grep -Fq -- "$py_batch_p0_field"; then
    echo "FAIL: Python agent Batch P0 模板必须含字段: $py_batch_p0_field" >&2
    exit 1
  fi
done
grep -q "review-batch-" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须含 review-batch- 历史回退路径" >&2; exit 1; }
grep -q "BATCH_INDEX" "$PY_AGENT_FILE" || { echo "FAIL: Python agent 必须含 BATCH_INDEX 汇总" >&2; exit 1; }
# django-rules 必须覆盖关键检查点
grep -q "on_delete" "$ROOT_DIR/references/languages/python/django-rules.md" || { echo "FAIL: django-rules 必须覆盖 on_delete" >&2; exit 1; }
grep -q "mark_safe" "$ROOT_DIR/references/languages/python/django-rules.md" || { echo "FAIL: django-rules 必须覆盖 mark_safe XSS" >&2; exit 1; }
grep -q "select_related" "$ROOT_DIR/references/languages/python/django-rules.md" || { echo "FAIL: django-rules 必须覆盖 select_related N+1" >&2; exit 1; }
grep -q "DEBUG" "$ROOT_DIR/references/languages/python/django-rules.md" || { echo "FAIL: django-rules 必须覆盖 DEBUG 配置" >&2; exit 1; }
# P2-4: django-rules 不得直接标注"P0 级"（P0 须通过五项硬门槛核验，由门槛决定级别）
if grep -q 'P0 级' "$ROOT_DIR/references/languages/python/django-rules.md"; then
  echo "FAIL: django-rules 不得直接标注 P0 级（须改为 P0 候选）" >&2
  exit 1
fi
# fastapi-rules 必须覆盖关键检查点
grep -q "Depends" "$ROOT_DIR/references/languages/python/fastapi-rules.md" || { echo "FAIL: fastapi-rules 必须覆盖 Depends" >&2; exit 1; }
grep -q "Pydantic" "$ROOT_DIR/references/languages/python/fastapi-rules.md" || { echo "FAIL: fastapi-rules 必须覆盖 Pydantic" >&2; exit 1; }
grep -q "async def" "$ROOT_DIR/references/languages/python/fastapi-rules.md" || { echo "FAIL: fastapi-rules 必须覆盖 async def 阻塞" >&2; exit 1; }
grep -q "OpenAPI" "$ROOT_DIR/references/languages/python/fastapi-rules.md" || { echo "FAIL: fastapi-rules 必须覆盖 OpenAPI" >&2; exit 1; }
# detect-language 必须能输出 python 候选
grep -q "has_python" "$ROOT_DIR/scripts/core/detect-language.sh" || { echo "FAIL: detect-language 必须含 has_python" >&2; exit 1; }
grep -q "emit python" "$ROOT_DIR/scripts/core/detect-language.sh" || { echo "FAIL: detect-language 必须含 emit python" >&2; exit 1; }
# core merge/status 必须含 python 标签分支
grep -q 'python)   COVERAGE_LABEL="Python 文件覆盖率"' "$ROOT_DIR/scripts/core/merge-batch-results.sh" || { echo "FAIL: merge-batch-results 必须含 python 覆盖率标签" >&2; exit 1; }
grep -q 'python)   LOC_LABEL="Python 行数"' "$ROOT_DIR/scripts/core/show-batch-status.sh" || { echo "FAIL: show-batch-status 必须含 python 标签" >&2; exit 1; }
# Python 框架版本页脚
grep -q 'Python 1.1' "$PY_FRAMEWORK" || { echo "FAIL: Python 框架必须标注版本 Python 1.1" >&2; exit 1; }

# Java / 前端框架版本页脚
grep -q '本手册版本：5.7' "$ROOT_DIR/references/languages/java/review-framework.md" || { echo "FAIL: Java 框架必须标注版本 5.7" >&2; exit 1; }
grep -q '本手册版本：前端 2.5' "$FE_FRAMEWORK" || { echo "FAIL: 前端框架必须标注版本 前端 2.5" >&2; exit 1; }

# 安全设计审查必须由模型基于关联代码推理不变量；脚本只提供结构上下文，
# 不得把方法名/字段名词表伪装成 Default Deny 识别能力。
require_literal "$SKILL_FILE" "scripts/core/prepare-review-context.sh" "单 agent 必须从冻结输入生成关联审查单元"
require_literal "$SKILL_FILE" "REVIEW_UNITS_PATH" "主 Skill 必须向审查 agent 注入关联审查单元"
for invariant_agent in "$AGENT_FILE" "$FRONTEND_AGENT_FILE" "$PY_AGENT_FILE"; do
  require_literal "$invariant_agent" "安全设计不变量" "agent 必须执行与命名无关的安全设计不变量推理"
  require_literal "$invariant_agent" "受保护动作" "agent 必须先识别受保护动作"
  require_literal "$invariant_agent" "未获得明确授权证据" "agent 必须主动寻找未授权到达受保护动作的反例路径"
  require_literal "$invariant_agent" "安全契约检查点" "agent 必须逐关联单元记录安全不变量复核结论"
done
if grep -Eq 'match[[:space:]]*/[[:space:]]*shouldFilter[[:space:]]*/[[:space:]]*allow' "$ROOT_DIR/references/languages/java/review-framework.md"; then
  echo "FAIL: Java Default Deny 识别不得依赖预置方法名清单" >&2
  exit 1
fi
if grep -Eq '信号A.*\((match|allow|permit|check|verify|has\*|can\*|skip)' "$AGENT_FILE" "$FRONTEND_AGENT_FILE" "$PY_AGENT_FILE"; then
  echo "FAIL: 跨文件安全信号不得使用方法名词表定义语义" >&2
  exit 1
fi

# LICENSE 契约：仓库声明 MIT 的三端 manifest 必须有对应 LICENSE 文件
if [ ! -f "$ROOT_DIR/LICENSE" ]; then
  echo "FAIL: 三端 manifest 声明 MIT 但缺少 LICENSE 文件" >&2
  exit 1
fi
grep -q "MIT License" "$ROOT_DIR/LICENSE" || { echo "FAIL: LICENSE 必须是标准 MIT 文本" >&2; exit 1; }

# 报告版本必须与 Java 框架版本同步（1.6.1 起的同步惯例，防止再次脱钩）
JAVA_FW_VERSION="$(sed -n 's/.*本手册版本：\([0-9][0-9.]*\)\*.*/\1/p' "$ROOT_DIR/references/languages/java/review-framework.md" | head -1)"
REPORT_VERSION="$(sed -n 's/^\*\*报告版本\*\*: \([0-9][0-9.]*\)/\1/p' "$REPORT_FORMAT_FILE" | head -1)"
if [ -z "$JAVA_FW_VERSION" ] || [ "$JAVA_FW_VERSION" != "$REPORT_VERSION" ]; then
  echo "FAIL: report-format 报告版本($REPORT_VERSION) 必须与 Java 框架版本($JAVA_FW_VERSION) 同步" >&2
  exit 1
fi

# === 脚本目录重构断言 ===
# SKILL.md 必须含「脚本调用顺序」编排段（执行顺序归文档，不编码进文件名）
grep -q "脚本调用顺序" "$SKILL_FILE" || { echo "FAIL: cc-code-reviewer SKILL.md 缺「脚本调用顺序」段" >&2; exit 1; }
grep -q "脚本调用顺序" "$ROOT_DIR/skills/cc-code-fixer/SKILL.md" || { echo "FAIL: cc-code-fixer SKILL.md 缺「脚本调用顺序」段" >&2; exit 1; }
# 防回退：文档应引用新路径（core/ 或 languages/java/），证明迁移发生
grep -q "scripts/core/detect-project.sh" "$SKILL_FILE" || { echo "FAIL: SKILL.md 应引用 core/detect-project.sh" >&2; exit 1; }
grep -q "scripts/languages/java/project-scan.sh" "$SKILL_FILE" || { echo "FAIL: SKILL.md 应引用 languages/java/project-scan.sh" >&2; exit 1; }

# === v1.6.6: 增量重复抑制 / 业务背景注入 / SARIF 导出 ===
# SKILL 必须接线两个新脚本的实际调用行（单 agent 与批次路径共用同一命令形态）。
require_match "SKILL 必须接线增量上轮已报标记脚本调用行" 'core/mark-repeat-findings\.sh" "\$REPORT_PATH" "\$REPEAT_PREV_REPORT_PATH"' "$SKILL_FILE"
require_match "SKILL 必须接线 SARIF 导出脚本调用行" 'core/export-sarif\.sh" "\$REPORT_PATH".*\.sarif.*--project-name "\$PROJECT_NAME"' "$SKILL_FILE"
# SKILL 必须采集并注入业务背景，且声明 8000 字符硬上限。
require_literal "$SKILL_FILE" "REVIEW_BACKGROUND" "skill must collect and inject REVIEW_BACKGROUND"
require_literal "$SKILL_FILE" "8000" "skill must document the 8000-character background cap"
# 报告格式必须披露上轮已报标记语义。
require_literal "$REPORT_FORMAT_FILE" "（上轮已报）" "report format must document the repeat-finding marker"
# README 必须出现 SARIF 特性关键词。
require_literal "$ROOT_DIR/README.md" "SARIF" "README must surface the SARIF export feature keyword"
# AGENTS / CLAUDE 必须同步两个新脚本的契约描述。
require_match "AGENTS/CLAUDE 必须描述增量上轮已报标记脚本" 'mark-repeat-findings\.sh' "$AGENTS_FILE" "$CLAUDE_FILE"
require_match "AGENTS/CLAUDE 必须描述 SARIF 导出脚本" 'export-sarif\.sh' "$AGENTS_FILE" "$CLAUDE_FILE"

echo "✅ 契约文档测试通过"
