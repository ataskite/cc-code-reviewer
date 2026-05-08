# CC Code Fixer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `cc-code-fixer` skill and dedicated fixer agent that can consume a previous review report, confirm a repair plan, run a Superpowers-style TDD fix workflow, and produce local or Feishu fix reports.

**Architecture:** Keep scan and fix separate inside the same plugin. The new skill owns input parsing, preflight detection, structured user confirmation, and agent invocation. The new fixer agent owns code changes, tests, verification, status classification, and fix report output.

**Tech Stack:** Claude Code plugin skills and agents, Bash and PowerShell preflight scripts, Markdown reference docs, shell-based test suite, `lark-cli` integration references.

---

## File Structure

- Create `skills/cc-code-fixer/SKILL.md`: fix-stage entry point, interactive flow, fast-mode validation, and sub-agent prompt injection contract.
- Create `agents/cc-code-fixer.md`: repair agent behavior, TDD rules, verification rules, Feishu update rules, and final summary format.
- Create `references/fix-workflow.md`: detailed workflow for report normalization, Superpowers integration, workspace preparation, and fallback behavior.
- Create `references/fix-report-format.md`: required Markdown fix report sections and issue status formats.
- Create `references/fix-feishu-integration.md`: Feishu doc read, Base read, Base update, and local fallback command rules.
- Create `references/fix-examples.md`: interactive and fast-mode examples for local Markdown, Feishu doc, and Feishu Base sources.
- Create `scripts/phase6-detect-fix-input.sh` and `scripts/phase6-detect-fix-input.ps1`: classify fix input source.
- Create `scripts/phase7-detect-superpowers.sh` and `scripts/phase7-detect-superpowers.ps1`: detect relevant Superpowers skills.
- Create `scripts/phase8-prepare-fix-workspace.sh` and `scripts/phase8-prepare-fix-workspace.ps1`: validate workspace strategy and branch safety.
- Create `tests/test_phase6_detect_fix_input.sh`: Bash coverage for input classification.
- Create `tests/test_phase7_detect_superpowers.sh`: Bash coverage for skill detection.
- Create `tests/test_phase8_prepare_fix_workspace.sh`: Bash coverage for workspace safety.
- Modify `tests/test_contract_docs.sh`: assert fix skill, agent, references, README, and plugin metadata contracts.
- Modify `README.md`: document scan/fix split and `cc-code-fixer` usage.
- Modify `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`: update description, tags, and bump both versions from `1.0.1` to `1.1.0`.

## Task 1: Phase 6 Fix Input Detection

**Files:**
- Create: `tests/test_phase6_detect_fix_input.sh`
- Create: `scripts/phase6-detect-fix-input.sh`
- Create: `scripts/phase6-detect-fix-input.ps1`

- [ ] **Step 1: Write the failing Bash test**

Create `tests/test_phase6_detect_fix_input.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase6 fix input.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

REPORT_FILE="$TMP_DIR/code-review-report-demo-20260507-103000.md"
cat >"$REPORT_FILE" <<'REPORT'
# Java 代码审查报告

**问题编号**：P0-1
**位置**：src/main/java/demo/UserController.java:42
**置信度**：高 | **所属维度**：安全
**问题**：接口缺少鉴权
REPORT

LOCAL_OUTPUT="$(bash "$ROOT_DIR/scripts/phase6-detect-fix-input.sh" "$REPORT_FILE")"
echo "$LOCAL_OUTPUT" | grep -q "FIX_INPUT_TYPE=local-markdown"
echo "$LOCAL_OUTPUT" | grep -q "FIX_INPUT_PATH=$REPORT_FILE"
echo "$LOCAL_OUTPUT" | grep -q "FIX_INPUT_EXISTS=true"

DOC_OUTPUT="$(bash "$ROOT_DIR/scripts/phase6-detect-fix-input.sh" "https://example.feishu.cn/docx/ABC123")"
echo "$DOC_OUTPUT" | grep -q "FIX_INPUT_TYPE=feishu-doc"
echo "$DOC_OUTPUT" | grep -q "FIX_INPUT_URL=https://example.feishu.cn/docx/ABC123"

BASE_OUTPUT="$(bash "$ROOT_DIR/scripts/phase6-detect-fix-input.sh" "https://example.feishu.cn/base/BASE123?table=tbl456")"
echo "$BASE_OUTPUT" | grep -q "FIX_INPUT_TYPE=feishu-base"
echo "$BASE_OUTPUT" | grep -q "FIX_INPUT_URL=https://example.feishu.cn/base/BASE123?table=tbl456"

TOKEN_OUTPUT="$(bash "$ROOT_DIR/scripts/phase6-detect-fix-input.sh" "base:BASE123:tbl456")"
echo "$TOKEN_OUTPUT" | grep -q "FIX_INPUT_TYPE=feishu-base-token"
echo "$TOKEN_OUTPUT" | grep -q "FEISHU_BASE_TOKEN=BASE123"
echo "$TOKEN_OUTPUT" | grep -q "FEISHU_TABLE_ID=tbl456"

MISSING_OUTPUT="$TMP_DIR/phase6-missing.out"
if bash "$ROOT_DIR/scripts/phase6-detect-fix-input.sh" "$TMP_DIR/missing.md" >"$MISSING_OUTPUT" 2>&1; then
  echo "phase6 should fail for missing local markdown" >&2
  exit 1
fi
grep -q "修复输入不存在" "$MISSING_OUTPUT"

UNSUPPORTED_OUTPUT="$TMP_DIR/phase6-unsupported.out"
if bash "$ROOT_DIR/scripts/phase6-detect-fix-input.sh" "not-a-report-source" >"$UNSUPPORTED_OUTPUT" 2>&1; then
  echo "phase6 should fail for unsupported source" >&2
  exit 1
fi
grep -q "无法识别修复输入来源" "$UNSUPPORTED_OUTPUT"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/test_phase6_detect_fix_input.sh
```

