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
  if ($Matches[1] -eq $Matches[2]) {
    Write-Error "无法识别修复输入来源: $InputSource"
    exit 1
  }
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
