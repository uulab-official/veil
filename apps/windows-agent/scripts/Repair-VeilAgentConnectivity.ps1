param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444,
    [string]$StatusPath = "",
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallScript = Join-Path $ScriptRoot "Install-VeilAgent.ps1"
$StartScript = Join-Path $InstallRoot "scripts\Start-VeilAgent.ps1"
$InstalledScriptsRoot = Join-Path $InstallRoot "scripts"
$InstallRootApp = Join-Path $InstallRoot "app"
$AgentExe = Join-Path $InstallRootApp "VeilAgent.exe"
$LogRoot = Join-Path $InstallRoot "logs"
$RepairLogPath = Join-Path $LogRoot "repair.log"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $StatusPath = Join-Path $LogRoot "repair-status.json"
}

function Test-VeilAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-VeilRepairStatus {
    param(
        [string]$Stage,
        [bool]$Succeeded,
        [string]$Message
    )

    $StatusRoot = Split-Path -Parent $StatusPath
    if (-not [string]::IsNullOrWhiteSpace($StatusRoot)) {
        New-Item -ItemType Directory -Force -Path $StatusRoot | Out-Null
    }

    [ordered]@{
        updatedAt = Get-Date -Format o
        stage = $Stage
        succeeded = $Succeeded
        message = $Message
        installRoot = $InstallRoot
        port = $Port
        elevated = [bool]$Elevated
        isAdministrator = Test-VeilAdministrator
        pid = $PID
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $StatusPath -Encoding UTF8
}

function Wait-VeilRepairStatus {
    param(
        [int]$TimeoutSeconds = 90
    )

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $Deadline) {
        if (Test-Path $StatusPath) {
            $Status = $null
            try {
                $Status = Get-Content -Raw -Path $StatusPath | ConvertFrom-Json
            } catch {
                Start-Sleep -Milliseconds 250
                continue
            }

            Write-Host "Elevated repair status: stage=$($Status.stage) succeeded=$($Status.succeeded)"
            Write-Host $Status.message
            if ($Status.succeeded -eq $true) {
                return
            }
            if ($Status.stage -eq "failed") {
                throw $Status.message
            }
        }
        Start-Sleep -Seconds 1
    }

    throw "Timed out waiting for elevated repair status at $StatusPath."
}

