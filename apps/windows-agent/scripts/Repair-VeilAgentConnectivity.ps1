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
$RepairBackupRoot = Join-Path $InstallRoot "app.previous"
$BundleLockPath = Join-Path $InstallRoot ".veil-agent-bundle.lock"
$RepairStagingRoot = Join-Path $InstallRoot ".repair-staging-$([Guid]::NewGuid().ToString('N'))"
$RepairStagedAppRoot = Join-Path $RepairStagingRoot "app"
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
        # Long enough for a user who notices the Windows approval prompt late; the elevated repair
        # keeps running either way, but this console is what reports whether it finished.
        [int]$TimeoutSeconds = 300
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
    # Launched from media (for example the host's tools update disc next to an older VEIL_AUTO), the
    # bundle beside this script is the one the host meant; scanning drive letters could pick the old one.
    if ($ScriptRootAgentRoot -ne $InstallRoot -and
        (Test-Path (Join-Path $ScriptRootAgentRoot "app\VeilAgent.exe"))) {
        $script:CachedSharedAgentRoot = $ScriptRootAgentRoot
        return $script:CachedSharedAgentRoot
    }

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

function Stop-VeilAgentProcesses {
    $RunningAgents = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue
    if ($RunningAgents) {
        $RunningAgents | Stop-Process -Force -ErrorAction SilentlyContinue
        # Stop-Process returns before Windows releases the agent's image and DLL handles, so moving
        # the app folder right away failed with "being used by another process".
        $RunningAgents | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue
    }
}