Expected: FAIL because `scripts/phase6-detect-fix-input.sh` does not exist.

- [ ] **Step 3: Implement the Bash script**

Create `scripts/phase6-detect-fix-input.sh`:

```bash
#!/bin/bash
set -euo pipefail

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
  echo "修复输入不能为空" >&2
  exit 1
fi

case "$INPUT" in
  http://*docx/*|https://*docx/*|http://*docs/*|https://*docs/*)
    echo "FIX_INPUT_TYPE=feishu-doc"
    echo "FIX_INPUT_URL=$INPUT"
    ;;
  http://*base/*|https://*base/*)
    echo "FIX_INPUT_TYPE=feishu-base"
    echo "FIX_INPUT_URL=$INPUT"
    ;;
  base:*:*)
    REST="${INPUT#base:}"
    BASE_TOKEN="${REST%%:*}"
    TABLE_ID="${REST#*:}"
    if [ -z "$BASE_TOKEN" ] || [ -z "$TABLE_ID" ] || [ "$BASE_TOKEN" = "$TABLE_ID" ]; then
      echo "无法识别修复输入来源: $INPUT" >&2
      exit 1
    fi
    echo "FIX_INPUT_TYPE=feishu-base-token"
    echo "FEISHU_BASE_TOKEN=$BASE_TOKEN"
    echo "FEISHU_TABLE_ID=$TABLE_ID"
    ;;
  *.md)
    if [ ! -f "$INPUT" ]; then
      echo "修复输入不存在: $INPUT" >&2
      exit 1
    fi
    ABS_PATH="$(cd "$(dirname "$INPUT")" && pwd -P)/$(basename "$INPUT")"
    echo "FIX_INPUT_TYPE=local-markdown"
    echo "FIX_INPUT_PATH=$ABS_PATH"
    echo "FIX_INPUT_EXISTS=true"
    ;;
  *)
    echo "无法识别修复输入来源: $INPUT" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 4: Implement the PowerShell mirror**

Create `scripts/phase6-detect-fix-input.ps1`:

```powershell
param(
  [Parameter(Mandatory=$true)]
  [string]$InputSource
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InputSource)) {
  Write-Error "修复输入不能为空"
  exit 1
}

if ($InputSource -match '^https?://.*(docx|docs)/') {
  Write-Output "FIX_INPUT_TYPE=feishu-doc"
  Write-Output "FIX_INPUT_URL=$InputSource"
  exit 0
}

if ($InputSource -match '^https?://.*base/') {
  Write-Output "FIX_INPUT_TYPE=feishu-base"
  Write-Output "FIX_INPUT_URL=$InputSource"
  exit 0
}

if ($InputSource -match '^base:([^:]+):([^:]+)$') {
  Write-Output "FIX_INPUT_TYPE=feishu-base-token"
  Write-Output "FEISHU_BASE_TOKEN=$($Matches[1])"
  Write-Output "FEISHU_TABLE_ID=$($Matches[2])"
  exit 0
}

if ($InputSource.EndsWith(".md")) {
  if (-not (Test-Path -LiteralPath $InputSource -PathType Leaf)) {
    Write-Error "修复输入不存在: $InputSource"
    exit 1
  }
  $Resolved = (Resolve-Path -LiteralPath $InputSource).Path
  Write-Output "FIX_INPUT_TYPE=local-markdown"
  Write-Output "FIX_INPUT_PATH=$Resolved"
  Write-Output "FIX_INPUT_EXISTS=true"
  exit 0
}

Write-Error "无法识别修复输入来源: $InputSource"
exit 1
```

- [ ] **Step 5: Run the test to verify it passes**

Run:

```bash
bash tests/test_phase6_detect_fix_input.sh
```

Expected: PASS with no output.

- [ ] **Step 6: Commit**

Run:

```bash
git add scripts/phase6-detect-fix-input.sh scripts/phase6-detect-fix-input.ps1 tests/test_phase6_detect_fix_input.sh
git commit -m "feat: detect code fixer input sources"
```

## Task 2: Phase 7 Superpowers Detection

**Files:**
- Create: `tests/test_phase7_detect_superpowers.sh`
- Create: `scripts/phase7-detect-superpowers.sh`
- Create: `scripts/phase7-detect-superpowers.ps1`

- [ ] **Step 1: Write the failing Bash test**

Create `tests/test_phase7_detect_superpowers.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase7 superpowers.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SKILL_ROOT="$TMP_DIR/skills"
mkdir -p "$SKILL_ROOT/brainstorming" "$SKILL_ROOT/test-driven-development" "$SKILL_ROOT/verification-before-completion"
printf '# brainstorming\n' > "$SKILL_ROOT/brainstorming/SKILL.md"
printf '# tdd\n' > "$SKILL_ROOT/test-driven-development/SKILL.md"
printf '# verification\n' > "$SKILL_ROOT/verification-before-completion/SKILL.md"

