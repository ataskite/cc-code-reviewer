$ErrorActionPreference = "Stop"

$DefaultRoots = @(
  (Join-Path $HOME ".agents/skills"),
  (Join-Path $HOME ".codex/skills"),
  (Join-Path $HOME ".codex/skills/.system")
)

if ($env:SUPERPOWERS_SKILL_ROOTS) {
  # Prefer semicolon lists on Windows so drive letters such as C:\skills are preserved.
  if ($env:SUPERPOWERS_SKILL_ROOTS.Contains(";")) {
    $Roots = $env:SUPERPOWERS_SKILL_ROOTS -split ';'
  } else {
    $Roots = $env:SUPERPOWERS_SKILL_ROOTS -split ':'
  }
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
    if ([string]::IsNullOrWhiteSpace($Root)) {
      continue
    }

    if (Test-Path -LiteralPath (Join-Path $Root "$Skill/SKILL.md") -PathType Leaf) {
      $Found = $true
      break
    }
  }

  if ($Found) {
    Write-Output "SUPERPOWER_SKILL:$Skill=available"
  } else {
    Write-Output "SUPERPOWER_SKILL:$Skill=missing"
    $Missing.Add($Skill) | Out-Null
  }
}

if ($Missing.Count -eq 0) {
  Write-Output "SUPERPOWERS_AVAILABLE=true"
  Write-Output "SUPERPOWER_MISSING=none"
} else {
  Write-Output "SUPERPOWERS_AVAILABLE=false"
  Write-Output "SUPERPOWER_MISSING=$($Missing -join ',')"
}
