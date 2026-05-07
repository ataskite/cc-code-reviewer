# CC Code Fixer Design

## Goal

Add a second skill to the existing `cc-code-reviewer` plugin that performs a fix stage from a previous review report. The new entry point is `cc-code-fixer`, and it uses a dedicated fixer agent to read review output, confirm a user-approved repair plan, run a Superpowers-style TDD workflow, and produce a structured fix report.

The existing `cc-code-reviewer` scan skill remains responsible only for review and report generation.

## Non-Goals

- Do not merge scan and fix into one large skill.
- Do not change the existing review report format except where optional fields or references make fix-stage handoff clearer.
- Do not automatically fix all findings without explicit user confirmation.
- Do not mark low-confidence or "待确认" findings as fixed unless the user explicitly selects them and the fixer can verify them.
- Do not depend on Feishu being available; local Markdown reports must remain first-class inputs and outputs.

## User Entry Points

Primary invocation:

```text
/cc-code-reviewer:cc-code-fixer <review-source> --project /path/to/project
```

Supported review sources:

- Local Markdown review report, such as `code-review-report-foo-20260507-103000.md`
- Feishu cloud document URL created by the scan stage
- Feishu Base URL or token created by the scan stage

Optional fast-mode parameters:

```text
--severity P0,P1
--dimensions 安全,正确性,数据库/数据访问
--issues P0-1,P1-3
--workspace worktree|branch|current
--strategy conservative|standard|deep
--upload no|doc|base|both
--branch fix/review-findings
```

Fast mode is enabled when any of `--severity`, `--dimensions`, `--issues`, `--workspace`, `--strategy`, or `--upload` is present. Fast mode requires `review-source`, `--project`, `--workspace`, `--strategy`, and at least one scope selector from `--severity`, `--dimensions`, or `--issues`.

If fast-mode parameters are incomplete, the skill must report the missing values and stop. It must not silently switch to interactive mode.

## Top-Level Architecture

```text
User trigger
  ↓
cc-code-fixer skill
  ├─ detect and normalize review source
  ├─ detect project, git, lark-cli, and Superpowers availability
  ├─ summarize fixable findings
  ├─ collect fix plan through AskUserQuestion
  ├─ invoke brainstorming with normalized findings as input
  ├─ prepare worktree or branch
  └─ launch cc-code-fixer agent with injected parameters
      ↓
      TDD repair execution
      ↓
      verification
      ↓
      local/Feishu fix report
      ↓
      optional Feishu Base status update
```

The skill owns interaction and orchestration. The fixer agent owns code changes, tests, verification, and report generation.

## New Files

Create:

- `skills/cc-code-fixer/SKILL.md`: user-facing fix-stage entry point and interaction contract.
- `agents/cc-code-fixer.md`: dedicated repair agent prompt.
- `references/fix-workflow.md`: fix-stage process details and Superpowers integration contract.
- `references/fix-report-format.md`: Markdown fix report format.
- `references/fix-feishu-integration.md`: Feishu document/Base read and update rules.
- `references/fix-examples.md`: complete interactive and fast-mode examples.
- `scripts/phase6-detect-fix-input.sh` and `.ps1`: classify report source and extract source metadata.
- `scripts/phase7-detect-superpowers.sh` and `.ps1`: detect relevant Superpowers skills.
- `scripts/phase8-prepare-fix-workspace.sh` and `.ps1`: validate or prepare fix branch/worktree.

Modify:

- `README.md`: document scan/fix split, `cc-code-fixer` usage, and report handoff.
- `references/feishu-integration.md`: document that existing fields `修复状态`, `修复时间`, `修复分支`, `修复人`, and `备注` are the default fix-stage update surface. Do not add new Base fields unless a later requirement explicitly asks for richer tracking.
- `tests/test_contract_docs.sh`: assert the fix-stage documentation contracts exist.
- Add focused tests for the new scripts.

## Fix Input Normalization

The fixer must convert every input source to the same internal finding model:

```text
issue_id
severity
dimension
tech_stack
title
location
confidence
evidence
impact
suggestion
source_type
source_ref
feishu_base_token
feishu_table_id
feishu_record_id
fix_status
```

Markdown parsing should prefer the existing report markers:

- `问题编号`
- `位置`
- `置信度`
- `所属维度`
- `问题`
- `证据`
- `影响`
- `建议`

Feishu Base parsing should use field names from `references/feishu-integration.md`, especially `问题编号`, `严重级别`, `所属维度`, `位置`, `置信度`, `证据`, `影响`, `修复建议`, and `修复状态`.

Findings with `修复状态=已修复` should be excluded by default and shown separately as already handled.

## Interactive Flow

Before any interaction, the skill must run source/project/lark/Superpowers detection and then display one summary:

```text
🔧 修复输入解析完成

📄 审查报告：{source display}
📂 项目：{project path}
🌿 Git：{current branch, dirty/clean status, worktree support}
🧠 Superpowers：{available skills or degraded mode reason}
📊 可修复问题：P0 {n} / P1 {n} / P2 {n} / P3 {n} / 待确认 {n}
📋 已修复或跳过：{n}
```

Then collect the plan with separate `AskUserQuestion` calls:

1. Workspace strategy:
   - New isolated worktree, recommended
   - New fix branch in current checkout
   - Current branch
