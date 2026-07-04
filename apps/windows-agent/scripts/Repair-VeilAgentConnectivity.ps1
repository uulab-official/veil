param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444,
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallScript = Join-Path $ScriptRoot "Install-VeilAgent.ps1"
$StartScript = Join-Path $InstallRoot "scripts\Start-VeilAgent.ps1"
$InstallRootApp = Join-Path $InstallRoot "app"
$AgentExe = Join-Path $InstallRootApp "VeilAgent.exe"
$LogRoot = Join-Path $InstallRoot "logs"
$RepairLogPath = Join-Path $LogRoot "repair.log"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Test-VeilAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-VeilElevatedRepair {
    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-InstallRoot", "`"$InstallRoot`"",
        "-Port", "$Port",
        "-Elevated"
    )

    Write-Host "Requesting elevated repair at $(Get-Date -Format o)."
    $Process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList $Arguments `
        -Verb RunAs `
        -WindowStyle Normal `
        -PassThru

    Write-Host "Elevated repair process started. PID=$($Process.Id)"
}

if (-not (Test-VeilAdministrator)) {
    Write-Host "Repair-VeilAgentConnectivity.ps1 started at $(Get-Date -Format o)."
    Write-Host "InstallRoot=$InstallRoot"
    Write-Host "Port=$Port"
    Write-Host "IsAdministrator=False"
    Write-Host "Administrator rights are required to repair Windows Firewall rules. Requesting UAC elevation."
    Invoke-VeilElevatedRepair
    Write-Host "Elevated repair launched. Approve the Windows prompt and wait for VeilAgent health."
    return
}

Start-Transcript -Path $RepairLogPath -Append | Out-Null
try {
    Write-Host "Repair-VeilAgentConnectivity.ps1 started at $(Get-Date -Format o)."
    Write-Host "InstallRoot=$InstallRoot"
    Write-Host "Port=$Port"
    Write-Host "IsAdministrator=True"

    if (-not (Test-Path $AgentExe)) {
        if (-not (Test-Path $InstallScript)) {
            throw "VeilAgent.exe was not found at $AgentExe and Install-VeilAgent.ps1 was not found at $InstallScript."
        }

        Write-Host "Installed VeilAgent.exe is missing; running installer before connectivity repair."
        & $InstallScript -InstallRoot $InstallRoot -Port $Port -NoStart
    }

    $RunningAgents = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue
    if ($RunningAgents) {
        Write-Host "Stopping existing VeilAgent process before firewall repair."
        $RunningAgents | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    foreach ($RuleName in @("VeilAgent", "VeilAgent WebSocket Port")) {
        netsh advfirewall firewall delete rule name="$RuleName" | Out-Null
    }

    netsh advfirewall firewall add rule `
        name="VeilAgent" `
        dir=in `
        action=allow `
        program="$AgentExe" `
        enable=yes `
        profile=any | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "netsh failed while adding the VeilAgent program firewall rule. ExitCode=$LASTEXITCODE"
    }

    netsh advfirewall firewall add rule `
        name="VeilAgent WebSocket Port" `
        dir=in `
        action=allow `
        protocol=TCP `
        localport=$Port `
        enable=yes `
        profile=any | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "netsh failed while adding the VeilAgent port firewall rule. ExitCode=$LASTEXITCODE"
    }

    [Environment]::SetEnvironmentVariable("VEIL_AGENT_HOST", "0.0.0.0", "User")
    [Environment]::SetEnvironmentVariable("VEIL_AGENT_PORT", "$Port", "User")

    if (-not (Test-Path $StartScript)) {
        $StartScript = Join-Path $ScriptRoot "Start-VeilAgent.ps1"
    }
    if (-not (Test-Path $StartScript)) {
        throw "Start-VeilAgent.ps1 was not found in the installed scripts or source media."
    }

    & $StartScript -InstallRoot $InstallRoot -Port $Port
    Write-Host "VeilAgent connectivity repair completed. Firewall rules are present and local agent start succeeded."
} finally {
    Stop-Transcript | Out-Null
}