OUTPUT="$(SUPERPOWERS_SKILL_ROOTS="$SKILL_ROOT" bash "$ROOT_DIR/scripts/phase7-detect-superpowers.sh")"
echo "$OUTPUT" | grep -q "SUPERPOWERS_AVAILABLE=false"
echo "$OUTPUT" | grep -q "SUPERPOWER_SKILL:brainstorming=available"
echo "$OUTPUT" | grep -q "SUPERPOWER_SKILL:test-driven-development=available"
echo "$OUTPUT" | grep -q "SUPERPOWER_SKILL:using-git-worktrees=missing"
echo "$OUTPUT" | grep -q "SUPERPOWER_MISSING=using-git-worktrees,finishing-a-development-branch"

mkdir -p "$SKILL_ROOT/using-git-worktrees" "$SKILL_ROOT/finishing-a-development-branch"
printf '# worktrees\n' > "$SKILL_ROOT/using-git-worktrees/SKILL.md"
printf '# finishing\n' > "$SKILL_ROOT/finishing-a-development-branch/SKILL.md"

FULL_OUTPUT="$(SUPERPOWERS_SKILL_ROOTS="$SKILL_ROOT" bash "$ROOT_DIR/scripts/phase7-detect-superpowers.sh")"
echo "$FULL_OUTPUT" | grep -q "SUPERPOWERS_AVAILABLE=true"
echo "$FULL_OUTPUT" | grep -q "SUPERPOWER_MISSING=none"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/test_phase7_detect_superpowers.sh
```

Expected: FAIL because `scripts/phase7-detect-superpowers.sh` does not exist.

- [ ] **Step 3: Implement the Bash script**

Create `scripts/phase7-detect-superpowers.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOTS="${SUPERPOWERS_SKILL_ROOTS:-$HOME/.agents/skills:$HOME/.codex/skills:$HOME/.codex/skills/.system}"
REQUIRED_SKILLS=(
  "brainstorming"
  "using-git-worktrees"
  "test-driven-development"
  "verification-before-completion"
  "finishing-a-development-branch"
)

missing=()

skill_exists() {
  local skill="$1"
  local old_ifs="$IFS"
  IFS=':'
  for root in $ROOTS; do
    if [ -f "$root/$skill/SKILL.md" ]; then
      IFS="$old_ifs"
      return 0
    fi
  done
  IFS="$old_ifs"
  return 1
}

for skill in "${REQUIRED_SKILLS[@]}"; do
  if skill_exists "$skill"; then
    echo "SUPERPOWER_SKILL:$skill=available"
  else
    echo "SUPERPOWER_SKILL:$skill=missing"
    missing+=("$skill")
  fi
done

if [ "${#missing[@]}" -eq 0 ]; then
  echo "SUPERPOWERS_AVAILABLE=true"
  echo "SUPERPOWER_MISSING=none"
else
  echo "SUPERPOWERS_AVAILABLE=false"
  IFS=','
  echo "SUPERPOWER_MISSING=${missing[*]}"
fi
```

- [ ] **Step 4: Implement the PowerShell mirror**

Create `scripts/phase7-detect-superpowers.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$DefaultRoots = @(
  Join-Path $HOME ".agents/skills",
  Join-Path $HOME ".codex/skills",
  Join-Path $HOME ".codex/skills/.system"
)

if ($env:SUPERPOWERS_SKILL_ROOTS) {
  $Roots = $env:SUPERPOWERS_SKILL_ROOTS -split ';|:'
} else {
  $Roots = $DefaultRoots
}

$RequiredSkills = @(
  "brainstorming",
  "using-git-worktrees",
  "test-driven-development",
  "verification-before-completion",
  "finishing-a-development-branch"
)

$Missing = New-Object System.Collections.Generic.List[string]

foreach ($Skill in $RequiredSkills) {
  $Found = $false
  foreach ($Root in $Roots) {
    if (Test-Path -LiteralPath (Join-Path $Root "$Skill/SKILL.md") -PathType Leaf) {
      $Found = $true
      break
    }
  }

  if ($Found) {
    Write-Output "SUPERPOWER_SKILL:$Skill=available"
  } else {
    Write-Output "SUPERPOWER_SKILL:$Skill=missing"
    $Missing.Add($Skill)
  }
}

