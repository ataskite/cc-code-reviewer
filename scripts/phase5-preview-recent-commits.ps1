# 阶段五：代码审查 - 增量审查提交预览
# 用途：展示最近 10 次提交，帮助用户选择增量审查范围

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir
)

$ErrorActionPreference = "Stop"
$previewCount = 10

$totalCommits = 0
try {
    $totalCommits = [int](git -C $ProjectDir rev-list --count HEAD 2>$null)
} catch {}

Write-Output "# === 最近提交预览 ==="
if ($totalCommits -eq 0) {
    Write-Output "（无提交记录）"
} else {
    $index = 1
    git -C $ProjectDir log --pretty=format:'%h %s' "-$previewCount" | ForEach-Object {
        Write-Output "$index. $_"
        $index += 1
    }
}
