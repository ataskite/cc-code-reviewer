# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

This is a **claudecode plugin skill** for enterprise-grade Java code review and report-driven fixing. It provides 15-dimension comprehensive analysis with 4 review modes (fast/standard/deep/security), supports incremental and stock review types, and can use review reports as input for a controlled fix stage.

**Important**: This repository intentionally uses **skill-only entry points** plus dedicated sub-agents. Claude Code can invoke the skills explicitly via `/cc-code-reviewer:cc-code-reviewer` for scan and `/cc-code-reviewer:cc-code-fixer` for fix.

## Architecture

### Overview

```mermaid
flowchart TD
    User["User / Claude Code session"]
    ReviewSkill["Scan Skill<br/>skills/cc-code-reviewer/SKILL.md"]
    FixSkill["Fix Skill<br/>skills/cc-code-fixer/SKILL.md"]
    ReviewAgent["Scan Agent<br/>agents/cc-code-reviewer.md"]
    Reports["Review reports<br/>Markdown / Feishu Doc / Feishu Base"]
    FixReports["Fix reports<br/>Markdown / Feishu Doc / Base writeback"]
    Lark["lark-cli<br/>lark-doc / lark-base"]
    Superpowers["Superpowers<br/>brainstorming / TDD / verification"]
    SubAgentDriven["subagent-driven-development"]

    subgraph ScanPhase["Scan phase"]
      ReviewSkill --> ScanScripts["phase1-5 scripts<br/>project / branches / stack / lark / incremental diff"]
      ScanScripts --> ReviewAgent
      ReviewAgent --> Reports
    end

    subgraph FixPhase["Fix phase"]
      Reports --> FixSkill
      FixSkill --> FixScripts["phase6-8 scripts<br/>input / superpowers / workspace"]
      FixScripts --> Superpowers
      Superpowers --> SubAgentDriven
      SubAgentDriven --> FixReports
    end

    User --> ReviewSkill
    User --> FixSkill
    Reports -.optional upload/read.-> Lark
    FixReports -.optional create/writeback.-> Lark
```

### Key Responsibilities

**Main Skill (`skills/cc-code-reviewer/SKILL.md`)**:
- Pre-scan: project detection → branch detection → project scan → lark-cli detection
- Interactive mode: Collect user config via AskUserQuestion (6 steps)
- Fast mode: Validate parameters and launch sub-agent directly
- **Never** execute code review itself

**Review Agent (`agents/cc-code-reviewer.md`)**:
- Execute actual code review with injected parameters
- Generate structured report
- Upload to Feishu (if requested)
- **Never** interact with user via AskUserQuestion

**Fix Skill (`skills/cc-code-fixer/SKILL.md`)**:
- Normalize fix input from local Markdown, Feishu Doc, or Feishu Base
- Preflight: project detection → branch detection → project scan → lark-cli detection → Superpowers detection
- Collect confirmed issue scope and output target via AskUserQuestion
- Hand off to Superpowers: brainstorming produces spec + plan, then subagent-driven-development executes
- **Never** execute repairs itself

### Execution Contract (Highest Priority)

These rules **must** be strictly followed:

1. **Pre-scan before interaction**: Execute scan/fix preflight scripts first, collect environment data
2. **Summary before questions**: Output a preflight summary once, only after the required scripts complete
3. **Structured interaction**: In interactive mode, use AskUserQuestion for each step separately
4. **Fast mode no interaction**: For scan, `--mode` triggers fast mode. Fix stage is always interactive.
5. **No text replacement**: Never use plain text questions to replace AskUserQuestion steps
6. **Never skip summary**: Even if all parameters provided, always show pre-scan summary
7. **Fix stage honors confirmed scope**: `cc-code-fixer` must only repair the confirmed issue set
8. **Fix stage delegates to Superpowers**: brainstorming produces spec + plan, subagent-driven-development executes; no dedicated fix sub-agent

## File Structure