if ($Missing.Count -eq 0) {
  Write-Output "SUPERPOWERS_AVAILABLE=true"
  Write-Output "SUPERPOWER_MISSING=none"
} else {
  Write-Output "SUPERPOWERS_AVAILABLE=false"
  Write-Output "SUPERPOWER_MISSING=$($Missing -join ',')"
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:

```bash
bash tests/test_phase7_detect_superpowers.sh
```

Expected: PASS with no output.

- [ ] **Step 6: Commit**

Run:

```bash
git add scripts/phase7-detect-superpowers.sh scripts/phase7-detect-superpowers.ps1 tests/test_phase7_detect_superpowers.sh
git commit -m "feat: detect fixer superpowers workflow support"
```

## Task 3: Phase 8 Workspace Safety

**Files:**
- Create: `tests/test_phase8_prepare_fix_workspace.sh`
- Create: `scripts/phase8-prepare-fix-workspace.sh`
- Create: `scripts/phase8-prepare-fix-workspace.ps1`

- [ ] **Step 1: Write the failing Bash test**

Create `tests/test_phase8_prepare_fix_workspace.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phase8 workspace.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email test@example.com
git -C "$TMP_DIR" config user.name test
printf 'one\n' > "$TMP_DIR/A.java"
git -C "$TMP_DIR" add A.java
git -C "$TMP_DIR" commit -q -m "first"

CURRENT_BRANCH="$(git -C "$TMP_DIR" branch --show-current)"

CURRENT_OUTPUT="$(bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" current "")"
echo "$CURRENT_OUTPUT" | grep -q "FIX_WORKSPACE_MODE=current"
echo "$CURRENT_OUTPUT" | grep -q "FIX_WORKSPACE_PATH=$TMP_DIR"
echo "$CURRENT_OUTPUT" | grep -q "FIX_BRANCH=$CURRENT_BRANCH"

BRANCH_OUTPUT="$(bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" branch "fix/review-findings")"
echo "$BRANCH_OUTPUT" | grep -q "FIX_WORKSPACE_MODE=branch"
echo "$BRANCH_OUTPUT" | grep -q "FIX_BRANCH=fix/review-findings"
test "$(git -C "$TMP_DIR" branch --show-current)" = "fix/review-findings"

git -C "$TMP_DIR" switch -q "$CURRENT_BRANCH"
printf 'dirty\n' >> "$TMP_DIR/A.java"

DIRTY_OUTPUT="$TMP_DIR/phase8-dirty.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" branch "fix/dirty" >"$DIRTY_OUTPUT" 2>&1; then
  echo "phase8 should fail on dirty branch strategy" >&2
  exit 1
fi
grep -q "存在未提交改动" "$DIRTY_OUTPUT"

INVALID_OUTPUT="$TMP_DIR/phase8-invalid.out"
if bash "$ROOT_DIR/scripts/phase8-prepare-fix-workspace.sh" "$TMP_DIR" branch "bad branch name" >"$INVALID_OUTPUT" 2>&1; then
  echo "phase8 should fail for invalid branch name" >&2
  exit 1
fi
grep -q "非法修复分支名" "$INVALID_OUTPUT"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
bash tests/test_phase8_prepare_fix_workspace.sh
```

Expected: FAIL because `scripts/phase8-prepare-fix-workspace.sh` does not exist.

- [ ] **Step 3: Implement the Bash script**

Create `scripts/phase8-prepare-fix-workspace.sh`:

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${1:-}"
MODE="${2:-}"
REQUESTED_BRANCH="${3:-}"

if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "项目路径不存在: $PROJECT_DIR" >&2
  exit 1
fi

if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前项目不是 Git 仓库，fix 阶段需要 Git 工作区" >&2
  exit 1
fi

CURRENT_BRANCH="$(git -C "$PROJECT_DIR" branch --show-current)"
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="detached-head"
fi

is_dirty() {
  [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]
}

validate_branch() {
  local branch="$1"
  if [ -z "$branch" ]; then
    echo "修复分支名不能为空" >&2
    exit 1
  fi
  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    echo "非法修复分支名: $branch" >&2
    exit 1
  fi
}

case "$MODE" in
  current)
    echo "FIX_WORKSPACE_MODE=current"
    echo "FIX_WORKSPACE_PATH=$PROJECT_DIR"
    echo "FIX_BRANCH=$CURRENT_BRANCH"
    ;;
  branch)
    validate_branch "$REQUESTED_BRANCH"
    if is_dirty; then
      echo "存在未提交改动，不能在当前仓库直接创建修复分支" >&2
      exit 1
    fi
    if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$REQUESTED_BRANCH"; then
      git -C "$PROJECT_DIR" switch "$REQUESTED_BRANCH" >/dev/null
    else
      git -C "$PROJECT_DIR" switch -c "$REQUESTED_BRANCH" >/dev/null
    fi
    echo "FIX_WORKSPACE_MODE=branch"
    echo "FIX_WORKSPACE_PATH=$PROJECT_DIR"
    echo "FIX_BRANCH=$REQUESTED_BRANCH"
    ;;
  worktree)
    validate_branch "$REQUESTED_BRANCH"
    if is_dirty; then
      echo "存在未提交改动，不能从脏工作区创建修复 worktree" >&2
      exit 1
    fi
    PROJECT_NAME="$(basename "$PROJECT_DIR")"
    WORKTREE_ROOT="$PROJECT_DIR/.worktrees"
    WORKTREE_PATH="$WORKTREE_ROOT/$REQUESTED_BRANCH"
    mkdir -p "$WORKTREE_ROOT"
    if [ -e "$WORKTREE_PATH" ]; then
      echo "修复 worktree 已存在: $WORKTREE_PATH" >&2
      exit 1
    fi
    git -C "$PROJECT_DIR" worktree add "$WORKTREE_PATH" -b "$REQUESTED_BRANCH" >/dev/null
    echo "FIX_WORKSPACE_MODE=worktree"
    echo "FIX_WORKSPACE_PATH=$WORKTREE_PATH"
    echo "FIX_BRANCH=$REQUESTED_BRANCH"
    echo "FIX_WORKTREE_PROJECT=$PROJECT_NAME"
    ;;
  *)
    echo "未知工作区策略: $MODE" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 4: Implement the PowerShell mirror**

Create `scripts/phase8-prepare-fix-workspace.ps1`:

