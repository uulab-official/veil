param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [string]$OutputDirectory = "$env:USERPROFILE\Desktop"
)

$ErrorActionPreference = "Stop"

$LogRoot = Join-Path $InstallRoot "logs"
$DiagnosticsRoot = Join-Path $InstallRoot "diagnostics"
$SparsePackageRoot = Join-Path $InstallRoot "package"
$SparsePackageStatusPath = Join-Path $SparsePackageRoot "sparse-package-status.json"
$AgentExe = Join-Path $InstallRoot "app\VeilAgent.exe"
$TaskName = "VeilAgent"

New-Item -ItemType Directory -Force -Path $DiagnosticsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$StagingRoot = Join-Path $DiagnosticsRoot "veil-agent-diagnostics-$Timestamp"
$ZipPath = Join-Path $OutputDirectory "veil-agent-diagnostics-$Timestamp.zip"

if (Test-Path $StagingRoot) {
    Remove-Item -Recurse -Force $StagingRoot
}
New-Item -ItemType Directory -Force -Path $StagingRoot | Out-Null

$SummaryPath = Join-Path $StagingRoot "summary.txt"
"GeneratedAt=$(Get-Date -Format o)" | Out-File -FilePath $SummaryPath -Encoding UTF8
"InstallRoot=$InstallRoot" | Add-Content -Path $SummaryPath
"LogRoot=$LogRoot" | Add-Content -Path $SummaryPath
"SparsePackageStatusPath=$SparsePackageStatusPath" | Add-Content -Path $SummaryPath
"SparsePackageStatusExists=$(Test-Path $SparsePackageStatusPath)" | Add-Content -Path $SummaryPath
"AgentExe=$AgentExe" | Add-Content -Path $SummaryPath
"AgentExeExists=$(Test-Path $AgentExe)" | Add-Content -Path $SummaryPath
"User=$env:USERNAME" | Add-Content -Path $SummaryPath
"ComputerName=$env:COMPUTERNAME" | Add-Content -Path $SummaryPath
"TaskName=$TaskName" | Add-Content -Path $SummaryPath

$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
"ScheduledTaskExists=$($null -ne $Task)" | Add-Content -Path $SummaryPath
if ($Task) {
    $Task | Format-List * | Out-File -FilePath (Join-Path $StagingRoot "scheduled-task.txt") -Encoding UTF8
}

$Processes = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue |
    Select-Object Id, ProcessName, StartTime, Path
if ($Processes) {
    $Processes | Format-List * | Out-File -FilePath (Join-Path $StagingRoot "processes.txt") -Encoding UTF8
} else {
    "No VeilAgent process is currently running." | Out-File -FilePath (Join-Path $StagingRoot "processes.txt") -Encoding UTF8
}

if (Test-Path $LogRoot) {
    $LogFiles = Get-ChildItem -Path $LogRoot -File -ErrorAction SilentlyContinue
    if ($LogFiles) {
        Copy-Item -Path $LogFiles.FullName -Destination $StagingRoot -Force
    } else {
        "Log directory exists but contains no files." | Add-Content -Path $SummaryPath
    }
} else {
    "No log directory found." | Add-Content -Path $SummaryPath
}

if (Test-Path $SparsePackageStatusPath) {
    Copy-Item -Path $SparsePackageStatusPath -Destination (Join-Path $StagingRoot "sparse-package-status.json") -Force
}

if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
Compress-Archive -Path (Join-Path $StagingRoot "*") -DestinationPath $ZipPath -Force

Write-Host "Veil agent diagnostics written to $ZipPath"
