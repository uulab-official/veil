param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent"
)

$ErrorActionPreference = "Stop"

$TaskName = "VeilAgent"
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

[Environment]::SetEnvironmentVariable("VEIL_AGENT_HOST", $null, "User")
[Environment]::SetEnvironmentVariable("VEIL_AGENT_PORT", $null, "User")

if (Test-Path $InstallRoot) {
    Remove-Item -Path $InstallRoot -Recurse -Force
}

Write-Host "VeilAgent scheduled task and files removed."
