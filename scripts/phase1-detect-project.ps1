# 阶段一：项目识别与准备
# 用途：识别用户提供的路径类型，Git仓库克隆到本地缓存目录
# 缓存策略：相同仓库只克隆一次，后续自动 pull 更新，避免重复克隆

param(
    [Parameter(Mandatory=$true)]
    [string]$InputPath
)

$ErrorActionPreference = "Stop"

# 本地缓存目录：使用系统临时目录
$CODE_DIR = $env:TEMP

# 识别规则：以http://、https://、git://或git@开头的URL → Git仓库
if ($InputPath -match '^https?://' -or $InputPath -match '^git://' -or $InputPath -match '^git@') {
    # 从 URL 中提取仓库名作为缓存目录名
    # https://github.com/org/repo.git → org_repo
    # git@github.com:org/repo.git → org_repo
    $repoName = $InputPath -replace '\.git$', '' -replace '^.*://', '' -replace '^.*@', '' -replace ':', '/' -replace '^.*/([^/]+/[^/]+)$', '$1' -replace '/', '_'
    $cacheDir = Join-Path $CODE_DIR $repoName

    if (Test-Path (Join-Path $cacheDir ".git")) {
        # 缓存已存在，pull 更新
        Write-Output "检测到Git仓库（缓存命中），正在拉取最新代码..."
        $currentBranch = git -C $cacheDir branch --show-current 2>$null
        try {
            git -C $cacheDir pull 2>&1 | Out-Null
            Write-Output "✅ 已更新到最新: $cacheDir (分支: $currentBranch)"
            $PROJECT_DIR = $cacheDir
            $PROJECT_SOURCE = "git-cache"
        } catch {
            Write-Output "⚠️ 拉取失败，删除缓存并重新克隆..."
            Remove-Item -Recurse -Force $cacheDir
            try {
                git clone $InputPath $cacheDir 2>&1 | Out-Null
                Write-Output "✅ 重新克隆成功: $cacheDir"
                $PROJECT_DIR = $cacheDir
                $PROJECT_SOURCE = "git-cache"
            } catch {
                Write-Output "❌ 克隆失败，请检查Git仓库URL是否正确以及是否有权限访问"
                exit 1
            }
        }
    } else {
        # 缓存不存在，首次克隆
        if (Test-Path $cacheDir) {
            Remove-Item -Recurse -Force $cacheDir
        }
        Write-Output "检测到Git仓库，正在克隆到缓存目录..."
        try {
            git clone $InputPath $cacheDir 2>&1 | Out-Null
            Write-Output "✅ 克隆成功: $cacheDir"
            $PROJECT_DIR = $cacheDir
            $PROJECT_SOURCE = "git-cache"
        } catch {
            Write-Output "❌ 克隆失败，请检查Git仓库URL是否正确以及是否有权限访问"
            exit 1
        }
    }
} else {
    if (Test-Path $InputPath) {
        Write-Output "检测到本地项目: $InputPath"
        $PROJECT_DIR = (Resolve-Path $InputPath).Path
        $PROJECT_SOURCE = "local"
    } else {
        Write-Output "❌ 路径不存在: $InputPath"
        exit 1
    }
}

# 输出结果供主agent解析
Write-Output "PROJECT_DIR=$PROJECT_DIR"
Write-Output "PROJECT_SOURCE=$PROJECT_SOURCE"
