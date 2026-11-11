param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent"
)

$ErrorActionPreference = "Stop"

$TaskName = "VeilAgent"
$SparsePackageName = "UULab.Veil.Agent"
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$TimeSyncTaskName = "VeilTimeSync"
if (Get-ScheduledTask -TaskName $TimeSyncTaskName -ErrorAction SilentlyContinue) {
    try {
        Unregister-ScheduledTask -TaskName $TimeSyncTaskName -Confirm:$false
    } catch {
        Write-Warning "VeilTimeSync task needs an elevated uninstall to remove: $($_.Exception.Message)"
    }
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
