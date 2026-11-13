param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [string]$Configuration = "Release",
    [int]$Port = 18444,
    [string]$SparsePackagePath = "",
    [string]$SparsePackageCertificatePath = "",
    [switch]$RequirePackageIdentity,
    [switch]$NoStart
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Resolve-Path (Join-Path $ScriptRoot "..")
$ProjectPath = Join-Path $AgentRoot "src\VeilAgent\VeilAgent.csproj"
$BundledAppRoot = Join-Path $AgentRoot "app"
$BundledAgentExe = Join-Path $BundledAppRoot "VeilAgent.exe"
$SparsePackageRoot = Join-Path $AgentRoot "package"
$SparsePackagePath = if ($SparsePackagePath) { $SparsePackagePath } else { Join-Path $SparsePackageRoot "VeilAgent.Identity.msix" }
$SparsePackageCertificatePath = if ($SparsePackageCertificatePath) { $SparsePackageCertificatePath } else { Join-Path $SparsePackageRoot "VeilAgent.Identity.cer" }
$SparsePackageName = "UULab.Veil.Agent"
$PublishRoot = Join-Path $InstallRoot "app"
$InstallBackupRoot = Join-Path $InstallRoot "app.previous"
$BundleLockPath = Join-Path $InstallRoot ".veil-agent-bundle.lock"
$InstallStagingRoot = Join-Path $InstallRoot ".install-staging-$([Guid]::NewGuid().ToString('N'))"
$InstallStagedAppRoot = Join-Path $InstallStagingRoot "app"
$InstalledScriptsRoot = Join-Path $InstallRoot "scripts"
$LogRoot = Join-Path $InstallRoot "logs"
$InstallLogPath = Join-Path $LogRoot "install.log"
$StartScript = Join-Path $InstalledScriptsRoot "Start-VeilAgent.ps1"
$TaskName = "VeilAgent"
$TimeSyncTaskName = "VeilTimeSync"

New-Item -ItemType Directory -Force -Path $InstalledScriptsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

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

