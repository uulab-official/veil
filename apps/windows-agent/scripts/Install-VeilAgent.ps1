param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [string]$Configuration = "Release",
    [int]$Port = 18444,
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Resolve-Path (Join-Path $ScriptRoot "..")
$ProjectPath = Join-Path $AgentRoot "src\VeilAgent\VeilAgent.csproj"
$BundledAppRoot = Join-Path $AgentRoot "app"
$BundledAgentExe = Join-Path $BundledAppRoot "VeilAgent.exe"
$PublishRoot = Join-Path $InstallRoot "app"
$InstalledScriptsRoot = Join-Path $InstallRoot "scripts"
$LogRoot = Join-Path $InstallRoot "logs"
$InstallLogPath = Join-Path $LogRoot "install.log"
$StartScript = Join-Path $InstalledScriptsRoot "Start-VeilAgent.ps1"
$TaskName = "VeilAgent"

New-Item -ItemType Directory -Force -Path $PublishRoot | Out-Null
New-Item -ItemType Directory -Force -Path $InstalledScriptsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

Start-Transcript -Path $InstallLogPath -Append | Out-Null
try {
    Write-Host "VeilAgent install started at $(Get-Date -Format o)."
    Write-Host "ScriptRoot=$ScriptRoot"
    Write-Host "AgentRoot=$AgentRoot"
    Write-Host "InstallRoot=$InstallRoot"

    if (Test-Path $BundledAgentExe) {
        Get-ChildItem -Path $PublishRoot -Force | Remove-Item -Recurse -Force
        Copy-Item `
            -Path (Join-Path $BundledAppRoot "*") `
            -Destination $PublishRoot `
            -Recurse `
            -Force
        Write-Host "Using packaged VeilAgent app bundle from $BundledAppRoot."
    } elseif (Get-Command dotnet -ErrorAction SilentlyContinue) {
        dotnet publish $ProjectPath `
            --configuration $Configuration `
            --runtime win-arm64 `
            --self-contained false `
            --output $PublishRoot
    } else {
        throw "No packaged VeilAgent.exe was found at $BundledAgentExe, and dotnet is not available. Build a win-arm64 bundle with scripts\Publish-VeilAgentBundle.ps1 before installing."
    }

    Copy-Item `
        -Path (Join-Path $ScriptRoot "Start-VeilAgent.ps1") `
        -Destination $InstalledScriptsRoot `
        -Force
    Copy-Item `
        -Path (Join-Path $ScriptRoot "Collect-VeilAgentDiagnostics.ps1") `
        -Destination $InstalledScriptsRoot `
        -Force
    Copy-Item `
        -Path (Join-Path $ScriptRoot "Uninstall-VeilAgent.ps1") `
        -Destination $InstalledScriptsRoot `
        -Force

    $Action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$StartScript`" -InstallRoot `"$InstallRoot`" -Port $Port"
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel LeastPrivilege
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force | Out-Null

    [Environment]::SetEnvironmentVariable("VEIL_AGENT_HOST", "127.0.0.1", "User")
    [Environment]::SetEnvironmentVariable("VEIL_AGENT_PORT", "$Port", "User")

    Write-Host "VeilAgent installed to $PublishRoot and registered as user logon task '$TaskName'."
    if (-not $NoStart) {
        & $StartScript -InstallRoot $InstallRoot -Port $Port
        Write-Host "VeilAgent started and listening on ws://127.0.0.1:$Port/."
    } else {
        Write-Host "Start now with: powershell -NoProfile -ExecutionPolicy Bypass -File `"$StartScript`" -InstallRoot `"$InstallRoot`" -Port $Port"
    }
} finally {
    Stop-Transcript | Out-Null
}
