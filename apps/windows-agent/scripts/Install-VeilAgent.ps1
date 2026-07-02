param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [string]$Configuration = "Release",
    [int]$Port = 18444
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Resolve-Path (Join-Path $ScriptRoot "..")
$ProjectPath = Join-Path $AgentRoot "src\VeilAgent\VeilAgent.csproj"
$PublishRoot = Join-Path $InstallRoot "app"
$StartScript = Join-Path $AgentRoot "scripts\Start-VeilAgent.ps1"
$TaskName = "VeilAgent"

New-Item -ItemType Directory -Force -Path $PublishRoot | Out-Null

dotnet publish $ProjectPath `
    --configuration $Configuration `
    --runtime win-arm64 `
    --self-contained false `
    --output $PublishRoot

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
Write-Host "Start now with: powershell -NoProfile -ExecutionPolicy Bypass -File `"$StartScript`" -InstallRoot `"$InstallRoot`" -Port $Port"