```powershell
param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectDir,

  [Parameter(Mandatory=$true)]
  [ValidateSet("current", "branch", "worktree")]
  [string]$Mode,

  [string]$RequestedBranch = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
  Write-Error "项目路径不存在: $ProjectDir"
  exit 1
}

git -C $ProjectDir rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Error "当前项目不是 Git 仓库，fix 阶段需要 Git 工作区"
  exit 1
}

$CurrentBranch = (git -C $ProjectDir branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($CurrentBranch)) {
  $CurrentBranch = "detached-head"
}

function Test-Dirty {
  $Status = (git -C $ProjectDir status --porcelain)
  return -not [string]::IsNullOrWhiteSpace($Status)
}

function Assert-BranchName {
  param([string]$Branch)

  if ([string]::IsNullOrWhiteSpace($Branch)) {
    Write-Error "修复分支名不能为空"
    exit 1
  }

  git check-ref-format --branch $Branch *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Error "非法修复分支名: $Branch"
    exit 1
  }
}

switch ($Mode) {
  "current" {
    Write-Output "FIX_WORKSPACE_MODE=current"
    Write-Output "FIX_WORKSPACE_PATH=$ProjectDir"
    Write-Output "FIX_BRANCH=$CurrentBranch"
  }
  "branch" {
    Assert-BranchName $RequestedBranch
    if (Test-Dirty) {
      Write-Error "存在未提交改动，不能在当前仓库直接创建修复分支"
      exit 1
    }

    git -C $ProjectDir show-ref --verify --quiet "refs/heads/$RequestedBranch"
    if ($LASTEXITCODE -eq 0) {
      git -C $ProjectDir switch $RequestedBranch *> $null
    } else {
      git -C $ProjectDir switch -c $RequestedBranch *> $null
    }

    Write-Output "FIX_WORKSPACE_MODE=branch"
    Write-Output "FIX_WORKSPACE_PATH=$ProjectDir"
    Write-Output "FIX_BRANCH=$RequestedBranch"
  }
  "worktree" {
    Assert-BranchName $RequestedBranch
    if (Test-Dirty) {
      Write-Error "存在未提交改动，不能从脏工作区创建修复 worktree"
      exit 1
    }

    $ProjectName = Split-Path -Leaf $ProjectDir
    $WorktreeRoot = Join-Path $ProjectDir ".worktrees"
    $WorktreePath = Join-Path $WorktreeRoot $RequestedBranch
    New-Item -ItemType Directory -Force -Path $WorktreeRoot *> $null

    if (Test-Path -LiteralPath $WorktreePath) {
      Write-Error "修复 worktree 已存在: $WorktreePath"
      exit 1
    }

    git -C $ProjectDir worktree add $WorktreePath -b $RequestedBranch *> $null

    Write-Output "FIX_WORKSPACE_MODE=worktree"
    Write-Output "FIX_WORKSPACE_PATH=$WorktreePath"
    Write-Output "FIX_BRANCH=$RequestedBranch"
    Write-Output "FIX_WORKTREE_PROJECT=$ProjectName"
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:

```bash
bash tests/test_phase8_prepare_fix_workspace.sh
```

Expected: PASS with no output.

- [ ] **Step 6: Commit**

Run:

```bash
git add scripts/phase8-prepare-fix-workspace.sh scripts/phase8-prepare-fix-workspace.ps1 tests/test_phase8_prepare_fix_workspace.sh
git commit -m "feat: prepare safe fixer workspaces"
```

## Task 4: Fix Reference Documents

**Files:**
- Create: `references/fix-workflow.md`
- Create: `references/fix-report-format.md`
- Create: `references/fix-feishu-integration.md`
- Create: `references/fix-examples.md`

- [ ] **Step 1: Write the failing contract checks**

Modify `tests/test_contract_docs.sh` by adding these variables near the existing file variables:

```bash
FIX_SKILL_FILE="$ROOT_DIR/skills/cc-code-fixer/SKILL.md"
FIX_AGENT_FILE="$ROOT_DIR/agents/cc-code-fixer.md"
FIX_WORKFLOW_FILE="$ROOT_DIR/references/fix-workflow.md"
FIX_REPORT_FILE="$ROOT_DIR/references/fix-report-format.md"
FIX_FEISHU_FILE="$ROOT_DIR/references/fix-feishu-integration.md"
FIX_EXAMPLES_FILE="$ROOT_DIR/references/fix-examples.md"
```

Add these checks after the existing scan-stage checks:

```bash
grep -q "cc-code-fixer" "$README_FILE"
grep -q "scan/fix" "$README_FILE"

grep -q "## Fix Input Normalization" "$FIX_WORKFLOW_FILE"
grep -q "brainstorming" "$FIX_WORKFLOW_FILE"
grep -q "test-driven-development" "$FIX_WORKFLOW_FILE"
grep -q "verification-before-completion" "$FIX_WORKFLOW_FILE"
grep -q "degraded mode" "$FIX_WORKFLOW_FILE"

grep -q "## 修复配置快照" "$FIX_REPORT_FILE"
grep -q "## 已修复问题" "$FIX_REPORT_FILE"
grep -q "## 未修复问题" "$FIX_REPORT_FILE"
grep -q "## 验证命令与结果" "$FIX_REPORT_FILE"

grep -q "修复状态" "$FIX_FEISHU_FILE"
grep -q "修复时间" "$FIX_FEISHU_FILE"
grep -q "修复分支" "$FIX_FEISHU_FILE"
grep -q "lark-cli base" "$FIX_FEISHU_FILE"

grep -q "本地 Markdown 报告" "$FIX_EXAMPLES_FILE"
grep -q "飞书多维表格" "$FIX_EXAMPLES_FILE"
grep -q "快速启动参数校验失败" "$FIX_EXAMPLES_FILE"
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: FAIL because the fix reference files do not exist.

