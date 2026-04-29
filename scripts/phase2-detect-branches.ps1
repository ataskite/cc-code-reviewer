# 阶段二：Git 分支探测与选择
# 用途：检测 Git 仓库的分支信息

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir
)

$ErrorActionPreference = "Stop"

$isGitRepo = $false
try {
    $result = git -C $ProjectDir rev-parse --is-inside-work-tree 2>&1
    if ($result -eq "true") { $isGitRepo = $true }
} catch {}

if ($isGitRepo) {
    Write-Output "IS_GIT_REPO=true"
    $currentBranch = git -C $ProjectDir branch --show-current 2>$null
    Write-Output "CURRENT_BRANCH=$currentBranch"
    Write-Output ""

    # 主动获取远程分支信息（仅更新引用，不下载内容）
    git -C $ProjectDir fetch --no-tags --quiet 2>$null

    # 列出本地分支，按最近提交时间排序（最多10个）
    Write-Output "=== 本地分支 ==="
    $localBranches = git -C $ProjectDir for-each-ref --sort=-committerdate `
        --format='BRANCH: %(refname:short) | %(committerdate:format:%Y-%m-%d %H:%M:%S) | %(subject)' refs/heads/ 2>$null
    $localTotal = 0
    if ($localBranches) {
        $localArray = @($localBranches)
        $localTotal = $localArray.Count
        $localArray | Select-Object -First 10 | ForEach-Object { Write-Output $_ }
    }
    if ($localTotal -gt 10) {
        Write-Output "（共 $localTotal 个本地分支，仅展示最近 10 个）"
    }

    # 列出远程分支（排除 origin/HEAD 和 origin 本身）
    Write-Output ""
    Write-Output "=== 远程分支 ==="
    $remoteRefs = git -C $ProjectDir for-each-ref --sort=-committerdate `
        --format='%(refname:short)' refs/remotes/ 2>$null
    $remoteTotal = 0
    if ($remoteRefs) {
        $remoteArray = @($remoteRefs | Where-Object { $_ -notmatch '/HEAD$' })
        $remoteTotal = $remoteArray.Count
        $remoteArray | Select-Object -First 10 | ForEach-Object {
            $ref = $_
            $shortName = $ref -replace '^origin/', ''
            $date = git -C $ProjectDir log -1 --format='%cd' --date='format:%Y-%m-%d %H:%M:%S' $ref 2>$null
            $subjectRaw = git -C $ProjectDir log -1 --format='%s' $ref 2>$null
            if (-not $subjectRaw) { $subjectRaw = "" }
            $subject = $subjectRaw.Substring(0, [Math]::Min(30, $subjectRaw.Length))
            Write-Output "BRANCH_REMOTE: $ref | $date | $subject"
        }
    }
    if ($remoteTotal -gt 10) {
        Write-Output "（共 $remoteTotal 个远程分支，仅展示最近 10 个）"
    }
} else {
    Write-Output "IS_GIT_REPO=false"
}
