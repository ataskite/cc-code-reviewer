# 阶段四：lark-cli 检测
# 用途：检测系统是否安装 lark-cli 命令行工具

$ErrorActionPreference = "Stop"

function Has-Skill {
    param([string]$SkillName)
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    $paths = @(
        (Join-Path $homeDir ".agents" "skills" $SkillName),
        (Join-Path $homeDir ".codex" "skills" $SkillName),
        (Join-Path $homeDir ".claude" "skills" $SkillName)
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    return $false
}

$larkPath = $null
try {
    $larkPath = (Get-Command lark-cli -ErrorAction SilentlyContinue).Path
} catch {}

if (-not $larkPath) {
    Write-Output "LARK_PLUGIN_INSTALLED=false"
    Write-Output "LARK_PLUGIN_REASON=lark-cli命令未安装"
} else {
    $versionOk = $false
    try {
        & $larkPath --version 2>$null | Out-Null
        $versionOk = $true
    } catch {}

    if (-not $versionOk) {
        Write-Output "LARK_PLUGIN_INSTALLED=false"
        Write-Output "LARK_PLUGIN_REASON=lark-cli命令不可执行"
    } elseif ((Has-Skill "lark-doc") -and (Has-Skill "lark-base")) {
        Write-Output "LARK_PLUGIN_INSTALLED=true"
        Write-Output "LARK_PLUGIN_NAME=lark-cli"
        Write-Output "LARK_CLI_PATH=$larkPath"
        Write-Output "LARK_SKILLS_INSTALLED=true"
    } else {
        Write-Output "LARK_PLUGIN_INSTALLED=false"
        Write-Output "LARK_PLUGIN_REASON=缺少lark-doc或lark-base技能"
    }
}