- [ ] **Step 3: Create `references/fix-workflow.md`**

Include these exact sections:

```markdown
# Fix Workflow

## Fix Input Normalization

The fix skill converts local Markdown reports, Feishu cloud documents, and Feishu Base records into one normalized issue list. The required fields are `issue_id`, `severity`, `dimension`, `location`, `confidence`, `evidence`, `impact`, `suggestion`, `source_type`, `source_ref`, and `fix_status`.

## Preflight Sequence

The skill runs phase6 input detection, phase1 project detection, phase2 branch detection, phase3 project scan, phase4 lark-cli detection, and phase7 Superpowers detection before asking the user any fix-plan questions.

## Superpowers Flow

When available, the fixer follows `brainstorming`, `using-git-worktrees`, `test-driven-development`, `verification-before-completion`, and `finishing-a-development-branch` in that order.

## Degraded Mode

If one or more Superpowers skills are missing, the skill reports degraded mode and keeps the same safety gates locally: explicit plan confirmation, dirty workspace protection, test-first behavior for behavior fixes, fresh verification, and a final branch handoff.

## Fix Scope Rules

The fixer repairs only selected severities, dimensions, or issue IDs. Findings marked `已修复` are excluded by default. Findings with low confidence or `待确认` are not changed unless explicitly selected and verified.

## Workspace Rules

The recommended strategy is an isolated worktree. Branch and current-checkout strategies require a clean Git working tree before branch changes.
```

- [ ] **Step 4: Create `references/fix-report-format.md`**

Include these exact sections:

```markdown
# 修复报告格式规范

## 修复配置快照

必须展示项目路径、工作区路径、修复分支、输入来源、修复范围、修复维度、修复策略、输出选项和 Superpowers 可用性。

## 修复输入摘要

必须展示原审查报告来源、选中问题数、跳过问题数、已修复问题数和待确认问题数。

## 已修复问题

每条包含问题编号、原始位置、修复方式、涉及文件、测试证据和验证结果。

## 部分修复问题

每条包含问题编号、已完成部分、未完成部分、阻塞原因和建议下一步。

## 未修复问题

每条包含问题编号、未修复原因、是否需要人工确认、建议验证方式。

## 测试变更

列出新增测试、修改测试、未新增测试的合理原因。

## 验证命令与结果

记录每条实际运行的命令、退出码、关键输出摘要。不得声称未运行的命令通过。

## 代码变更摘要

按文件列出主要改动和关联问题编号。

## 飞书回写结果

展示云文档链接、多维表格更新结果或失败原因。

## 后续建议

列出剩余风险、建议继续审查或人工确认的事项。
```

- [ ] **Step 5: Create `references/fix-feishu-integration.md`**

Include command references for:

```markdown
# Fix Feishu Integration

## 读取飞书云文档

通过 `lark-cli docs +fetch` 获取前一阶段云文档内容，再按 Markdown 报告格式解析。

## 读取飞书多维表格

通过 `lark-cli base +record-list` 读取原问题清单。必须读取字段 `问题编号`, `严重级别`, `所属维度`, `位置`, `置信度`, `证据`, `影响`, `修复建议`, `修复状态`, `修复时间`, `修复分支`, `修复人`, `备注`。

## 更新飞书多维表格

通过 `lark-cli base +record-update` 更新原记录。默认只更新 `修复状态`, `修复时间`, `修复分支`, `备注`。不新增字段。

## 创建修复报告云文档

通过 `lark-cli docs +create --markdown @{FIX_REPORT_FILENAME}` 创建修复报告文档。命令必须在报告文件所在目录执行。

## 失败降级

飞书读取失败时停止修复并说明原因。飞书回写失败时保留本地修复报告和代码改动，并在最终汇总中展示失败原因。
```

- [ ] **Step 6: Create `references/fix-examples.md`**

Include examples for:

```markdown
# Fix Examples

## 本地 Markdown 报告

`/cc-code-reviewer:cc-code-fixer /path/to/code-review-report-demo.md --project /path/to/project`

## 飞书多维表格

`/cc-code-reviewer:cc-code-fixer https://example.feishu.cn/base/BASE123 --project /path/to/project`

## 快速启动

`/cc-code-reviewer:cc-code-fixer /path/to/report.md --project /path/to/project --severity P0,P1 --workspace worktree --strategy standard --upload no --branch fix/review-findings`

## 快速启动参数校验失败

缺少 `--project`, `--workspace`, `--strategy`, 或缺少 `--severity`、`--dimensions`、`--issues` 中任意一个时，输出参数校验失败并终止。
```

- [ ] **Step 7: Run the contract test to verify it passes for references**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: still FAIL because the skill and agent are not created yet, but the reference-file greps should no longer be the failure source.

- [ ] **Step 8: Commit**

Run:

```bash
git add references/fix-workflow.md references/fix-report-format.md references/fix-feishu-integration.md references/fix-examples.md tests/test_contract_docs.sh
git commit -m "docs: add code fixer workflow references"
```

## Task 5: Fix Skill Entry Point

**Files:**
- Create: `skills/cc-code-fixer/SKILL.md`
- Modify: `tests/test_contract_docs.sh`

- [ ] **Step 1: Add failing contract checks for the skill**

Add these checks to `tests/test_contract_docs.sh`:

```bash
grep -q "模式判定" "$FIX_SKILL_FILE"
grep -q "phase6-detect-fix-input" "$FIX_SKILL_FILE"
grep -q "phase7-detect-superpowers" "$FIX_SKILL_FILE"
grep -q "修复输入解析完成" "$FIX_SKILL_FILE"
grep -q "AskUserQuestion" "$FIX_SKILL_FILE"
grep -q "工作区策略" "$FIX_SKILL_FILE"
grep -q "修复范围" "$FIX_SKILL_FILE"
grep -q "修复策略" "$FIX_SKILL_FILE"
grep -q "确认执行计划" "$FIX_SKILL_FILE"
grep -q "禁止降级为交互式模式" "$FIX_SKILL_FILE"
grep -q "cc-code-reviewer:cc-code-fixer" "$FIX_SKILL_FILE"
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: FAIL because `skills/cc-code-fixer/SKILL.md` does not exist.