```
skills/cc-code-reviewer/SKILL.md    # Main skill definition (entry point)
skills/cc-code-fixer/SKILL.md       # Fix-stage skill definition
agents/cc-code-reviewer.md          # Sub agent for review execution
references/
  ├── review-framework.md             # 15 dimensions definition + mode matrix
  ├── report-format.md                # Report output format specification
  ├── feishu-integration.md           # Feishu upload operation reference
  ├── fix-workflow.md                 # Fix-stage workflow contract
  ├── fix-report-format.md            # Fix report output format
  ├── fix-feishu-integration.md       # Fix-stage Feishu read/write contract
  └── examples.md                     # Complete example dialogues
scripts/
  ├── phase1-detect-project.sh        # Project identification
  ├── phase2-detect-branches.sh       # Branch detection
  ├── phase2-switch-branch.sh         # Branch switching
  ├── phase3-project-scan.sh          # Project structure scan
  ├── phase4-detect-lark-plugin.sh    # lark-cli detection
  ├── phase5-prepare-incremental.sh   # Incremental review preparation
  ├── phase6-detect-fix-input.sh      # Fix input detection
  ├── phase7-detect-superpowers.sh    # Superpowers workflow detection
  ├── phase8-prepare-fix-workspace.sh # Fix branch/worktree preparation
  └── phase9-collect-fix-metadata.sh  # Fix completion time, branch, and git user
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
- `phase6-detect-fix-input.sh`: local Markdown, Feishu Doc, Feishu Base, and compact Base selectors
- `phase7-detect-superpowers.sh`: required Superpowers skill discovery
- `phase8-prepare-fix-workspace.sh`: current/branch/worktree strategies and dirty workspace protection
- Documentation contracts for fast-mode parameter validation, report persistence, Feishu Base fields, fix-stage contracts, and test instructions

The plugin only supports macOS and Linux. Keep script changes in Bash and verify them through the local Bash suite.

### Testing Scripts Individually

```bash
# Test pre-scan scripts independently
bash scripts/phase1-detect-project.sh "/path/to/project"
bash scripts/phase2-detect-branches.sh "/path/to/project"
bash scripts/phase3-project-scan.sh "/path/to/project"
bash scripts/phase4-detect-lark-plugin.sh
bash scripts/phase5-prepare-incremental.sh "/path/to/project" 5
bash scripts/phase6-detect-fix-input.sh "/path/to/report.md"
bash scripts/phase7-detect-superpowers.sh
bash scripts/phase8-prepare-fix-workspace.sh "/path/to/project" worktree "fix/review-findings"
bash scripts/phase9-collect-fix-metadata.sh "/path/to/project"
```

### Modifying Review Logic

1. **Script logic**: Edit `scripts/*.sh` files directly
2. **Review flow**: Edit `skills/cc-code-reviewer/SKILL.md`
3. **Review dimensions**: Edit `references/review-framework.md`
4. **Agent prompt**: Edit `agents/cc-code-reviewer.md`

**Critical**: Keep mode × dimension matrix consistent between `review-framework.md` and `cc-code-reviewer.md`.

### Modifying Fix Logic

1. **Fix flow**: Edit `skills/cc-code-fixer/SKILL.md`
2. **Input/workspace scripts**: Edit phase6-8 Bash scripts together
3. **Fix report or Feishu contracts**: Edit `references/fix-report-format.md` and `references/fix-feishu-integration.md`

**Critical**: Keep fix statuses, report filename conventions, and Feishu field names consistent across skill, references, and tests.

### Plugin Installation

After making changes, reload the plugin:

```bash
/reload-plugins
```

Verify installation by triggering the skill with a Java review request such as `帮我审查这个项目 /path/to/project`.

## Important Notes

### Scan Mode Detection

- **Interactive mode**: No `--mode` parameter → 6-step AskUserQuestion flow
- **Fast mode**: Has `--mode` parameter → Validate and execute directly

### Fix Mode Detection

- **Fixed interactive mode**: `cc-code-fixer` always requires interactive confirmation. No fast mode or `--mode` parameter.
- User provides project path only; all fix planning is collected through AskUserQuestion steps.

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

Fix report format is defined in `references/fix-report-format.md`. Feishu fix-stage read/write behavior is defined in `references/fix-feishu-integration.md`.
