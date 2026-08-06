param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444,
    [string]$StatusPath = "",
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

# Normalize once so every later comparison against $InstallRoot (in particular
# Find-VeilSharedAgentRoot's self-copy guard) compares like-for-like against paths that come back
# from Resolve-Path, regardless of trailing separators or relative segments the caller passed in.
# GetFullPath is used instead of Resolve-Path because $InstallRoot does not have to exist yet on a
# fresh install.
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallScript = Join-Path $ScriptRoot "Install-VeilAgent.ps1"
$StartScript = Join-Path $InstallRoot "scripts\Start-VeilAgent.ps1"
$InstalledScriptsRoot = Join-Path $InstallRoot "scripts"
$InstallRootApp = Join-Path $InstallRoot "app"
$AgentExe = Join-Path $InstallRootApp "VeilAgent.exe"
$TaskName = "VeilAgent"
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

    # Driver installation and firewall setup are intermediate stages. Only the final health
    # stage is terminal; returning on networkDriverInstalled lets the non-elevated caller finish
    # before the standard-user agent has been started and hides the real failure.
    $TerminalSuccessStages = @(
        "guestAgentHealthSucceeded"
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
            if ($Status.succeeded -eq $true -and $TerminalSuccessStages -contains [string]$Status.stage) {
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
    # Start-Process receives a single command-line string for the RunAs verb. Passing a string array
    # here is interpreted differently by Windows PowerShell and can fail before the elevated process
    # is created, leaving the parent waiting forever for repair-status.json.
    $ArgumentLine = @(
        "-NoProfile",
        "-ExecutionPolicy Bypass",
        "-File `"$PSCommandPath`"",
        "-InstallRoot `"$InstallRoot`"",
        "-Port", "$Port",
        "-StatusPath `"$StatusPath`"",
        "-Elevated"
    ) -join " "

    Write-Host "Requesting elevated repair at $(Get-Date -Format o)."
    try {
        $Process = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $ArgumentLine `
            -Verb RunAs `
            -WindowStyle Normal `
            -PassThru `
            -ErrorAction Stop
    } catch {
        Write-VeilRepairStatus `
            -Stage "failed" `
            -Succeeded $false `
            -Message "Unable to request elevated repair: $($_.Exception.Message)"
        throw
    }

    Write-Host "Elevated repair process started. PID=$($Process.Id)"
}

$script:CachedSharedAgentRoot = $null

function Find-VeilSharedAgentRoot {
    # When this script runs from its installed copy ($ScriptRoot = %LOCALAPPDATA%\Veil\Agent\scripts),
    # a plain "..\app" relative to $ScriptRoot resolves to the installed app folder itself
    # ($InstallRootApp) rather than the real "Veil Guest Agent" bundle on the shared drive. Copying
    # that "source" onto the install destination is then a silent no-op, so a newer staged build
    # never actually reaches the guest even though the repair flow reports success. Scan attached
    # filesystem drives for the real "Veil Guest Agent" folder instead of trusting $ScriptRoot's
    # current location, the same way Install-VeilVirtIONetworkDriver looks for driver media below.
    #
    # Cached per script run: this is called from both Sync-VeilInstalledSupportScripts and
    # Sync-VeilInstalledAppBundle, and re-scanning every attached drive twice is both wasted work and
    # a correctness risk if drive state could change between the two calls (it shouldn't within one
    # repair run, but computing it once removes the possibility entirely).
    if ($script:CachedSharedAgentRoot) {
        return $script:CachedSharedAgentRoot
    }

    $ScriptRootAgentRoot = (Resolve-Path (Join-Path $ScriptRoot "..")).Path

    $CandidateRoots = @()
    foreach ($Drive in Get-PSDrive -PSProvider FileSystem) {
        if (-not $Drive.Root) {
            continue
        }
        $CandidateRoots += Join-Path $Drive.Root "Veil Guest Agent"
    }

    foreach ($CandidateRoot in $CandidateRoots) {
        try {
            if (-not (Test-Path (Join-Path $CandidateRoot "app\VeilAgent.exe"))) {
                continue
            }

            $ResolvedCandidateRoot = (Resolve-Path $CandidateRoot).Path
        } catch {
            # A disconnected network drive, a stale substituted drive letter, or removable media in
            # a bad state can make Test-Path/Resolve-Path throw instead of returning $false under
            # this script's global $ErrorActionPreference = "Stop". One bad drive must not abort the
            # whole repair flow -- skip it and keep scanning the rest.
            Write-Host "Skipping unreachable drive candidate ${CandidateRoot}: $($_.Exception.Message)"
            continue
        }

        if ($ResolvedCandidateRoot -ne $InstallRoot) {
            $script:CachedSharedAgentRoot = $ResolvedCandidateRoot
            return $script:CachedSharedAgentRoot
        }
    }

    $script:CachedSharedAgentRoot = $ScriptRootAgentRoot
    return $script:CachedSharedAgentRoot
}

function Sync-VeilInstalledSupportScripts {
    New-Item -ItemType Directory -Force -Path $InstalledScriptsRoot | Out-Null
    $SharedAgentRoot = Find-VeilSharedAgentRoot
    $SharedScriptsRoot = Join-Path $SharedAgentRoot "scripts"

    if ((Resolve-Path $SharedScriptsRoot -ErrorAction SilentlyContinue).Path -eq (Resolve-Path $InstalledScriptsRoot -ErrorAction SilentlyContinue).Path) {
        Write-Host "Resolved support script source is the installed scripts folder itself; keeping installed scripts."
        return
    }

    foreach ($ScriptName in @(
        "Start-VeilAgent.ps1",
        "Collect-VeilAgentDiagnostics.ps1",
        "Repair-VeilAgentConnectivity.ps1"
    )) {
        $SourcePath = Join-Path $SharedScriptsRoot $ScriptName
        if (Test-Path $SourcePath) {
            Copy-Item -Force -Path $SourcePath -Destination $InstalledScriptsRoot
            Write-Host "Refreshed installed support script: $ScriptName from $SourcePath"
        }
    }
}

function Sync-VeilInstalledAppBundle {
    $BundledAppRoot = Join-Path (Find-VeilSharedAgentRoot) "app"
    $BundledAgentExe = Join-Path $BundledAppRoot "VeilAgent.exe"

    if (-not (Test-Path $BundledAgentExe)) {
        Write-Host "No packaged VeilAgent app bundle found at $BundledAgentExe; keeping installed app files."
        return $false
    }

    New-Item -ItemType Directory -Force -Path $InstallRootApp | Out-Null
    if ((Resolve-Path $BundledAppRoot).Path -eq (Resolve-Path $InstallRootApp).Path) {
        Write-Host "Resolved bundle source is the installed app folder itself; keeping installed app files."
        return $false
    }

    $RunningAgents = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue
    if ($RunningAgents) {
        Write-Host "Stopping existing VeilAgent process before refreshing installed app bundle."
        $RunningAgents | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

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

    $InstalledAnyDriver = $false
    foreach ($InfFile in $InfFiles) {
        Write-Host "Installing VirtIO network driver from $($InfFile.FullName)."
        pnputil /add-driver "$($InfFile.FullName)" /install | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -eq 0) {
            $InstalledAnyDriver = $true
        } else {
            Write-Host "pnputil returned ExitCode=$LASTEXITCODE while installing $($InfFile.FullName); continuing repair so firewall and agent health can still be checked."
        }
    }

    Write-Host "VirtIO NetKVM Windows 11 ARM64 driver install completed from $DriverRoot. InstalledAnyDriver=$InstalledAnyDriver"
    return $InstalledAnyDriver
}

function Invoke-VeilNetworkDeviceRescan {
    Write-Host "Requesting a Windows Plug and Play network-device rescan."
    $ScanOutput = @(& pnputil /scan-devices 2>&1)
    $ScanExitCode = $LASTEXITCODE
    $ScanOutput | ForEach-Object { Write-Host $_ }

    $Adapters = @()
    try {
        $Adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.HardwareInterface -eq $true })
    } catch {
        Write-Host "Unable to enumerate Windows network adapters after device rescan: $($_.Exception.Message)"
    }

    $AdapterSummary = if ($Adapters.Count -gt 0) {
        ($Adapters | ForEach-Object { "$($_.Name) [$($_.Status)]" }) -join ", "
    } else {
        "none"
    }
    $ScanSucceeded = $ScanExitCode -eq 0 -and $Adapters.Count -gt 0
    $RescanMessage = "pnputil /scan-devices exit code $ScanExitCode. Hardware network adapters visible after rescan: $AdapterSummary."
    Write-VeilRepairStatus -Stage "networkDeviceRescan" -Succeeded $ScanSucceeded -Message $RescanMessage
    Write-Host $RescanMessage

    # Windows may need a short interval to bind a newly installed NetKVM package to the
    # emulated device before Get-NetIPAddress can observe an address.
    Start-Sleep -Seconds 5
    return $ScanSucceeded
}

