# Tighten P0 Severity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Completed steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 收紧 P0 为证据充分、生产可达且必须阻断发布的事故级问题，同时在非 fast 模式中把未通过 P0 门槛的候选完整下移，并让 fast 交互明确提示“仅输出 P0”。

**Architecture:** 不新增运行时代码或状态，只修改扫描 prompt、参考规范、交互文案和契约测试。分级采用确定的三路决策：满足全部硬门槛进入 P0；问题成立但影响不足进入 P1；事故级风险尚缺关键证据进入待确认。fast 保持纯 P0，其他级别不输出。

**Tech Stack:** Markdown skill/agent prompts、Bash contract tests、`grep`/`require_literal` 文档契约断言。

## Global Constraints

- P0 必须同时满足生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。
- 任一 P0 条件不满足都不得标为 P0；中、低置信度绝不进入 P0。
- 非 fast 模式中，证据成立但影响不足的候选下移 P1，关键证据不足的高风险候选进入待确认，不得静默丢弃。
- fast 保持纯 P0，不输出 P1、P2、P3 或待确认项。
- AskUserQuestion 的 fast 选项和最终执行计划都必须直观展示“仅输出 P0”。
- 不修改批次规划、跨轮基线、问题指纹、fixer 范围或报告存储结构。
- `AGENTS.md` 与 `CLAUDE.md` 必须保持内容一致。

## File Map

- `tests/test_contract_docs.sh`：锁定 P0 硬门槛、降级完整性、fast 交互文案和执行计划提示。
- `agents/cc-code-reviewer.md`：扫描代理实际执行的 P0 判定门槛、降级规则和典型边界。
- `references/review-framework.md`：模式矩阵使用的统一分级原则和 fast 纯 P0 语义。
- `references/report-format.md`：P0 报告证据必须呈现的生产路径、事故后果和防护状态。
- `skills/cc-code-reviewer/SKILL.md`：AskUserQuestion fast 选项以及执行计划的输出级别提示。
- `references/examples.md`：同步所有用户可见的 fast 选项示例和 fast 执行计划示例。
- `README.md`：模式概览直观说明 fast 只输出 P0。
- `AGENTS.md`、`CLAUDE.md`：同步记录 fast 交互提示与 P0 分级迁移契约。

---

### Task 1: Lock and implement the strict P0 classification contract

**Files:**
- Modify: `tests/test_contract_docs.sh`
- Modify: `agents/cc-code-reviewer.md`
- Modify: `references/review-framework.md`
- Modify: `references/report-format.md`

**Interfaces:**
- Consumes: `REVIEW_MODE` and the existing P0/P1/P2/P3/待确认 report taxonomy.
- Produces: a prompt-level five-gate P0 decision and deterministic downgrade destinations used by every scan mode.

- [x] **Step 1: Add failing contract assertions**

Append the following assertions near the existing reviewer-agent contract checks in `tests/test_contract_docs.sh`:

```bash
require_literal "$AGENT_FILE" "P0 五项硬门槛（必须全部满足）" "review agent must define all mandatory P0 gates"
require_literal "$AGENT_FILE" "生产可达" "P0 must require a production-reachable path"
require_literal "$AGENT_FILE" "置信度必须为高" "P0 must require high confidence"
require_literal "$AGENT_FILE" "事故级影响" "P0 must require incident-level impact"
require_literal "$AGENT_FILE" "缺少有效防护" "P0 must account for effective mitigations"
require_literal "$AGENT_FILE" "阻断发布" "P0 must be release-blocking"
require_literal "$AGENT_FILE" "证据成立但影响未达到事故级" "confirmed non-P0 findings must downgrade to P1"
require_literal "$AGENT_FILE" "归入待确认" "unproven high-risk findings must move to pending confirmation"
require_literal "$AGENT_FILE" "不得因为未通过 P0 门槛而静默丢弃" "non-fast modes must preserve downgraded findings"
require_literal "$ROOT_DIR/references/review-framework.md" "P0 五项硬门槛" "review framework must share the strict P0 contract"
require_literal "$ROOT_DIR/references/report-format.md" "P0 证据门槛" "report format must require P0 gate evidence"
```

- [x] **Step 2: Run the contract test and verify RED**

Run: `bash tests/test_contract_docs.sh`

Expected: FAIL with `review agent must define all mandatory P0 gates` because the new contract text is absent.

- [x] **Step 3: Replace the loose P0 definition in the review agent**

In `agents/cc-code-reviewer.md`, replace the current P0 row and loose confidence bullets with:

