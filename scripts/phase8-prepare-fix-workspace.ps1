param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectDir,

  [Parameter(Mandatory=$true)]
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
  $Status = git -C $ProjectDir status --porcelain
  return -not [string]::IsNullOrWhiteSpace(($Status -join [Environment]::NewLine))
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

function Ensure-WorktreesIgnored {
  $ExcludeFile = (git -C $ProjectDir rev-parse --git-path info/exclude).Trim()
  if (-not [System.IO.Path]::IsPathRooted($ExcludeFile)) {
    $ExcludeFile = Join-Path $ProjectDir $ExcludeFile
  }
  $ExcludeDir = Split-Path -Parent $ExcludeFile
  New-Item -ItemType Directory -Force -Path $ExcludeDir *> $null

  if (-not (Test-Path -LiteralPath $ExcludeFile -PathType Leaf)) {
    New-Item -ItemType File -Path $ExcludeFile *> $null
  }

  $ExistingPatterns = Get-Content -LiteralPath $ExcludeFile
  if ($ExistingPatterns -notcontains ".worktrees/") {
    Add-Content -LiteralPath $ExcludeFile -Value ""
    Add-Content -LiteralPath $ExcludeFile -Value ".worktrees/"
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
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    Write-Output "FIX_WORKSPACE_MODE=branch"
    Write-Output "FIX_WORKSPACE_PATH=$ProjectDir"
    Write-Output "FIX_BRANCH=$RequestedBranch"
  }
  "worktree" {
    Assert-BranchName $RequestedBranch
    $ProjectName = Split-Path -Leaf $ProjectDir
    $WorktreeRoot = Join-Path $ProjectDir ".worktrees"
    $WorktreePath = Join-Path $WorktreeRoot $RequestedBranch

    if (Test-Path -LiteralPath $WorktreePath) {
      Write-Error "修复 worktree 已存在: $WorktreePath"
      exit 1
    }

    if (Test-Dirty) {
      Write-Error "存在未提交改动，不能从脏工作区创建修复 worktree"
      exit 1
    }

    Ensure-WorktreesIgnored
    New-Item -ItemType Directory -Force -Path $WorktreeRoot *> $null

    git -C $ProjectDir show-ref --verify --quiet "refs/heads/$RequestedBranch"
    if ($LASTEXITCODE -eq 0) {
      git -C $ProjectDir worktree add $WorktreePath $RequestedBranch *> $null
    } else {
      git -C $ProjectDir worktree add $WorktreePath -b $RequestedBranch *> $null
    }
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }

    Write-Output "FIX_WORKSPACE_MODE=worktree"
    Write-Output "FIX_WORKSPACE_PATH=$WorktreePath"
    Write-Output "FIX_BRANCH=$RequestedBranch"
    Write-Output "FIX_WORKTREE_PROJECT=$ProjectName"
  }
  default {
    Write-Error "未知工作区策略: $Mode"
    exit 1
  }
}
