# v1.6.4 Review Findings Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 修复 v1.6.4 当前审查确认的语义分组、跨文件重归档、partial 批次和发布契约问题，使新功能可验证、可恢复、可安全合并。

**Architecture:** 保持现有 Bash + Perl 确定性脚本架构。新增行为先通过独立回归测试锁定；`plan.json` 与 `summary.json` 保留现有兼容字段，并用新增字段表达 partial 已合并但未完成覆盖的状态。语义分组由独立脚本依据冻结 review-input 元数据生成，再由 planner 读取。

**Tech Stack:** Bash、Perl JSON::PP、Markdown 契约文档、现有 `tests/run_all.sh`。

**Spec:** 当前 v1.6.4 `CHANGELOG.md`、`skills/cc-code-reviewer/SKILL.md` 与本轮代码审查结论。

## Global Constraints

- 不覆盖工作区已有 v1.6.4 改动。
- 语义分组、partial 和跨文件重归档必须 fail-open/可恢复语义与文档保持一致。
- `PROJECT_DIR` 外的路径不得进入重归档候选。
- 每个修复先添加可复现的失败测试，再修改生产脚本。
- 完成前必须运行 `bash tests/run_all.sh` 和 `git diff --check`。

---

### Task 1: 锁定 v1.6.4 回归缺陷

**Files:**
- Modify: `tests/core/test_core_plan_file_batches.sh`
- Modify: `tests/core/test_core_merge_batch_results.sh`
- Modify: `tests/core/test_core_relocate_findings.sh`
- Modify: `tests/test_contract_docs.sh`
- Create: `tests/core/test_core_prepare_semantic_groups.sh`

**Interfaces:**
- Tests consume the existing planner, merger, relocation script and the new semantic-group generator contract.
- Tests produce executable regression coverage for JSON parsing, path containment, partial state, and incremental grouping.

- [x] **Step 1: Write failing assertions**
  - Parse every successful semantic-group `plan.json` with `JSON::PP`.
  - Reject manifest entries outside `PROJECT_DIR`, including `../` and symlinked external files.
  - Treat partial results with zero formal findings as blocked/failed.
  - Assert partial merged batches appear in a separate `merged_batch_ids` ledger.
  - Assert the semantic-group generator emits stable groups from review-input metadata and skips one-to-three-file inputs.

- [x] **Step 2: Run focused tests and verify expected failures**

```bash
bash tests/core/test_core_plan_file_batches.sh
bash tests/core/test_core_relocate_findings.sh
bash tests/core/test_core_merge_batch_results.sh
bash tests/core/test_core_prepare_semantic_groups.sh
```

Expected: the new assertions fail against the current implementation.

---

### Task 2: Fix planner and evidence re-archiving boundaries

**Files:**
- Modify: `scripts/core/plan-file-batches.sh:261-287`
- Modify: `scripts/core/relocate-findings.sh:111-125`

**Interfaces:**
- Planner continues to emit valid JSON with optional `semantic_grouping_enabled` and `semantic_groups_path`.
- Relocation continues to accept `(REPORT_MD, PROJECT_DIR, MANIFEST_FILE)` but filters candidates to canonical files inside the project root.

- [x] **Step 1: Add the smallest planner fix**
  - Emit a comma after `semantic_groups_path` only when optional semantic fields are present.
  - Parse the generated plan in the regression test.

- [x] **Step 2: Add candidate containment validation**
  - Resolve each manifest path with `abs_path`.
  - Require the resolved candidate to equal `PROJECT_DIR` descendant and reject external symlink targets.
  - Keep invalid entries fail-open by skipping them, while preserving valid in-project candidates.

- [x] **Step 3: Run focused tests**

```bash
bash tests/core/test_core_plan_file_batches.sh
bash tests/core/test_core_relocate_findings.sh
```

Expected: both pass, including valid JSON and no external relocation.

---

### Task 3: Repair partial merge accounting and recovery contract

**Files:**
- Modify: `scripts/core/merge-batch-results.sh:221-255,365-395,480-555`
- Modify: `scripts/core/show-batch-status.sh:399-405`
- Modify: `skills/cc-code-reviewer/SKILL.md:1080-1115,1537-1555`
- Modify: `references/report-format.md`
- Modify: `tests/core/test_core_merge_batch_results.sh`
- Modify: `tests/core/test_core_show_batch_status.sh`
- Modify: `tests/test_contract_docs.sh`

**Interfaces:**
- `summary.json.included_batch_ids` remains the completed-coverage ledger.
- New `summary.json.merged_batch_ids` records completed and partial batches whose results entered the report.
- Partial status remains runnable and is accepted by the Skill’s batch selection and validation rules.

- [x] **Step 1: Add failing partial assertions**
  - Partial with no formal finding must exit with merge blocking semantics.
  - Partial with findings must populate `merged_batch_ids` and retain conservative coverage.
  - Skill contract must mention `partial` in runnable and validation sets.

- [x] **Step 2: Implement minimal merge/ledger changes**
  - Validate partial result content before inclusion.
  - Append accepted partial IDs to `merged_batch_ids` without inflating completed coverage.
  - Mark coverage ledger items as `partial` and retain interruption reasons.

- [x] **Step 3: Synchronize display and report text**
  - Include partial in dynamic selection rules.
  - Update Java report summary and Skill merge steps so they no longer claim only completed batches are merged.

- [x] **Step 4: Run focused tests**

```bash
bash tests/core/test_core_merge_batch_results.sh
bash tests/core/test_core_show_batch_status.sh
bash tests/test_contract_docs.sh
```

---

### Task 4: Close the incremental semantic-group generation loop

**Files:**
- Create: `scripts/core/prepare-semantic-groups.sh`
- Create: `tests/core/test_core_prepare_semantic_groups.sh`
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `README.md`

**Interfaces:**
- Command: `prepare-semantic-groups.sh PROJECT_DIR REVIEW_INPUT_PATH OUTPUT_PATH`.
- Input: frozen `review-input.json` selected items and metadata only.
- Output: deterministic TSV `<group_key>\t<repo-relative-path>`, or an empty/no-file result when selected file count is <= 3 or no high-confidence group exists.

- [x] **Step 1: Add failing generator tests**
  - Same module/function files group together.
  - Test + implementation and rename pairs group together when metadata supports it.
  - One-to-three selected files produce no grouping.
  - Paths are repository-relative and output is deterministic.

- [x] **Step 2: Implement the metadata-only generator**
  - Use selected item path, extension, module/directory and change metadata.
  - Do not inspect source contents or expand review scope.
  - Use stable group keys and write atomically.

- [x] **Step 3: Wire Skill instructions to run it before planner invocation**
  - Generate the file before exporting `CC_CODE_REVIEWER_SEMANTIC_GROUPS_FILE`.
  - Pass the generated path to single-agent and file-batch routes.

- [x] **Step 4: Run full verification**

```bash
bash tests/run_all.sh
git diff --check
```

Expected: all tests pass and the worktree contains only the intended fixes, tests, plan, and synchronized contract text.