- [ ] **Step 3: Create the skill document**

Create `skills/cc-code-fixer/SKILL.md` with these sections and rules:

```markdown
---
description: Java 审查问题修复 - 基于审查报告执行 TDD 修复、验证和修复报告生成
---

## 执行算法（最高优先级，必须严格按此顺序执行）

### 第一步：模式判定

检测用户输入中是否包含 `--severity`, `--dimensions`, `--issues`, `--workspace`, `--strategy`, `--upload`, 或 `--branch`。包含任意一个即进入快速启动模式；否则进入交互式模式。

### 第二步：提取修复输入和项目路径

必须提取 `<review-source>` 和 `--project`。无法识别时立即终止。

### 第三步：预检测

按顺序执行 phase6-detect-fix-input、phase1-detect-project、phase2-detect-branches、phase3-project-scan、phase4-detect-lark-plugin、phase7-detect-superpowers。预检测阶段禁止 AskUserQuestion。

### 第四步：输出修复输入解析完成摘要

必须展示审查报告来源、项目路径、Git 状态、Superpowers 状态、可修复问题统计和已修复或跳过统计。

### 第五步：参数收集

交互式模式必须逐步调用 AskUserQuestion，依次收集工作区策略、修复范围、修复维度、修复策略、输出目标和确认执行计划。快速启动模式必须校验参数完整性，失败时输出错误并终止，禁止降级为交互式模式。

### 第六步：Superpowers 设计与工作区准备

如果 Superpowers 可用，将归一化问题清单注入 brainstorming 生成修复设计。根据用户选择调用工作区准备逻辑。

### 第七步：调用子 agent 执行修复

使用 Task 工具启动 `cc-code-reviewer:cc-code-fixer`，注入修复任务参数、归一化问题清单、用户确认计划和项目预扫描结果。

## 交互式确认步骤定义

每一步必须单独调用 AskUserQuestion 并等待用户响应。不得合并多个问题。

### 步骤 1：选择工作区策略

选项：新建 isolated worktree（推荐）、当前仓库新建 fix 分支、当前分支直接修复。

### 步骤 2：选择修复范围

多选：P0、P1、P2、P3、待确认、自定义问题编号。选择自定义问题编号时追加一次交互收集逗号分隔编号。

### 步骤 3：选择修复维度

多选：从归一化问题清单中的维度动态生成。

### 步骤 4：选择修复策略

选项：conservative、standard、deep。

### 步骤 5：选择输出目标

选项：仅本地 Markdown、上传飞书云文档、更新原飞书多维表格、同时云文档和多维表格。

### 步骤 6：确认执行计划

展示完整执行计划后调用 AskUserQuestion，选项为确认执行和取消。

## 快速启动模式参数规范

快速启动必须提供 review-source、--project、--workspace、--strategy，并提供 --severity、--dimensions、--issues 中至少一个。校验失败时展示已识别参数、缺少必填参数、非法参数值和正确示例。

## 子 agent 调用规范

subagent_type: `cc-code-reviewer:cc-code-fixer`
description: `执行 Java 审查问题修复`

注入章节包括修复任务参数、归一化问题清单、用户确认的修复计划和项目预扫描结果。
```

- [ ] **Step 4: Run the contract test to verify it passes for the skill**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: still FAIL because the fixer agent is not created yet.

- [ ] **Step 5: Commit**

Run:

```bash
git add skills/cc-code-fixer/SKILL.md tests/test_contract_docs.sh
git commit -m "feat: add code fixer skill contract"
```

## Task 6: Fixer Agent

**Files:**
- Create: `agents/cc-code-fixer.md`
- Modify: `tests/test_contract_docs.sh`

- [ ] **Step 1: Add failing contract checks for the agent**

Add these checks to `tests/test_contract_docs.sh`:

```bash
grep -q "修复任务参数" "$FIX_AGENT_FILE"
grep -q "不得再次询问用户" "$FIX_AGENT_FILE"
grep -q "test-driven-development" "$FIX_AGENT_FILE"
grep -q "先写失败测试" "$FIX_AGENT_FILE"
grep -q "verification-before-completion" "$FIX_AGENT_FILE"
grep -q "fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$FIX_AGENT_FILE"
grep -q "修复状态" "$FIX_AGENT_FILE"
grep -q "不得修复注入范围之外的问题" "$FIX_AGENT_FILE"
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: FAIL because `agents/cc-code-fixer.md` does not exist.

- [ ] **Step 3: Create the fixer agent**

Create `agents/cc-code-fixer.md` with these sections:

```markdown
---
name: cc-code-fixer
description: 执行 Java 审查问题修复的专属子代理，按用户确认范围进行 TDD 修复、验证和报告生成
model: sonnet
effort: high
maxTurns: 80
---

