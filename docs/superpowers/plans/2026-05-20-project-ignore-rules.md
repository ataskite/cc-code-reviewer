# Project Ignore Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add project-level AI-readable ignore rules for recurring false positives in scan reports.

**Architecture:** Add a dedicated `cc-code-ignore` skill that reads a report source and writes `.cc-code-reviewer/ignore/issues.yml`. Update scan orchestration to inject that file into the scan agent, and update report contracts to disclose ignore filtering.

**Tech Stack:** Claude Code plugin skills, Markdown contracts, Bash contract tests, YAML ignore file.

---

### Task 1: Contract Test

**Files:**
- Modify: `tests/test_contract_docs.sh`

- [x] Add assertions for `skills/cc-code-ignore/SKILL.md`, `references/ignore-workflow.md`, scan ignore injection, and report disclosure.
- [x] Run `bash tests/test_contract_docs.sh`.
- [x] Confirm the test fails before implementation because the new skill and workflow files do not exist.

### Task 2: Ignore Skill And Reference

**Files:**
- Create: `skills/cc-code-ignore/SKILL.md`
- Create: `references/ignore-workflow.md`

- [x] Define one-input project path behavior.
- [x] Define supported sources: Feishu Base and local Markdown.
- [x] Define user problem-number selection as a temporary locator only.
- [x] Define the minimal AI instruction YAML format with `name`, `applies_to`, and `skip_when`.

### Task 3: Scan Integration Contract

**Files:**
- Modify: `skills/cc-code-reviewer/SKILL.md`
- Modify: `agents/cc-code-reviewer.md`
- Modify: `references/report-format.md`

- [x] Add ignore file detection after pre-scan and before agent launch.
- [x] Add `IGNORE_RULES_PATH` and `IGNORE_RULES_CONTENT` to agent prompt injection.
- [x] Require the agent to apply ignore rules before outputting findings.
- [x] Require report snapshot and final summary to disclose ignore status and counts.

### Task 4: User-Facing Docs

**Files:**
- Modify: `README.md`
- Modify: `references/examples.md`

- [x] Document the `/cc-code-reviewer:cc-code-ignore` entry point.
- [x] Show the project ignore path and minimal YAML example.
- [x] Add example wording for ignore-hit disclosure.

### Task 5: Verification

**Files:**
- Run all test scripts.

- [x] Run `bash tests/test_contract_docs.sh`.
- [x] Run `bash tests/run_all.sh`.
- [x] Ensure unrelated existing changes remain untouched.