2. Fix scope, multi-select:
   - P0
   - P1
   - P2
   - P3
   - 待确认
   - Custom issue IDs
   - If Custom issue IDs is selected, collect a free-form comma-separated issue list in a separate interaction.
3. Dimension scope, multi-select:
   - Use dimensions present in normalized findings
4. Fix strategy:
   - Conservative: high-confidence, low-blast-radius fixes only
   - Standard: selected issues plus focused tests
   - Deep: allows small refactors when needed
5. Output target:
   - Local Markdown only
   - Feishu cloud document
   - Update original Feishu Base
   - Both document and Base update
6. Final execution confirmation.

The skill must print a complete execution plan before the final confirmation.

## Superpowers Integration

The fix stage should integrate with Superpowers as a process contract, not just a text reference.

Required sequence when available:

1. `brainstorming`: feed the normalized findings, project context, selected scope, and constraints into a repair design.
2. `using-git-worktrees`: prepare the selected isolated workspace strategy when the user chooses worktree mode.
3. `test-driven-development`: require failing tests before production code changes for behavior fixes.
4. `verification-before-completion`: require fresh verification before declaring fixes complete.
5. `finishing-a-development-branch`: present merge, PR, or keep-branch options after successful verification.

If a Superpowers skill is unavailable, the fixer must say which part is degraded and follow the local fallback rules from `references/fix-workflow.md`.

## Fixer Agent Contract

The skill invokes the sub-agent:

```text
subagent_type: "cc-code-reviewer:cc-code-fixer"
description: "执行 Java 审查问题修复"
```

Injected prompt sections:

```text
## 修复任务参数（外部注入，请直接使用，无需再次确认）

| 参数 | 值 |
|------|-----|
| 项目路径 | ... |
| 工作区路径 | ... |
| 修复分支 | ... |
| 输入来源 | ... |
| 修复范围 | ... |
| 修复维度 | ... |
| 修复策略 | ... |
| 输出选项 | ... |
| Superpowers 可用性 | ... |

### 归一化问题清单
...

### 用户确认的修复计划
...

### 项目预扫描结果
...
```

Agent rules:

- Do not ask the user questions.
- Do not fix findings outside the injected scope.
- Do not change public behavior unless a test captures the intended behavior.
- For each selected high-confidence bug, write or update a failing test first, run it, then implement the fix.
- For style-only or configuration-only changes where TDD is not meaningful, document why no failing test is applicable and run the closest verification command.
- Preserve user changes in the worktree. Do not revert unrelated files.
- Record every selected issue as `fixed`, `not fixed`, `partially fixed`, `not applicable`, or `needs human confirmation`.

## Fix Report

The agent must save:

```text
fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md
```

The report must include:

- Fix configuration snapshot
- Input report/source
- Workspace and branch
- Selected scope
- Summary counts
- Fixed issues
- Partially fixed issues
- Not fixed issues with reasons
- Tests added or changed
- Verification commands and results
- Code change summary
- Feishu document/Base update result
- Suggested next actions

## Feishu Behavior

If the input is a Feishu Base and the user chooses Base update, update existing records:

- `修复状态`: `已修复`, `已忽略`, `不适用`, or `待修复`
- `修复时间`: current date
- `修复分支`: actual fix branch
- `备注`: concise fix summary or reason not fixed

If the user chooses a fix report document, create a new Feishu cloud document from the fix report Markdown and link it in the final summary.

If Feishu update fails, keep the local Markdown report and clearly report the failed command or error summary. Feishu failure must not discard code fixes.

## Safety Rules

- Dirty workspace protection is mandatory before branch switching or worktree creation.
- Worktree mode is recommended because fixes can touch many files.
- If baseline tests fail before fixing, report the failure and ask whether to continue.
- If a selected finding cannot be reproduced or verified, do not force a code change.
- Security fixes must avoid weakening validation, authentication, authorization, tenant isolation, or logging hygiene.
- Dependency upgrades must be minimal and justified by the finding.
- The fixer must not fabricate report evidence or claim a test passed without command output.

## Testing Strategy

Script tests:

- `phase6-detect-fix-input.sh` recognizes local Markdown, Feishu doc URL, Feishu Base URL, and missing input.
- `phase7-detect-superpowers.sh` reports available and unavailable skill sets.
- `phase8-prepare-fix-workspace.sh` blocks unsafe dirty branch operations and validates requested branch names.

Documentation contract tests:

- `skills/cc-code-fixer/SKILL.md` contains the required pre-interaction summary, AskUserQuestion steps, fast-mode validation, and sub-agent injection format.
- `agents/cc-code-fixer.md` forbids user interaction and requires TDD/verification behavior.
- `references/fix-report-format.md` defines all required report sections.
- `references/fix-feishu-integration.md` defines Base update fields and local fallback behavior.

Manual acceptance scenarios:

- Local Markdown report → select P0/P1 → worktree → local fix report.
- Feishu Base report → select security findings → update Base statuses.
- Fast mode with complete parameters → no AskUserQuestion.
- Fast mode with missing parameters → validation error and stop.
- No Superpowers detected → degraded workflow message and local fallback.

## Open Decisions

Use `cc-code-fixer` as the skill and agent name. The broader plugin name remains `cc-code-reviewer` for marketplace continuity.

Default workspace strategy is a new isolated worktree.

Default fix strategy is `standard`.

Default output is local Markdown unless the original source was Feishu and lark-cli is available, in which case the user is offered Feishu update options.