function Test-VeilAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The agent runs with a limited token and cannot set the Windows clock, which goes stale after a
# suspended session is resumed or the Mac sleeps. This registers a SYSTEM task that resyncs from
# network time and lets the installing user start it; time.sync.request starts it when needed.
function Register-VeilTimeSyncTask {
    param(
        [string]$SyncScript,
        [string]$TaskName
    )

    if (-not (Test-VeilAdministrator)) {
        Write-Host "Not elevated; skipping the $TaskName task. time.sync.request will report install-time-sync-task-elevated."
        return
    }

    # The task runs as SYSTEM, so it must not run anything a program running as the user can replace. It
    # used to run Sync-VeilGuestTime.ps1 from the install folder under %LOCALAPPDATA%, which the user can
    # write to: any program of theirs could put its own code there and start the task. It now starts the
    # Windows Time service and asks for a resync with two programs from the Windows directory, by full
    # path. GuestTimeSyncRepair.RegistrationScript in the agent registers the same task.
    $System32 = Join-Path $env:SystemRoot "System32"
    $Command = '/c ""' + (Join-Path $System32 "sc.exe") + '" start w32time & "' + (Join-Path $System32 "w32tm.exe") + '" /resync /rediscover"'
    $Action = New-ScheduledTaskAction `
        -Execute (Join-Path $System32 "cmd.exe") `
        -Argument $Command
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Principal $Principal `
        -Settings $Settings `
        -Force | Out-Null

    # Grant only read and execute on this one task to the installing user, so the limited-token agent
    # can start it but not change what it runs.
    $UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $Scheduler = New-Object -ComObject "Schedule.Service"
    $Scheduler.Connect()
    $Task = $Scheduler.GetFolder("\").GetTask($TaskName)
    $Descriptor = $Task.GetSecurityDescriptor(4)
    $Ace = "(A;;GRGX;;;$UserSid)"
    if (-not $Descriptor.Contains($Ace)) {
        $Task.SetSecurityDescriptor($Descriptor + $Ace, 0)
    }

    # Standalone-machine W32Time refuses corrections over 15 hours, which is exactly the long-sleep
    # case. 0xFFFFFFFF means "accept any correction".
    $ConfigKey = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config"
    Set-ItemProperty -Path $ConfigKey -Name MaxPosPhaseCorrection -Value 0xFFFFFFFF -Type DWord
    Set-ItemProperty -Path $ConfigKey -Name MaxNegPhaseCorrection -Value 0xFFFFFFFF -Type DWord
    w32tm /config /update | Out-Null

    Write-Host "Registered SYSTEM task '$TaskName' so the agent can resync the Windows clock after a Mac sleep."
}

function Register-VeilSparsePackage {
    param(
        [string]$PackagePath,
        [string]$CertificatePath,
        [string]$ExternalLocation,
        [string]$PackageName
    )

    if (-not (Test-Path $PackagePath)) {
        Write-Host "No signed sparse identity package found at $PackagePath; continuing with unpackaged agent identity."
        return
    }

    if ($CertificatePath -and (Test-Path $CertificatePath)) {
        Import-Certificate -FilePath $CertificatePath -CertStoreLocation Cert:\CurrentUser\TrustedPeople | Out-Null
        Write-Host "Trusted Veil sparse package certificate in Cert:\CurrentUser\TrustedPeople."
    }

    $ExistingPackage = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
    if ($ExistingPackage) {
        Write-Host "Removing existing sparse identity package $($ExistingPackage.PackageFullName)."
        $ExistingPackage | Remove-AppxPackage
    }

    Add-AppxPackage -Path $PackagePath -ExternalLocation $ExternalLocation
    Write-Host "Registered sparse identity package $PackageName for external location $ExternalLocation."
}

Start-Transcript -Path $InstallLogPath -Append | Out-Null
$BundleLockStream = $null
$bundleLockAcquired = $false
$installRetiredCurrent = $false
$installPromoted = $false
try {
    Write-Host "VeilAgent install started at $(Get-Date -Format o)."
    Write-Host "ScriptRoot=$ScriptRoot"
    Write-Host "AgentRoot=$AgentRoot"
    Write-Host "InstallRoot=$InstallRoot"

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

    New-Item -ItemType Directory -Force -Path $InstallStagedAppRoot | Out-Null
    if (Test-Path $BundledAgentExe) {
        Copy-Item `
            -Path (Join-Path $BundledAppRoot "*") `
            -Destination $InstallStagedAppRoot `
            -Recurse `
            -Force
        Write-Host "Using packaged VeilAgent app bundle from $BundledAppRoot; staged before promotion."
    } elseif (Get-Command dotnet -ErrorAction SilentlyContinue) {
        dotnet publish $ProjectPath `
            --configuration $Configuration `
            --runtime win-arm64 `
            --self-contained false `
            --output $InstallStagedAppRoot
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet publish failed with exit code $LASTEXITCODE."
        }
    } else {
        throw "No packaged VeilAgent.exe was found at $BundledAgentExe, and dotnet is not available. Build a win-arm64 bundle with scripts\Publish-VeilAgentBundle.ps1 before installing."
    }

    $RequiredArtifacts = @(
        "VeilAgent.exe",
        "VeilAgent.dll",
        "VeilAgent.deps.json",
        "VeilAgent.runtimeconfig.json"
    )
    foreach ($Artifact in $RequiredArtifacts) {
        $ArtifactPath = Join-Path $InstallStagedAppRoot $Artifact
        if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) -or (Get-Item -LiteralPath $ArtifactPath).Length -eq 0) {
            throw "The staged VeilAgent bundle is incomplete: missing or empty $ArtifactPath."
        }
    }

    if (Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue) {
        Write-Host "Stopping existing VeilAgent process before promoting the staged bundle."
        Stop-VeilAgentProcesses
    }

    if (Test-Path -LiteralPath $PublishRoot) {
        if (Test-Path -LiteralPath $InstallBackupRoot) {
            Remove-Item -LiteralPath $InstallBackupRoot -Recurse -Force
        }
        try {
            Move-VeilItemWithRetry -LiteralPath $PublishRoot -Destination $InstallBackupRoot
            $installRetiredCurrent = $true
        } catch {
            # An app opened by an older agent can keep this folder as its current directory, which
            # blocks renaming the folder but not replacing the files in it.
            Write-Host "Replacing the VeilAgent files in place: $($_.Exception.Message)"
            Copy-Item -LiteralPath $PublishRoot -Destination $InstallBackupRoot -Recurse -Force
            Copy-Item -Path (Join-Path $InstallStagedAppRoot "*") -Destination $PublishRoot -Recurse -Force
            $installPromoted = $true
        }
    }
    if (-not $installPromoted) {
        Move-Item -LiteralPath $InstallStagedAppRoot -Destination $PublishRoot
        $installPromoted = $true
    }
    Write-Host "Promoted the complete VeilAgent app bundle to $PublishRoot."

    Copy-Item `
        -Path (Join-Path $ScriptRoot "Start-VeilAgent.ps1") `
        -Destination $InstalledScriptsRoot `
        -Force
    Copy-Item `
        -Path (Join-Path $ScriptRoot "Collect-VeilAgentDiagnostics.ps1") `
        -Destination $InstalledScriptsRoot `
        -Force
    Copy-Item `
        -Path (Join-Path $ScriptRoot "Repair-VeilAgentConnectivity.ps1") `
        -Destination $InstalledScriptsRoot `
        -Force
    Copy-Item `
        -Path (Join-Path $ScriptRoot "Uninstall-VeilAgent.ps1") `
        -Destination $InstalledScriptsRoot `
        -Force
    Copy-Item `
        -Path (Join-Path $ScriptRoot "Sync-VeilGuestTime.ps1") `
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

    try {
        Register-VeilSparsePackage `
            -PackagePath $SparsePackagePath `
            -CertificatePath $SparsePackageCertificatePath `
            -ExternalLocation $PublishRoot `
            -PackageName $SparsePackageName
    } catch {
        Write-Warning "Veil sparse identity package could not be registered: $($_.Exception.Message)"
        Write-Host "Continuing with unpackaged identity; agent.health.response.capabilities.packageIdentity will remain false until the sparse package is registered."
    }

    try {
        Register-VeilTimeSyncTask `
            -SyncScript (Join-Path $InstalledScriptsRoot "Sync-VeilGuestTime.ps1") `
            -TaskName $TimeSyncTaskName
    } catch {
        Write-Warning "VeilTimeSync task could not be registered: $($_.Exception.Message)"
        Write-Host "Windows will keep its own clock after a Mac sleep or session resume until this installer runs as administrator."
    }

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
        & $StartScript -InstallRoot $InstallRoot -Port $Port -RequirePackageIdentity:$RequirePackageIdentity
        Write-Host "VeilAgent started inside Windows on 0.0.0.0:$Port. The macOS host connects through QEMU at ws://127.0.0.1:$Port/."
    } else {
        Write-Host "Start now with: powershell -NoProfile -ExecutionPolicy Bypass -File `"$StartScript`" -InstallRoot `"$InstallRoot`" -Port $Port"
    }
} finally {
    try {
        if ($installRetiredCurrent -and -not $installPromoted -and -not (Test-Path -LiteralPath $PublishRoot) -and (Test-Path -LiteralPath $InstallBackupRoot)) {
            try {
                Move-Item -LiteralPath $InstallBackupRoot -Destination $PublishRoot
                Write-Warning "Installation failed; the previous VeilAgent app bundle was restored."
            } catch {
                Write-Warning "Installation failed and rollback could not complete. Recover the previous bundle from $InstallBackupRoot."
            }
        }
        if (Test-Path -LiteralPath $InstallStagingRoot) {
            Remove-Item -LiteralPath $InstallStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
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
    Stop-Transcript | Out-Null
}
