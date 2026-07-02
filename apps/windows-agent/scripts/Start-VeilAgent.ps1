param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444
)

$ErrorActionPreference = "Stop"

$LogRoot = Join-Path $InstallRoot "logs"
$StartLogPath = Join-Path $LogRoot "start.log"
$AgentExe = Join-Path $InstallRoot "app\VeilAgent.exe"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
Add-Content -Path $StartLogPath -Value "VeilAgent start requested at $(Get-Date -Format o). InstallRoot=$InstallRoot Port=$Port"
if (-not (Test-Path $AgentExe)) {
    Add-Content -Path $StartLogPath -Value "VeilAgent.exe was not found at $AgentExe."
    throw "VeilAgent.exe was not found at $AgentExe. Run Install-VeilAgent.ps1 first."
}

$env:VEIL_AGENT_HOST = "127.0.0.1"
$env:VEIL_AGENT_PORT = "$Port"

$Process = Start-Process `
    -FilePath $AgentExe `
    -WorkingDirectory (Split-Path -Parent $AgentExe) `
    -WindowStyle Hidden `
    -PassThru

Add-Content -Path $StartLogPath -Value "VeilAgent process started. PID=$($Process.Id)"

Write-Host "VeilAgent started on ws://127.0.0.1:$Port/"