function Move-VeilItemWithRetry {
    param(
        [string]$LiteralPath,
        [string]$Destination
    )

    for ($Attempt = 1; ; $Attempt++) {
        try {
            Move-Item -LiteralPath $LiteralPath -Destination $Destination
            return
        } catch {
            if ($Attempt -ge 5) {
                throw
            }
            Write-Host "$LiteralPath is still in use; retrying ($Attempt/5): $($_.Exception.Message)"
            Stop-VeilAgentProcesses
            Start-Sleep -Seconds 1
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

    $BundledResolvedPath = (Resolve-Path $BundledAppRoot).Path
    if ((Test-Path -LiteralPath $InstallRootApp -PathType Container) -and
        $BundledResolvedPath -eq (Resolve-Path $InstallRootApp).Path) {
        Write-Host "Resolved bundle source is the installed app folder itself; keeping installed app files."
        return $false
    }

    $RepairRetiredCurrent = $false
    $RepairPromoted = $false
    $BundleLockStream = $null
    $bundleLockAcquired = $false
    try {
        try {
            $BundleLockStream = [System.IO.File]::Open(
                $BundleLockPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )
            $bundleLockAcquired = $true
            $LockText = "pid=$PID`nstartedAt=$(Get-Date -Format o)"
            $LockBytes = [System.Text.Encoding]::UTF8.GetBytes($LockText)
            $BundleLockStream.Write($LockBytes, 0, $LockBytes.Length)
            $BundleLockStream.Flush()
        } catch {
            throw "Another VeilAgent bundle operation is active or needs recovery at $BundleLockPath. Inspect the lock owner before removing it."
        }

        # Copy and validate beside the live app. Connectivity repair must not erase a
        # working agent before a media copy has completed.
        New-Item -ItemType Directory -Force -Path $RepairStagedAppRoot | Out-Null
        Copy-Item `
            -Path (Join-Path $BundledAppRoot "*") `
            -Destination $RepairStagedAppRoot `
            -Recurse `
            -Force

        foreach ($Artifact in @(
            "VeilAgent.exe",
            "VeilAgent.dll",
            "VeilAgent.deps.json",
            "VeilAgent.runtimeconfig.json"
        )) {
            $ArtifactPath = Join-Path $RepairStagedAppRoot $Artifact
            if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) -or (Get-Item -LiteralPath $ArtifactPath).Length -eq 0) {
                throw "The staged VeilAgent bundle is incomplete: missing or empty $ArtifactPath."
            }
        }

        if (Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue) {
            Write-Host "Stopping existing VeilAgent process before promoting the repaired app bundle."
            Stop-VeilAgentProcesses
        }

        if (Test-Path -LiteralPath $InstallRootApp) {
            if (Test-Path -LiteralPath $RepairBackupRoot) {
                Remove-Item -LiteralPath $RepairBackupRoot -Recurse -Force
            }
            try {
                Move-VeilItemWithRetry -LiteralPath $InstallRootApp -Destination $RepairBackupRoot
                $RepairRetiredCurrent = $true
            } catch {
                # An app opened by an older agent can keep this folder as its current directory, which
                # blocks renaming the folder but not replacing the files in it.
                Write-Host "Replacing the VeilAgent files in place: $($_.Exception.Message)"
                Copy-Item -LiteralPath $InstallRootApp -Destination $RepairBackupRoot -Recurse -Force
                Copy-Item -Path (Join-Path $RepairStagedAppRoot "*") -Destination $InstallRootApp -Recurse -Force
                $RepairPromoted = $true
            }
        }
        if (-not $RepairPromoted) {
            Move-Item -LiteralPath $RepairStagedAppRoot -Destination $InstallRootApp
            $RepairPromoted = $true
        }
        Write-Host "Refreshed installed VeilAgent app bundle from $BundledAppRoot. Previous files are retained at $RepairBackupRoot."
        return $true
    } catch {
        if ($RepairRetiredCurrent -and -not $RepairPromoted -and
            -not (Test-Path -LiteralPath $InstallRootApp) -and
            (Test-Path -LiteralPath $RepairBackupRoot)) {
            try {
                Move-Item -LiteralPath $RepairBackupRoot -Destination $InstallRootApp
                Write-Warning "App refresh failed; the previous VeilAgent bundle was restored."
            } catch {
                Write-Warning "App refresh failed and rollback could not complete. Recover the previous bundle from $RepairBackupRoot."
            }
        }
        throw
    } finally {
        try {
            if (Test-Path -LiteralPath $RepairStagingRoot) {
                Remove-Item -LiteralPath $RepairStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        } finally {
            try {
                if ($BundleLockStream) {
                    $BundleLockStream.Dispose()
                }
            } finally {
                if ($bundleLockAcquired -and (Test-Path -LiteralPath $BundleLockPath)) {
                    Remove-Item -LiteralPath $BundleLockPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
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

function Start-VeilAgentAsStandardUser {
    param(
        [string]$StartScriptPath,
        [int]$TimeoutSeconds = 30
    )

    # The repair itself must be elevated for driver and firewall work, but the agent launches
    # desktop apps on behalf of the signed-in user. Starting it directly here would make every
    # child app elevated and break normal window control. Re-register and run the interactive
    # logon task at Limited integrity instead.
    $Action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$StartScriptPath`" -InstallRoot `"$InstallRoot`" -Port $Port"
    $Trigger = New-ScheduledTaskTrigger -AtLogOn
    $InteractiveUser = "$env:USERDOMAIN\$env:USERNAME"
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

    Start-ScheduledTask -TaskName $TaskName
    Write-VeilRepairStatus -Stage "standardUserAgentStartRequested" -Succeeded $false -Message "Requested VeilAgent start through the limited interactive logon task."

    $Deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $RunningAgent = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $AgentExe } |
            Select-Object -First 1
        if ($RunningAgent) {
            Write-Host "Limited interactive VeilAgent process appeared. PID=$($RunningAgent.Id)"
            # The process already exists, so Start-VeilAgent.ps1 only performs its bounded health
            # probes here; it cannot fall through to an elevated Start-Process call.
            & $StartScriptPath -InstallRoot $InstallRoot -Port $Port -RequireGuestAddress
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $Deadline)

    throw "Timed out waiting for the limited interactive VeilAgent task to start $AgentExe."
}

function Test-VeilFirewallRulesReady {
    # Reading firewall rules needs no elevation. The program rule names the installed VeilAgent.exe
    # path, so new files at that path stay covered without touching the rules.
    try {
        $ProgramRule = Get-NetFirewallRule -DisplayName "VeilAgent" -ErrorAction Stop |
            Where-Object { $_.Enabled -eq "True" -and $_.Direction -eq "Inbound" -and $_.Action -eq "Allow" } |
            Where-Object { ($_ | Get-NetFirewallApplicationFilter).Program -eq $AgentExe } |
            Select-Object -First 1
        $PortRule = Get-NetFirewallRule -DisplayName "VeilAgent WebSocket Port" -ErrorAction Stop |
            Where-Object { $_.Enabled -eq "True" -and $_.Direction -eq "Inbound" -and $_.Action -eq "Allow" } |
            Where-Object { @(($_ | Get-NetFirewallPortFilter).LocalPort) -contains "$Port" } |
            Select-Object -First 1
        return [bool]($ProgramRule -and $PortRule)
    } catch {
        return $false
    }
}

function Invoke-VeilUnelevatedUpdate {
    # A tools update only replaces files under %LOCALAPPDATA% and restarts the agent as this user,
    # which needs no administrator rights once the firewall rules exist. Asking for approval on every
    # update left it to fail whenever nobody was at the Windows prompt.
    Start-Transcript -Path $RepairLogPath -Append | Out-Null
    try {
        Write-Host "Repair-VeilAgentConnectivity.ps1 started at $(Get-Date -Format o)."
        Write-Host "InstallRoot=$InstallRoot"
        Write-Host "Port=$Port"
        Write-Host "IsAdministrator=False"
        Write-Host "Firewall rules for $AgentExe and TCP $Port are present; updating without elevation."
        Write-VeilRepairStatus -Stage "started" -Succeeded $false -Message "Unelevated update started."
        Sync-VeilInstalledAppBundle | Out-Null
        Sync-VeilInstalledSupportScripts
        & $StartScript -InstallRoot $InstallRoot -Port $Port -RequireGuestAddress
        Write-VeilRepairStatus -Stage "guestAgentHealthSucceeded" -Succeeded $true -Message "VeilAgent was updated without elevation and answered agent.health.response on loopback and guest IPv4."
        Write-Host "VeilAgent update completed without elevation."
        return $true
    } catch {
        Write-Host "Updating without elevation failed: $($_.Exception.Message)"
        return $false
    } finally {
        Stop-Transcript | Out-Null
    }
}

if (-not (Test-VeilAdministrator) -and (Test-Path $AgentExe) -and (Test-VeilFirewallRulesReady)) {
    if (Invoke-VeilUnelevatedUpdate) {
        return
    }
    Write-Host "Falling back to the elevated repair."
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
    # VMs installed before Veil added viogpudo get it here; the host boots on virtio-gpu alone from
    # the next cold start once the agent reports it. Until then QEMU still attaches ramfb, so keep
    # Windows on the one display Veil shows.
    $VirtIODriversScript = Join-Path $ScriptRoot "Install-VeilVirtIODrivers.ps1"
    if (Test-Path $VirtIODriversScript) {
        & $VirtIODriversScript -DriverFolders @("viogpudo", "viorng", "Balloon", "vioserial") -SingleBootDisplay -DisplayWaitSeconds 15
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

    Start-VeilAgentAsStandardUser -StartScriptPath $StartScript
    Write-VeilRepairStatus -Stage "guestAgentHealthSucceeded" -Succeeded $true -Message "VeilAgent answered agent.health.response inside Windows on loopback and guest IPv4."
    Write-Host "VeilAgent connectivity repair completed. Firewall rules are present and loopback plus guest IPv4 health succeeded."
} catch {
    Write-VeilRepairStatus -Stage "failed" -Succeeded $false -Message $_.Exception.Message
    throw
} finally {
    Stop-Transcript | Out-Null
}