```markdown
| 严重问题 (Critical Issues) | P0 | 已证实且必须阻断发布的事故级生产风险 | 生产可达的严重权限绕过、可造成关键数据破坏的注入、可导致资金错误或系统性不可用的已证实缺陷 |

**P0 五项硬门槛（必须全部满足）**：
1. **生产可达**：存在明确的生产入口、调用链或生效配置，不能只依据孤立代码形态推测。
2. **证据完整**：代码、配置或调用链能够直接证明问题成立，置信度必须为高。
3. **事故级影响**：可造成严重安全突破、关键数据错误或丢失、资金错误、系统性不可用。
4. **缺少有效防护**：不存在已生效且足以阻断事故的鉴权、参数化、超时、隔离、限流、回滚或补偿机制。
5. **阻断发布**：问题随当前代码上线时必须立即阻断发布并修复。

任一条件不满足都不得标为 P0；中、低置信度不得进入 P0。

**未通过 P0 门槛时的归类**：
- 证据成立但影响未达到事故级，或已有有效缓解机制：下移到 P1。
- 风险可能达到事故级，但生产可达性、调用链、运行配置或防护状态尚未证实：归入待确认。
- 影响仅涉及局部质量、规范或优化：按现有规则归入 P2/P3。
- 除 fast 模式的纯 P0 输出边界外，不得因为未通过 P0 门槛而静默丢弃候选问题。
```

Add these boundary examples after the downgrade rules:

```markdown
**典型 P0 边界**：
- SQL/NoSQL 注入必须证明不可信输入到达未参数化查询，且现有校验或绑定不能阻断；仅发现拼接但输入来源不明时归入待确认。
- 权限绕过必须证明未授权主体能够访问受保护资源或执行敏感操作；仅缺少注解但存在其他鉴权链时不得定为 P0。
- 事务问题必须证明会造成关键写操作部分提交、不可恢复的数据不一致或资金错误；一般事务边界问题下移 P1。
- 外部调用无超时必须证明其位于关键同步路径、没有其他时间边界，并可能耗尽共享资源造成系统性不可用；一般缺少显式超时下移 P1。
- 硬编码凭据必须证明是有效生产凭据且可造成现实安全突破；测试值、示例值或有效性未知的值不得直接定为 P0。
```

Remove the contradictory sentence `` `低置信度` 的问题通常不应直接定为 P0，除非代码证据足够直接 ``. Keep the existing rule that unproven issues belong in 待确认 or a lower severity.

- [x] **Step 4: Synchronize the framework and report evidence contract**

Insert this section before the mode matrix in `references/review-framework.md`:

```markdown
## P0 分级门槛

**P0 五项硬门槛**：生产可达、证据完整且置信度高、事故级影响、缺少有效防护、必须阻断发布。五项必须同时满足；任一不满足都不得标为 P0。

- 证据成立但影响未达到事故级或已有有效缓解机制：P1。
- 事故级风险尚缺生产可达性、调用链、运行配置或防护状态证据：待确认。
- 其他问题继续按影响进入 P2/P3。
- standard、deep、security 模式不得静默丢弃未通过 P0 门槛的候选；fast 按纯 P0 模式边界只输出 P0。
```

In `references/report-format.md`, immediately before `### 🔴 严重问题`, add:

```markdown
### P0 证据门槛

每条 P0 必须在证据、影响和建议中明确证明：生产路径可达、置信度高、后果达到事故级、没有足以阻断事故的有效防护，并且问题必须阻断发布。任一项无法证明时不得输出为 P0，应按审查模式进入 P1、待确认或更低级别。
```

- [x] **Step 5: Run the focused contract test and verify GREEN**

Run: `bash tests/test_contract_docs.sh`

Expected: PASS and final output contains `✅ 契约文档测试通过`.

- [x] **Step 6: Commit the strict classification contract**

```bash
git add tests/test_contract_docs.sh agents/cc-code-reviewer.md references/review-framework.md references/report-format.md
git commit -m "feat: tighten P0 severity classification"
```

---

### Task 2: Make fast's P0-only behavior explicit in interaction and docs

**Files:**
- Modify: `tests/test_contract_docs.sh`
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `references/examples.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: the `REVIEW_MODE=fast` selection from AskUserQuestion.
- Produces: user-visible `fast（仅输出 P0）` selection copy and an execution-plan line `- 输出级别：仅 P0`.

- [x] **Step 1: Add failing interaction-copy assertions**

Add these assertions near the existing `MODE_PICK_LINE` checks in `tests/test_contract_docs.sh`:

```bash
require_literal "$SKILL_FILE" 'label: "fast（仅输出 P0）"' "fast option must state its P0-only output"
require_literal "$SKILL_FILE" '只报告已证实、足以阻断上线的 P0；P1/P2/P3 和待确认项均不输出' "fast option must explain excluded severities"
require_literal "$SKILL_FILE" '输出级别：仅 P0' "fast execution plan must repeat the P0-only boundary"
require_literal "$EXAMPLES_FILE" 'fast（仅输出 P0）' "scan examples must show the explicit fast label"
require_literal "$ROOT_DIR/README.md" '仅输出 P0' "README mode table must disclose fast output severity"
require_literal "$AGENTS_FILE" 'fast 模式只输出满足全部 P0 硬门槛的问题' "AGENTS must document fast P0-only behavior"
require_literal "$CLAUDE_FILE" 'fast 模式只输出满足全部 P0 硬门槛的问题' "CLAUDE must document fast P0-only behavior"
```

- [x] **Step 2: Run the contract test and verify RED**

Run: `bash tests/test_contract_docs.sh`

Expected: FAIL with `fast option must state its P0-only output`.

- [x] **Step 3: Update the AskUserQuestion option and execution plan**

In `skills/cc-code-reviewer/SKILL.md`, change the fast option to:

```yaml
  - label: "fast（仅输出 P0）"
    description: "只报告已证实、足以阻断上线的 P0；P1/P2/P3 和待确认项均不输出"