function Invoke-VeilElevatedRepair {
    $Arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-InstallRoot", "`"$InstallRoot`"",
        "-Port", "$Port",
        "-StatusPath", "`"$StatusPath`"",
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

function Sync-VeilInstalledSupportScripts {
    New-Item -ItemType Directory -Force -Path $InstalledScriptsRoot | Out-Null

    foreach ($ScriptName in @(
        "Start-VeilAgent.ps1",
        "Collect-VeilAgentDiagnostics.ps1",
        "Repair-VeilAgentConnectivity.ps1"
    )) {
        $SourcePath = Join-Path $ScriptRoot $ScriptName
        if (Test-Path $SourcePath) {
            Copy-Item -Force -Path $SourcePath -Destination $InstalledScriptsRoot
            Write-Host "Refreshed installed support script: $ScriptName"
        }
    }
}

function Sync-VeilInstalledAppBundle {
    $AgentRoot = (Resolve-Path (Join-Path $ScriptRoot "..")).Path
    $BundledAppRoot = Join-Path $AgentRoot "app"
    $BundledAgentExe = Join-Path $BundledAppRoot "VeilAgent.exe"

    if (-not (Test-Path $BundledAgentExe)) {
        Write-Host "No packaged VeilAgent app bundle found at $BundledAgentExe; keeping installed app files."
        return $false
    }

    $RunningAgents = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue
    if ($RunningAgents) {
        Write-Host "Stopping existing VeilAgent process before refreshing installed app bundle."
        $RunningAgents | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    New-Item -ItemType Directory -Force -Path $InstallRootApp | Out-Null
    Get-ChildItem -Path $InstallRootApp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Copy-Item `
        -Path (Join-Path $BundledAppRoot "*") `
        -Destination $InstallRootApp `
        -Recurse `
        -Force
    Write-Host "Refreshed installed VeilAgent app bundle from $BundledAppRoot."
    return $true
}

function Install-VeilVirtIONetworkDriver {
    $CandidateRoots = @()
    foreach ($Drive in Get-PSDrive -PSProvider FileSystem) {
        $CandidateRoots += Join-Path $Drive.Root "NetKVM\w11\ARM64"
        $CandidateRoots += Join-Path $Drive.Root "NetKVM\w11\ARM64\2k22"
    }

    $DriverRoot = $CandidateRoots | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $DriverRoot) {
        Write-Host "No NetKVM Windows 11 ARM64 driver folder found on attached media."
        return $false
    }

    $InfFiles = Get-ChildItem -Path $DriverRoot -Filter "*.inf" -File -ErrorAction SilentlyContinue
    if (-not $InfFiles) {
        Write-Host "NetKVM driver folder found at $DriverRoot, but no INF files were present."
        return $false
    }

    foreach ($InfFile in $InfFiles) {
        Write-Host "Installing VirtIO network driver from $($InfFile.FullName)."
        pnputil /add-driver "$($InfFile.FullName)" /install | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "pnputil returned ExitCode=$LASTEXITCODE while installing $($InfFile.FullName); continuing repair so firewall and agent health can still be checked."
        }
    }

    Write-Host "VirtIO NetKVM Windows 11 ARM64 driver install attempted from $DriverRoot."
    return $true
}

if (-not (Test-VeilAdministrator)) {
    Write-Host "Repair-VeilAgentConnectivity.ps1 started at $(Get-Date -Format o)."
    Write-Host "InstallRoot=$InstallRoot"
    Write-Host "Port=$Port"
    Write-Host "StatusPath=$StatusPath"
    Write-Host "IsAdministrator=False"
    Write-Host "Administrator rights are required to repair Windows Firewall rules. Requesting UAC elevation."
    Remove-Item -Force -ErrorAction SilentlyContinue -Path $StatusPath
    Invoke-VeilElevatedRepair
    Write-Host "Elevated repair launched. Approve the Windows prompt; this console will wait for completion evidence."
    Wait-VeilRepairStatus
    return
}

Start-Transcript -Path $RepairLogPath -Append | Out-Null
try {
    Write-Host "Repair-VeilAgentConnectivity.ps1 started at $(Get-Date -Format o)."
    Write-Host "InstallRoot=$InstallRoot"
    Write-Host "Port=$Port"
    Write-Host "StatusPath=$StatusPath"
    Write-Host "IsAdministrator=True"
    Write-VeilRepairStatus -Stage "started" -Succeeded $false -Message "Elevated repair started."

    if (-not (Sync-VeilInstalledAppBundle) -and -not (Test-Path $AgentExe)) {
        if (-not (Test-Path $InstallScript)) {
            throw "VeilAgent.exe was not found at $AgentExe and Install-VeilAgent.ps1 was not found at $InstallScript."
        }

        Write-Host "Installed VeilAgent.exe is missing; running installer before connectivity repair."
        & $InstallScript -InstallRoot $InstallRoot -Port $Port -NoStart
    }
    Sync-VeilInstalledSupportScripts
    if (Install-VeilVirtIONetworkDriver) {
        Write-VeilRepairStatus -Stage "networkDriverInstalled" -Succeeded $false -Message "VirtIO NetKVM Windows 11 ARM64 driver install was attempted from attached driver media."
        Start-Sleep -Seconds 3
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
    Write-VeilRepairStatus -Stage "firewallRulesReady" -Succeeded $false -Message "Windows Firewall program and TCP $Port rules are present."

    [Environment]::SetEnvironmentVariable("VEIL_AGENT_HOST", "0.0.0.0", "User")
    [Environment]::SetEnvironmentVariable("VEIL_AGENT_PORT", "$Port", "User")

    if (-not (Test-Path $StartScript)) {
        $StartScript = Join-Path $ScriptRoot "Start-VeilAgent.ps1"
    }
    if (-not (Test-Path $StartScript)) {
        throw "Start-VeilAgent.ps1 was not found in the installed scripts or source media."
    }

    & $StartScript -InstallRoot $InstallRoot -Port $Port
    Write-VeilRepairStatus -Stage "guestAgentHealthSucceeded" -Succeeded $true -Message "VeilAgent answered agent.health.response inside Windows on loopback and guest IPv4."
    Write-Host "VeilAgent connectivity repair completed. Firewall rules are present and loopback plus guest IPv4 health succeeded."
} catch {
    Write-VeilRepairStatus -Stage "failed" -Succeeded $false -Message $_.Exception.Message
    throw
} finally {
    Stop-Transcript | Out-Null
}
