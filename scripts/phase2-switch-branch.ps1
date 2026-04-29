# 阶段二：Git 分支切换
# 用途：切换到用户选择的分支（支持本地和远程分支）

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir,

    [Parameter(Mandatory=$true)]
    [string]$TargetBranch,

    [Parameter(Mandatory=$true)]
    [string]$CurrentBranch,

    [string]$ProjectSource = "unknown"
)

$ErrorActionPreference = "Stop"

function Invoke-GitChecked {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Arguments
    )

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') 失败（exit $LASTEXITCODE）: $($output -join [Environment]::NewLine)"
    }
    return $output
}

# 如果目标分支就是当前分支，无需切换
if ($TargetBranch -eq $CurrentBranch) {
    Write-Output "✅ 已在目标分支: $CurrentBranch"
    exit 0
}

# 去掉 origin/ 前缀，获取短分支名
$shortBranch = $TargetBranch -replace '^origin/', ''

Write-Output "正在切换到分支: $shortBranch"

# 本地项目目录可能承载用户的在途改动，此时不主动切分支
if ($ProjectSource -eq "local") {
    $dirtyStatus = git -C $ProjectDir status --porcelain 2>$null
    if ($dirtyStatus) {
        Write-Output "⚠️ 检测到本地项目目录存在未提交改动，为避免影响当前工作区，将继续使用当前分支 $CurrentBranch 审查"
        exit 1
    }
}

# 检查本地分支是否存在
$localExists = $false
try {
    git -C $ProjectDir show-ref --verify --quiet "refs/heads/$shortBranch" 2>$null
    if ($LASTEXITCODE -eq 0) { $localExists = $true }
} catch {}

# 检查远程分支是否存在
$remoteExists = $false
try {
    git -C $ProjectDir show-ref --verify --quiet "refs/remotes/origin/$shortBranch" 2>$null
    if ($LASTEXITCODE -eq 0) { $remoteExists = $true }
} catch {}

if ($localExists) {
    # 本地分支存在，直接切换
    try {
        Invoke-GitChecked -Arguments @("-C", $ProjectDir, "checkout", $shortBranch) | Out-Null
        Write-Output "✅ 已切换到本地分支: $shortBranch"
    } catch {
        Write-Output "⚠️ 分支切换失败，将使用当前分支 $CurrentBranch 继续审查"
        exit 1
    }
} elseif ($remoteExists) {
    # 远程分支存在，先 fetch 再切换
    Write-Output "检测到远程分支，正在拉取最新代码..."
    try {
        Invoke-GitChecked -Arguments @("-C", $ProjectDir, "fetch", "origin", $shortBranch) | Out-Null
        Invoke-GitChecked -Arguments @("-C", $ProjectDir, "checkout", $shortBranch) | Out-Null
        Write-Output "✅ 已切换到远程分支: $shortBranch"
    } catch {
        Write-Output "⚠️ 分支切换失败，将使用当前分支 $CurrentBranch 继续审查"
        exit 1
    }
} else {
    Write-Output "⚠️ 分支 '$shortBranch' 不存在（本地或远程均未找到），将使用当前分支 $CurrentBranch 继续审查"
    exit 1
}
