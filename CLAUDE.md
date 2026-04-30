# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Claude Code plugin skill** for enterprise-grade Java code review. It provides 15-dimension comprehensive analysis with 4 review modes (fast/standard/deep/security), supporting both incremental and stock review types.

**Important**: This repository intentionally uses a **skill-only entry point** plus a dedicated sub-agent. Claude Code can invoke the skill explicitly via the quick-reference form `/cc-code-reviewer:cc-code-reviewer` (`/plugin-name:skill-name`).

## Architecture

### Two-Layer Agent Model

```
User Trigger
    ↓
Main Skill (skills/cc-code-reviewer/SKILL.md)
    ├─ Pre-scan phase (4 Bash scripts, no interaction)
    ├─ Interactive mode: 6-step AskUserQuestion flow
    └─ Fast mode: Direct execution with --mode parameter
    ↓
Sub Agent (agents/cc-code-reviewer.md)
    ├─ Execute code review (15 dimensions)
    └─ Optional: Upload to Feishu (lark-doc/lark-base skills)
    ↓
Return results to Main Skill → Display to user
```

### Key Responsibilities

**Main Skill (`skills/cc-code-reviewer/SKILL.md`)**:
- Pre-scan: project detection → branch detection → project scan → lark-cli detection
- Interactive mode: Collect user config via AskUserQuestion (6 steps)
- Fast mode: Validate parameters and launch sub-agent directly
- **Never** execute code review itself

**Sub Agent (cc-code-reviewer.md)**:
- Execute actual code review with injected parameters
- Generate structured report
- Upload to Feishu (if requested)
- **Never** interact with user via AskUserQuestion

### Execution Contract (Highest Priority)

These rules **must** be strictly followed:

1. **Pre-scan before interaction**: Execute all 4 pre-scan scripts first, collect environment data
2. **Summary before questions**: Output "pre-scan summary" once, only after all 4 scripts complete
3. **Structured interaction**: In interactive mode (no `--mode` detected), use AskUserQuestion for each step separately
4. **Fast mode no interaction**: If `--mode` detected, validate and launch sub-agent immediately, no AskUserQuestion
5. **No text replacement**: Never use plain text questions to replace AskUserQuestion steps
6. **Never skip summary**: Even if all parameters provided, always show pre-scan summary

## File Structure

```
skills/cc-code-reviewer/SKILL.md    # Main skill definition (entry point)
agents/cc-code-reviewer.md          # Sub agent for review execution
references/
  ├── review-framework.md             # 15 dimensions definition + mode matrix
  ├── report-format.md                # Report output format specification
  ├── feishu-integration.md           # Feishu upload operation reference
  └── examples.md                     # Complete example dialogues
scripts/
  ├── phase1-detect-project.sh        # Project identification
  ├── phase2-detect-branches.sh       # Branch detection
  ├── phase2-switch-branch.sh         # Branch switching
  ├── phase3-project-scan.sh          # Project structure scan
  ├── phase4-detect-lark-plugin.sh    # lark-cli detection
  └── phase5-prepare-incremental.sh   # Incremental review preparation
```

## Common Development Tasks

### Running The Full Test Suite

Run this before handing off changes:

```bash
bash tests/run_all.sh
```

The suite runs every `tests/test_*.sh` file and then `git diff --check`. It covers:
- `phase1-detect-project.sh`: local path detection and missing-path failures
- `phase2-detect-branches.sh` / `phase2-switch-branch.sh`: branch discovery, clean local checkout, dirty local workspace protection
- `phase3-project-scan.sh`: Maven multi-module scans, module paths with spaces, unknown-project line counts
- `phase4-detect-lark-plugin.sh`: lark-cli detection output contract
- `phase5-prepare-incremental.sh`: incremental diff ranges that include the root commit
- Documentation contracts for fast-mode parameter validation, report persistence, Feishu Base fields, and test instructions

PowerShell scripts mirror the Bash scripts, but the automated local suite runs Bash. When editing `.ps1` files, verify them separately on Windows or a machine with PowerShell.

### Testing Scripts Individually

```bash
# Test pre-scan scripts independently
bash scripts/phase1-detect-project.sh "/path/to/project"
bash scripts/phase2-detect-branches.sh "/path/to/project"
bash scripts/phase3-project-scan.sh "/path/to/project"
bash scripts/phase4-detect-lark-plugin.sh
bash scripts/phase5-prepare-incremental.sh "/path/to/project" 5
```

### Modifying Review Logic

1. **Script logic**: Edit `scripts/*.sh` files directly
2. **Review flow**: Edit `skills/cc-code-reviewer/SKILL.md`
3. **Review dimensions**: Edit `references/review-framework.md`
4. **Agent prompt**: Edit `agents/cc-code-reviewer.md`

**Critical**: Keep mode × dimension matrix consistent between `review-framework.md` and `cc-code-reviewer.md`.

### Plugin Installation

After making changes, reload the plugin:

```bash
/reload-plugins
```

Verify installation by triggering the skill with a Java review request such as `帮我审查这个项目 /path/to/project`.

## Important Notes

### Mode Detection

- **Interactive mode**: No `--mode` parameter → 6-step AskUserQuestion flow
- **Fast mode**: Has `--mode` parameter → Validate and execute directly

### AskUserQuestion Usage

Each interaction step must:
- Call AskUserQuestion exactly once
- Set `multiSelect: false`, except the multi-module stock-review scope step where selecting multiple modules is allowed
- Present clear options with descriptions
- Wait for user response before proceeding

**Never**: Merge multiple steps into one message, or use plain text questions.

### Parameter Injection

Sub agent receives parameters via prompt injection, including:
- Project path, type, scope, mode
- Pre-scan results (project structure, modules)
- Incremental data (git log, changed files, diff stats)

**Sub agent must**: Use these parameters directly, never re-ask user.

### Feishu Integration

Uses `lark-cli` command with:
- `lark-doc` skill for cloud documents
- `lark-base` skill for bitable (multi-dimensional tables)

**Never** use deprecated tools like `feishu_create_doc` or `feishu_bitable_*`.

### Report Format

Report format is defined in `references/report-format.md` — follow it exactly when modifying output structure.
