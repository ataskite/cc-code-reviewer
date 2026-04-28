# 阶段三：项目预扫描
# 用途：快速了解项目规模、模块分布和项目类型，完成单模块/多模块判断

param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectDir
)

$ErrorActionPreference = "Stop"

function Get-JavaStats {
    param([string]$RootDir, [string]$ExcludePattern)
    $count = 0
    $lines = 0
    $javaFiles = Get-ChildItem -Path $RootDir -Filter "*.java" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $ExcludePattern -and $_.FullName -notmatch '\.git[/\\]' }
    foreach ($file in $javaFiles) {
        $count++
        $lines += (Get-Content $file.FullName | Measure-Object -Line).Lines
    }
    return "$count|$lines"
}

function Get-RelativeDir {
    param([string]$Dir)
    if ($Dir -eq $ProjectDir) {
        return ""
    } else {
        $rel = $Dir.Substring($ProjectDir.Length)
        return $rel
    }
}

# 检测项目类型并执行相应扫描
if (Test-Path (Join-Path $ProjectDir "pom.xml")) {
    # Maven项目扫描
    Write-Output "=== 项目概况 ==="
    Write-Output "项目类型: Maven"
    $stats = Get-JavaStats $ProjectDir 'target'
    $javaCount = $stats.Split('|')[0]
    $javaLines = $stats.Split('|')[1]
    Write-Output "Java文件总数: $javaCount"
    Write-Output "代码总行数: $javaLines"
    Write-Output ""

    # 检测是否为多模块项目（排除 XML 注释中的 <modules> 标签）
    $pomContent = Get-Content (Join-Path $ProjectDir "pom.xml") -Raw
    $pomNoComments = $pomContent -replace '<!--.*?-->', ''
    $isMultiModule = [regex]::Matches($pomNoComments, '<modules>').Count
    if ($isMultiModule -eq 0) {
        Write-Output "模块类型: 单模块项目"
        Write-Output "PROJECT_TYPE=maven-single"
    } else {
        Write-Output "模块类型: 多模块项目"
        Write-Output "PROJECT_TYPE=maven-multi"
    }

    Write-Output ""
    Write-Output "=== 模块结构 ==="
    $pomFiles = Get-ChildItem -Path $ProjectDir -Filter "pom.xml" -Recurse -File -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch 'target' }
    foreach ($pomFile in $pomFiles) {
        $dir = $pomFile.DirectoryName
        $rel = Get-RelativeDir $dir
        if ([string]::IsNullOrEmpty($rel)) {
            $rootStats = Get-JavaStats $dir 'target'
            $rootCount = $rootStats.Split('|')[0]
            $rootLines = $rootStats.Split('|')[1]
            Write-Output "├── (root)  [$rootCount 类, $rootLines 行]"
            continue
        }
        $moduleStats = Get-JavaStats $dir 'target'
        $mCount = $moduleStats.Split('|')[0]
        $mLines = $moduleStats.Split('|')[1]
        if ([int]$mCount -gt 0) {
            $depth = ($rel.ToCharArray() | Where-Object { $_ -eq '\' -or $_ -eq '/' }).Count
            $indent = " " * ($depth * 2)
            $name = Split-Path $dir -Leaf
            Write-Output "$indent├── $name  [$mCount 类, $mLines 行]"
            Write-Output "MODULE:$name|$rel|$mCount|$mLines"
        }
    }

} elseif ((Test-Path (Join-Path $ProjectDir "build.gradle")) -or (Test-Path (Join-Path $ProjectDir "build.gradle.kts"))) {
    # Gradle项目扫描
    Write-Output "=== 项目概况 ==="
    Write-Output "项目类型: Gradle"
    $stats = Get-JavaStats $ProjectDir 'build'
    $javaCount = $stats.Split('|')[0]
    $javaLines = $stats.Split('|')[1]
    Write-Output "Java文件总数: $javaCount"
    Write-Output "代码总行数: $javaLines"
    Write-Output ""

    # 检测是否为多模块项目（通过settings.gradle判断）
    $settingsFile = Get-ChildItem -Path $ProjectDir -Filter "settings.gradle*" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($settingsFile) {
        $settingsContent = Get-Content $settingsFile.FullName -Raw
        $settingsNoComments = $settingsContent -replace '(?m)^\s*//.*$', ''
        $includeCount = [regex]::Matches($settingsNoComments, 'include').Count
        if ($includeCount -gt 0) {
            Write-Output "模块类型: 多模块项目"
            Write-Output "PROJECT_TYPE=gradle-multi"
        } else {
            Write-Output "模块类型: 单模块项目"
            Write-Output "PROJECT_TYPE=gradle-single"
        }
    } else {
        Write-Output "模块类型: 单模块项目"
        Write-Output "PROJECT_TYPE=gradle-single"
    }

    Write-Output ""
    Write-Output "=== 模块结构 ==="
    $buildFiles = Get-ChildItem -Path $ProjectDir -Filter "build.gradle*" -Recurse -File -Depth 3 -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch 'build' }
    foreach ($buildFile in $buildFiles) {
        $dir = $buildFile.DirectoryName
        $rel = Get-RelativeDir $dir
        if ([string]::IsNullOrEmpty($rel)) {
            $rootStats = Get-JavaStats $dir 'build'
            $rootCount = $rootStats.Split('|')[0]
            $rootLines = $rootStats.Split('|')[1]
            Write-Output "├── (root)  [$rootCount 类, $rootLines 行]"
            continue
        }
        $moduleStats = Get-JavaStats $dir 'build'
        $mCount = $moduleStats.Split('|')[0]
        $mLines = $moduleStats.Split('|')[1]
        if ([int]$mCount -gt 0) {
            $depth = ($rel.ToCharArray() | Where-Object { $_ -eq '\' -or $_ -eq '/' }).Count
            $indent = " " * ($depth * 2)
            $name = Split-Path $dir -Leaf
            Write-Output "$indent├── $name  [$mCount 类, $mLines 行]"
            Write-Output "MODULE:$name|$rel|$mCount|$mLines"
        }
    }
} else {
    Write-Output "=== 项目概况 ==="
    Write-Output "❌ 未检测到 Maven (pom.xml) 或 Gradle (build.gradle) 构建文件"
    Write-Output "PROJECT_TYPE=unknown"
    Write-Output ""
    $stats = Get-JavaStats $ProjectDir 'target'
    $javaCount = $stats.Split('|')[0]
    Write-Output "Java文件总数: $javaCount"
}