function Start-VeilAgentAsStandardUser {
    param(
        [string]$StartScriptPath,
        [int]$TimeoutSeconds = 30
    )

    # The repair itself must be elevated for driver and firewall work, but the agent launches
    # desktop apps on behalf of the signed-in user. Starting it directly here would make every
    # child app elevated and break normal window control. Re-register and run the interactive
    # logon task at Limited integrity instead.
    $PowerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $PowerShellPath)) {
        throw "Windows PowerShell executable was not found at $PowerShellPath."
    }

    $Action = New-ScheduledTaskAction `
        -Execute $PowerShellPath `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$StartScriptPath`" -InstallRoot `"$InstallRoot`" -Port $Port -RequireGuestIPv4"
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    # Match Install-VeilAgent.ps1. With an Interactive principal, Task Scheduler resolves the
    # current session from the plain account name; forcing DOMAIN\USERNAME here can create a task
    # that registers successfully but cannot be started in the signed-in desktop session (especially
    # for local accounts in the managed ARM guest).
    $InteractiveUser = $env:USERNAME
    $Principal = New-ScheduledTaskPrincipal `
        -UserId $InteractiveUser `
        -LogonType Interactive `
        -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Principal $Principal `
        -Settings $Settings `
        -Force | Out-Null
    Write-Host "Registered limited interactive VeilAgent task for $InteractiveUser."

    Write-VeilRepairStatus -Stage "standardUserAgentStartRequested" -Succeeded $false -Message "Requested VeilAgent start through the limited interactive logon task for $InteractiveUser."
    Start-ScheduledTask -TaskName $TaskName

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $RunningAgent = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $AgentExe } |
            Select-Object -First 1
        if ($RunningAgent) {
            Write-Host "Limited interactive VeilAgent process appeared. PID=$($RunningAgent.Id)"
            # The process already exists, so Start-VeilAgent.ps1 only performs its bounded health
            # probes here; it cannot fall through to an elevated Start-Process call.
            & $StartScriptPath -InstallRoot $InstallRoot -Port $Port -RequireGuestIPv4
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $Deadline)

    $TaskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    $TaskState = if ($TaskInfo) { [string]$TaskInfo.State } else { "unknown" }
    $LastTaskResult = if ($TaskInfo) {
        "0x{0:X8}" -f ([uint32]$TaskInfo.LastTaskResult)
    } else {
        "unknown"
    }
    $LastRunTime = if ($TaskInfo) { [string]$TaskInfo.LastRunTime } else { "unknown" }
    throw "Timed out waiting for the limited interactive VeilAgent task to start $AgentExe. TaskState=$TaskState LastTaskResult=$LastTaskResult LastRunTime=$LastRunTime User=$InteractiveUser."
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
        Write-VeilRepairStatus -Stage "networkDriverInstalled" -Succeeded $true -Message "VirtIO NetKVM Windows 11 ARM64 driver installed from attached driver media."
    }
    Invoke-VeilNetworkDeviceRescan | Out-Null

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

    Start-VeilAgentAsStandardUser -StartScriptPath $StartScript
    Write-VeilRepairStatus -Stage "guestAgentHealthSucceeded" -Succeeded $true -Message "VeilAgent answered agent.health.response inside Windows on loopback and guest IPv4."
    Write-Host "VeilAgent connectivity repair completed. Firewall rules are present and loopback health succeeded; guest IPv4 health was checked when available."
} catch {
    Write-VeilRepairStatus -Stage "failed" -Succeeded $false -Message $_.Exception.Message
    throw
} finally {
    Stop-Transcript | Out-Null
}
