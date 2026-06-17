# Stock Review Module Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align stock review interaction with incremental/full/module choices and support selected-module batching strategies.

**Architecture:** Keep the skill's external flow user-friendly while preserving existing internal variables. `全量审查` and `指定模块` still map to stock review internally, and `phase11-plan-large-batches.sh` becomes scope-aware so smart batching can plan selected modules instead of always planning the whole Maven reactor.

**Tech Stack:** Bash, Markdown skill contracts, shell contract tests, jq/JSON validation.

---

### Task 1: Contract Tests

**Files:**
- Modify: `tests/test_contract_docs.sh`
- Modify: `tests/test_phase11_plan_large_batches.sh`

- [ ] Add contract assertions for the three review entries: `增量审查`, `全量审查`, `指定模块`.
- [ ] Add contract assertions for `STOCK_REVIEW_STRATEGY`, `module-sequential`, `ai-planned`, and default `CONCURRENCY=1`.
- [ ] Add planner regression tests for selected-module smart batching.
- [ ] Add planner regression tests for module-sequential batching.
- [ ] Run the focused tests and verify they fail before implementation.

### Task 2: Scope-Aware Planner

**Files:**
- Modify: `scripts/phase11-plan-large-batches.sh`

- [ ] Add optional arguments: `REVIEW_SCOPE_INPUT` and `PLANNING_STRATEGY`.
- [ ] Normalize comma/space separated module paths and validate each selected module has a `pom.xml`.
- [ ] For `semantic-cost-batching`, generate work units only for selected modules while retaining bounded support context candidates.
- [ ] For `module-sequential`, emit one batch per selected module with warning metadata for oversized modules instead of blocking.
- [ ] Write `review_scope`, `selected_modules`, and strategy into `plan.json` and every batch JSON.
- [ ] Run `tests/test_phase11_plan_large_batches.sh`.

### Task 3: Skill Flow Contract

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `agents/cc-code-reviewer.md` if parameter wording needs alignment
- Modify: `references/examples.md`

- [ ] Change the review entry question to `增量审查 / 全量审查 / 指定模块`.
- [ ] Add the selected-module collection step after `指定模块`.
- [ ] Add the stock review strategy step for multi-module full/module scans.
- [ ] Update Maven large repo gating so full and selected-module scans can enter planning.
- [ ] Change concurrency default to `串行执行` / `CONCURRENCY=1`, max `3`.
- [ ] Update examples to show the new flow.
- [ ] Run `tests/test_contract_docs.sh`.

### Task 4: Verification

**Files:**
- Verify all touched files.

- [ ] Run `bash tests/test_phase11_plan_large_batches.sh`.
- [ ] Run `bash tests/test_contract_docs.sh`.
- [ ] Run `bash tests/run_all.sh`.
- [ ] Run a real yudao selected-module planner check with `/Users/jiangkun/Documents/github-project/yudao-cloud`.