你是一位资深 Java 修复工程师。你的使命是基于上一阶段审查报告，修复用户明确选择的问题，补充测试，运行验证，并生成结构化修复报告。

## 外部参数注入

你收到 `修复任务参数`、`归一化问题清单`、`用户确认的修复计划` 和 `项目预扫描结果`。你必须直接使用这些参数，不得再次询问用户。

## 硬性规则

- 不得修复注入范围之外的问题。
- 不得再次询问用户或调用交互工具。
- 行为变更必须遵守 test-driven-development：先写失败测试，确认失败，再实现修复，再确认通过。
- 完成声明必须遵守 verification-before-completion：运行新鲜验证命令并读取结果后才能声明通过。
- 对无法复现、低置信度或待确认问题，记录为 `needs human confirmation` 或 `not fixed`，不要强行改代码。
- 不得回滚用户已有改动。

## 执行流程

1. 解析选中问题并按 P0、P1、P2、P3、待确认排序。
2. 为每个行为缺陷写最小失败测试。
3. 运行测试并确认失败原因正确。
4. 实现最小修复。
5. 运行相关测试和项目级验证命令。
6. 更新每个问题状态：fixed、partially fixed、not fixed、not applicable、needs human confirmation。
7. 生成 `fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md`。
8. 按输出选项创建飞书文档或更新多维表格。

## 修复报告

修复报告格式必须遵循 `../references/fix-report-format.md`。

## 飞书回写

飞书操作必须遵循 `../references/fix-feishu-integration.md`。默认只更新现有字段 `修复状态`、`修复时间`、`修复分支`、`备注`。

## 最终汇总

最终输出必须包含修复报告路径、修复数量、未修复数量、验证命令结果、修复分支和飞书链接或失败原因。
```

- [ ] **Step 4: Run the contract test to verify it passes**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add agents/cc-code-fixer.md tests/test_contract_docs.sh
git commit -m "feat: add code fixer agent contract"
```

## Task 7: README and Plugin Metadata

**Files:**
- Modify: `README.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `tests/test_contract_docs.sh`

- [ ] **Step 1: Add failing docs and metadata checks**

Add these checks to `tests/test_contract_docs.sh`:

```bash
grep -q "/cc-code-reviewer:cc-code-fixer" "$README_FILE"
grep -q "修复阶段" "$README_FILE"
grep -q "worktree" "$README_FILE"
grep -q "fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md" "$README_FILE"
grep -q "code-fixer" "$PLUGIN_FILE"
grep -q "fix" "$MARKETPLACE_FILE"
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: FAIL because README and metadata do not yet mention fixer capability.

- [ ] **Step 3: Update README**

Add a "修复阶段" section after the current usage section:

````markdown
## 修复阶段

扫描阶段生成本地 Markdown、飞书云文档或飞书多维表格后，可以使用 `cc-code-fixer` 进入修复阶段。

```text
/cc-code-reviewer:cc-code-fixer /path/to/code-review-report-demo.md --project /path/to/project
```

修复阶段会先解析审查报告，展示可修复问题摘要，再引导你选择工作区策略、修复范围、修复维度、修复策略和输出目标。默认推荐新建 isolated worktree，避免污染当前分支。

快速启动示例：

```text
/cc-code-reviewer:cc-code-fixer /path/to/report.md --project /path/to/project --severity P0,P1 --workspace worktree --strategy standard --upload no --branch fix/review-findings
```

修复完成后会生成 `fix-report-{PROJECT_NAME}-{YYYYMMDD-HHmmss}.md`，并可按需创建飞书云文档或更新原飞书多维表格中的修复状态。
````

- [ ] **Step 4: Update plugin metadata**

Update `.claude-plugin/plugin.json` description to mention review and fix:

```json
"description": "Java 代码审查与修复插件 - 15维度智能审查，支持基于报告的 TDD 修复流程"
```

Update `.claude-plugin/marketplace.json` plugin description and tags to include fix:

```json
"description": "AI-powered Java code review and report-driven fixing with TDD workflow support",
"tags": ["java", "code-review", "code-fix", "quality", "security"]
```

Bump both metadata files from `1.0.1` to `1.1.0` because this adds a new user-facing skill.

- [ ] **Step 5: Run the contract test**

Run:

```bash
bash tests/test_contract_docs.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git add README.md .claude-plugin/plugin.json .claude-plugin/marketplace.json tests/test_contract_docs.sh
git commit -m "docs: document code fixer usage"
```

## Task 8: Full Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run the full suite**

Run:

```bash
bash tests/run_all.sh
```

Expected:

```text
All tests passed.
```

- [ ] **Step 2: Inspect final status**

Run:

```bash
git status --short
```

Expected: no unstaged changes. If there are generated or intentional uncommitted files, commit them before finishing.

- [ ] **Step 3: Final commit if verification required formatting changes**

If Step 1 or Step 2 led to any fixes, commit them:

```bash
git add -A
git commit -m "test: verify code fixer workflow"
```

Expected: either a new verification-fix commit or no commit needed because the worktree is clean.

## Self-Review Checklist

- Every file in the approved design has a task.
- Every new Bash script has a Bash test.
- Every new skill, agent, and reference document has a contract assertion.
- The plan keeps scan and fix as separate skill entry points.
- Fast mode has explicit validation and does not fall back to interaction.
- Superpowers integration is represented in both workflow docs and agent rules.
- Feishu update uses existing fields by default and does not add Base fields.
- Final verification uses `bash tests/run_all.sh`.
