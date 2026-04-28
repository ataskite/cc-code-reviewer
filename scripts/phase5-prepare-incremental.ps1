# 阶段五：代码审查 - 增量审查预处理
# 用途：获取提交记录、变更文件列表和变更统计

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir,

    [Parameter(Mandatory=$true)]
    [int]$CommitCount
)

$ErrorActionPreference = "Stop"

# 防止 HEAD~N 越界：获取实际提交数
$totalCommits = 0
try {
    $totalCommits = [int](git -C $ProjectDir rev-list --count HEAD 2>$null)
} catch {}

if ($totalCommits -lt $CommitCount) {
    Write-Output "⚠️ 项目仅有 $totalCommits 次提交，将使用实际数量"
    $CommitCount = $totalCommits
}

Write-Output "# === 提交记录 ==="
if ($CommitCount -eq 0) {
    Write-Output "（无提交记录）"
} else {
    git -C $ProjectDir log --oneline "-$CommitCount"
}

Write-Output ""
Write-Output "# === 变更文件列表 ==="
if ($CommitCount -eq 0) {
    Write-Output "（无提交记录）"
} elseif ($totalCommits -eq 1) {
    git -C $ProjectDir show --format="" --name-only HEAD
} else {
    git -C $ProjectDir diff --name-only "HEAD~$CommitCount..HEAD"
}

Write-Output ""
Write-Output "# === 变更统计 ==="
if ($CommitCount -eq 0) {
    Write-Output "（无变更）"
} elseif ($totalCommits -eq 1) {
    git -C $ProjectDir show --stat --format="" HEAD
} else {
    git -C $ProjectDir diff --stat "HEAD~$CommitCount..HEAD"
}