```

In the execution-plan template, immediately after `- 审查模式：{REVIEW_MODE}`, add:

```text
- 输出级别：仅 P0  ← 仅 REVIEW_MODE=fast 时显示
```

Do not add this line for standard, deep, or security.

- [x] **Step 4: Synchronize user-facing and repository guidance**

In every `请选择审查模式` option list in `references/examples.md`, replace `fast` with `fast（仅输出 P0）`. Add `- 输出级别：仅 P0` to a fast execution-plan example.

In the `README.md` review-mode table, change the fast coverage cell to `正确性 + 事务/配置安全 + 资源管理；仅输出 P0`.

Add this bullet under `### Scan Interaction Contract` in both `AGENTS.md` and `CLAUDE.md`:

```markdown
- fast 模式只输出满足全部 P0 硬门槛的问题；AskUserQuestion 选项必须直观标注“仅输出 P0”，最终执行计划必须再次显示“输出级别：仅 P0”。
```

Run the repository's normalized synchronization guard (it excludes the two intentional header/tool-introduction differences and normalizes `claudecode` to `Claude Code` before comparing):

```bash
diff \
  <(perl -CS -Mutf8 -ne 'next if $. == 1 || $. == 3; s/\bclaudecode\b/Claude Code/g; print' AGENTS.md) \
  <(perl -CS -Mutf8 -ne 'next if $. == 1 || $. == 3; s/\bclaudecode\b/Claude Code/g; print' CLAUDE.md)
```

Expected: exit code 0.

- [x] **Step 5: Run the focused contract test and verify GREEN**

Run: `bash tests/test_contract_docs.sh`

Expected: PASS and final output contains `✅ 契约文档测试通过`.

- [x] **Step 6: Commit the explicit fast-mode copy**

```bash
git add tests/test_contract_docs.sh skills/cc-code-reviewer/SKILL.md references/examples.md README.md AGENTS.md CLAUDE.md
git commit -m "docs: clarify fast mode only reports P0"
```

---

### Task 3: Verify the complete repository contract

**Files:**
- Verify: all files changed by Tasks 1-2

**Interfaces:**
- Consumes: the strict P0 and fast interaction contracts.
- Produces: a clean, fully tested repository state ready for handoff.

- [x] **Step 1: Inspect the final diff for scope and contradictions**

Run:

```bash
git diff f7b91f3328325c809bc0f70355ebf918d848c797..HEAD -- agents/cc-code-reviewer.md references/review-framework.md references/report-format.md skills/cc-code-reviewer/SKILL.md references/examples.md README.md AGENTS.md CLAUDE.md tests/test_contract_docs.sh docs/superpowers/plans/2026-06-22-tighten-p0-severity.md
```

Expected: the fixed implementation baseline captures all four implementation commits plus subsequent review-fix commits; changes remain limited to P0 classification, downgrade completeness, fast interaction copy, synchronized documentation, examples, plan truth-sync, and their tests.

- [x] **Step 2: Search for obsolete loose P0 wording**

Run:

```bash
if rg -n '低置信度.*P0.*除非|无超时的关键外部调用' agents/cc-code-reviewer.md references/review-framework.md references/report-format.md; then
  echo "obsolete loose P0 wording remains" >&2
  exit 1
fi
```

Expected: exit code 0 with no matches.

- [x] **Step 3: Run the complete test suite**

Run: `bash tests/run_all.sh`

Expected: every `tests/test_*.sh` file passes and the suite exits 0.

- [x] **Step 4: Re-run whitespace and repository-state verification**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` exits 0; `git status --short` is empty after the Task 1 and Task 2 commits.

- [x] **Step 5: Record verification evidence**

Final verification record:

- Full suite: 22/22 test files passed.
- Implementation commits: `f88f289` (`feat: tighten P0 severity classification`), `d38b736` (`fix: enforce strict fast P0 output`), `7279348` (`docs: clarify fast mode only reports P0`), `b08232d` (`fix: normalize fast review mode selection`).
- Review repairs are included by inspecting the fixed baseline range `f7b91f3328325c809bc0f70355ebf918d848c797..HEAD`; they do not alter the approved requirements.
