param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent"
)

$ErrorActionPreference = "Stop"

$TaskName = "VeilAgent"
$SparsePackageName = "UULab.Veil.Agent"
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$ExistingPackage = Get-AppxPackage -Name $SparsePackageName -ErrorAction SilentlyContinue
if ($ExistingPackage) {
    $ExistingPackage | Remove-AppxPackage
}

[Environment]::SetEnvironmentVariable("VEIL_AGENT_HOST", $null, "User")
[Environment]::SetEnvironmentVariable("VEIL_AGENT_PORT", $null, "User")

if (Test-Path $InstallRoot) {
    Remove-Item -Path $InstallRoot -Recurse -Force
}

Write-Host "VeilAgent scheduled task, sparse identity package, and files removed."
