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

    $RunningAgents = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue
    if ($RunningAgents) {
        Write-Host "Stopping existing VeilAgent process before updating installed files."
        $RunningAgents | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

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
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    $TaskRegistered = $false
    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $Action `
            -Trigger $Trigger `
            -Principal $Principal `
            -Settings $Settings `
            -Force | Out-Null
        $TaskRegistered = $true
    } catch {
        Write-Warning "VeilAgent logon task could not be registered: $($_.Exception.Message)"
        Write-Host "Continuing with current-session agent start; run this installer as an elevated user later to enable logon auto-start."
    }

    [Environment]::SetEnvironmentVariable("VEIL_AGENT_HOST", "0.0.0.0", "User")
    [Environment]::SetEnvironmentVariable("VEIL_AGENT_PORT", "$Port", "User")

    $FirewallProgram = Join-Path $PublishRoot "VeilAgent.exe"
    try {
        netsh advfirewall firewall add rule `
            name="VeilAgent" `
            dir=in `
            action=allow `
            program="$FirewallProgram" `
            enable=yes `
            profile=any | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "netsh exited with code $LASTEXITCODE"
        }
        Write-Host "VeilAgent Windows Firewall inbound rule is present."
    } catch {
        Write-Warning "VeilAgent Windows Firewall rule could not be added: $($_.Exception.Message)"
        Write-Host "Continuing with current-session agent start; if macOS cannot connect, allow VeilAgent in Windows Security or rerun this installer as an elevated user."
    }

    if ($TaskRegistered) {
        Write-Host "VeilAgent installed to $PublishRoot and registered as user logon task '$TaskName'."
    } else {
        Write-Host "VeilAgent installed to $PublishRoot without a logon task."
    }
    if (-not $NoStart) {
        & $StartScript -InstallRoot $InstallRoot -Port $Port
        Write-Host "VeilAgent started inside Windows on 0.0.0.0:$Port. The macOS host connects through QEMU at ws://127.0.0.1:$Port/."
    } else {
        Write-Host "Start now with: powershell -NoProfile -ExecutionPolicy Bypass -File `"$StartScript`" -InstallRoot `"$InstallRoot`" -Port $Port"
    }
} finally {
    Stop-Transcript | Out-Null
}
