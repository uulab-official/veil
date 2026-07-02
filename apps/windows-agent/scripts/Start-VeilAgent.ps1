param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444
)

$ErrorActionPreference = "Stop"

$AgentExe = Join-Path $InstallRoot "app\VeilAgent.exe"
if (-not (Test-Path $AgentExe)) {
    throw "VeilAgent.exe was not found at $AgentExe. Run Install-VeilAgent.ps1 first."
}

$env:VEIL_AGENT_HOST = "127.0.0.1"
$env:VEIL_AGENT_PORT = "$Port"

Start-Process `
    -FilePath $AgentExe `
    -WorkingDirectory (Split-Path -Parent $AgentExe) `
    -WindowStyle Hidden

Write-Host "VeilAgent started on ws://127.0.0.1:$Port/"
