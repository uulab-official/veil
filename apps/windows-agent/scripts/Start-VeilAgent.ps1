param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444,
    [switch]$RequirePackageIdentity,
    [switch]$RequireGuestAddress
)

$ErrorActionPreference = "Stop"

$LogRoot = Join-Path $InstallRoot "logs"
$StartLogPath = Join-Path $LogRoot "start.log"
$AgentExe = Join-Path $InstallRoot "app\VeilAgent.exe"
$StdOutLogPath = Join-Path $LogRoot "agent.stdout.log"
$StdErrLogPath = Join-Path $LogRoot "agent.stderr.log"
$ListenHost = "0.0.0.0"
$ProbeHost = "127.0.0.1"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
Add-Content -Path $StartLogPath -Value "VeilAgent start requested at $(Get-Date -Format o). InstallRoot=$InstallRoot Port=$Port RequirePackageIdentity=$RequirePackageIdentity RequireGuestAddress=$RequireGuestAddress"
if (-not (Test-Path $AgentExe)) {
    Add-Content -Path $StartLogPath -Value "VeilAgent.exe was not found at $AgentExe."
    throw "VeilAgent.exe was not found at $AgentExe. Run Install-VeilAgent.ps1 first."
}

function Test-VeilAgentPort {
    param(
        [int]$Port,
        [string]$ProbeAddress = "127.0.0.1",
        [int]$Attempts = 20
    )

    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        try {
            $Client = [System.Net.Sockets.TcpClient]::new()
            $Connect = $Client.BeginConnect($ProbeAddress, $Port, $null, $null)
            if ($Connect.AsyncWaitHandle.WaitOne(250)) {
                $Client.EndConnect($Connect)
                $Client.Close()
                return $true
            }
            $Client.Close()
        } catch {
            # Keep retrying; the agent may still be opening its WebSocket listener.
        }
        Start-Sleep -Milliseconds 250
    }

    return $false
}

function Test-VeilAgentHealth {
    param(
        [int]$Port,
        [string]$ProbeAddress = "127.0.0.1",
        [int]$Attempts = 10,
        [switch]$RequirePackageIdentity
    )

    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        $Client = [System.Net.WebSockets.ClientWebSocket]::new()
        $Cancellation = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(2))
        try {
            $Uri = [Uri]::new("ws://${ProbeAddress}:$Port/")
            $ConnectTask = $Client.ConnectAsync($Uri, $Cancellation.Token)
            if (-not $ConnectTask.Wait([TimeSpan]::FromSeconds(2))) {
                throw "Timed out connecting to $Uri."
            }
            if ($ConnectTask.IsFaulted) {
                throw $ConnectTask.Exception
            }

            $RequestId = "guest_health_$([Guid]::NewGuid().ToString("N"))"
            $Payload = @{
                type = "agent.health.request"
                requestId = $RequestId
                protocolVersion = 1
            } | ConvertTo-Json -Compress
            $RequestBytes = [System.Text.Encoding]::UTF8.GetBytes($Payload)
            $SendTask = $Client.SendAsync(
                [System.ArraySegment[byte]]::new($RequestBytes),
                [System.Net.WebSockets.WebSocketMessageType]::Text,
                $true,
                $Cancellation.Token
            )
            if (-not $SendTask.Wait([TimeSpan]::FromSeconds(2))) {
                throw "Timed out sending health request."
            }
            if ($SendTask.IsFaulted) {
                throw $SendTask.Exception
            }

            $Buffer = New-Object byte[] 8192
            $ResponseBuilder = [System.Text.StringBuilder]::new()
            do {
                $ReceiveTask = $Client.ReceiveAsync(
                    [System.ArraySegment[byte]]::new($Buffer),
                    $Cancellation.Token
                )
                if (-not $ReceiveTask.Wait([TimeSpan]::FromSeconds(2))) {
                    throw "Timed out waiting for health response."
                }
                if ($ReceiveTask.IsFaulted) {
                    throw $ReceiveTask.Exception
                }

                $Result = $ReceiveTask.Result
                if ($Result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    throw "WebSocket closed before health response."
                }

                [void]$ResponseBuilder.Append([System.Text.Encoding]::UTF8.GetString($Buffer, 0, $Result.Count))
            } while (-not $Result.EndOfMessage)

            $Response = $ResponseBuilder.ToString() | ConvertFrom-Json
            if ($Response.type -eq "agent.health.response" -and $Response.requestId -eq $RequestId) {
                if ($RequirePackageIdentity -and $Response.capabilities.packageIdentity -ne $true) {
                    Add-Content -Path $StartLogPath -Value "Health probe reached $Uri, but packageIdentity was not true."
                    Write-Host "VeilAgent answered health on $Uri, but package identity is not ready yet."
                    return $false
                }

                return $true
            }
        } catch {
            Add-Content -Path $StartLogPath -Value "Health probe attempt $Attempt failed: $($_.Exception.Message)"
        } finally {
            $Cancellation.Cancel()
            $Cancellation.Dispose()
            $Client.Dispose()
        }

        Start-Sleep -Milliseconds 500
    }

    return $false
}

function Get-VeilGuestIPv4Addresses {
    try {
        $Addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -and
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*" -and
                $_.IPAddress -ne "0.0.0.0"
            } |
            Select-Object -ExpandProperty IPAddress -Unique
        return @($Addresses)
    } catch {
        Add-Content -Path $StartLogPath -Value "Get-NetIPAddress failed while reading guest IPv4 addresses: $($_.Exception.Message)"
        return @()
    }
}

function Test-VeilAgentGuestAddressHealth {
    param(
        [int]$Port,
        [string[]]$Addresses,
        [switch]$RequirePackageIdentity
    )

    foreach ($Address in $Addresses) {
        Add-Content -Path $StartLogPath -Value "Testing agent.health.response on guest IPv4 address ws://${Address}:$Port/."
        if (Test-VeilAgentHealth -Port $Port -ProbeAddress $Address -Attempts 3 -RequirePackageIdentity:$RequirePackageIdentity) {
            Write-Host "VeilAgent answered agent.health.response on guest IPv4 address ws://${Address}:$Port/."
            Add-Content -Path $StartLogPath -Value "VeilAgent answered agent.health.response on guest IPv4 address ws://${Address}:$Port/."
            return $true
        }
    }

    return $false
}

$GuestIPv4Addresses = if ($RequireGuestAddress) { @(Get-VeilGuestIPv4Addresses) } else { @() }
if ($GuestIPv4Addresses.Count -gt 0) {
    $GuestIPv4Text = $GuestIPv4Addresses -join ", "
} else {
    $GuestIPv4Text = "none"
}
Add-Content -Path $StartLogPath -Value "Guest IPv4 addresses visible to Windows: $GuestIPv4Text"
Write-Host "Guest IPv4 addresses visible to Windows: $GuestIPv4Text"

$RunningAgent = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $AgentExe } |
    Select-Object -First 1
if ($RunningAgent) {
    Add-Content -Path $StartLogPath -Value "VeilAgent is already running from the installed app. PID=$($RunningAgent.Id)"
    $LoopbackReady = (Test-VeilAgentPort -Port $Port -ProbeAddress $ProbeHost) -and
        (Test-VeilAgentHealth -Port $Port -ProbeAddress $ProbeHost -RequirePackageIdentity:$RequirePackageIdentity)
    $GuestAddressReady = $false
    if ($RequireGuestAddress -and $GuestIPv4Addresses.Count -gt 0) {
        $GuestAddressReady = Test-VeilAgentGuestAddressHealth -Port $Port -Addresses $GuestIPv4Addresses -RequirePackageIdentity:$RequirePackageIdentity
    }
    if ($LoopbackReady -and ($GuestAddressReady -or -not $RequireGuestAddress)) {
        $ReadyDetail = if ($RequirePackageIdentity) { " with package identity" } else { "" }
        $AddressDetail = if ($GuestAddressReady) { " and a guest IPv4 address" } else { "; guest IPv4 verification was not required" }
        Add-Content -Path $StartLogPath -Value "Existing VeilAgent answered agent.health.response on loopback$AddressDetail$ReadyDetail."
        Write-Host "VeilAgent is already running on ${ListenHost}:$Port; loopback health succeeded$AddressDetail$ReadyDetail."
        exit 0
    }

    $FailureDetail = if ($RequirePackageIdentity) { " or package identity was not ready" } else { "" }
    $AddressRequirement = if ($RequireGuestAddress) { " and guest IPv4 health was required" } else { "" }
    Add-Content -Path $StartLogPath -Value "Existing VeilAgent process is present, but loopback health$AddressRequirement did not succeed$FailureDetail."
    throw "VeilAgent process is already running, but loopback health$AddressRequirement did not succeed$FailureDetail. Guest IPv4 addresses: $GuestIPv4Text. Run Collect-VeilAgentDiagnostics.ps1."
}

$env:VEIL_AGENT_HOST = $ListenHost
$env:VEIL_AGENT_PORT = "$Port"

$Process = Start-Process `
    -FilePath $AgentExe `
    -WorkingDirectory (Split-Path -Parent $AgentExe) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $StdOutLogPath `
    -RedirectStandardError $StdErrLogPath `
    -PassThru

Add-Content -Path $StartLogPath -Value "VeilAgent process started. PID=$($Process.Id)"

# Restarts the agent when it dies by itself. The agent only starts at logon, so a crash left Windows
# without it until the next restart; on the live guest an access violation in frame capture did that
# twice in one day. A hidden PowerShell waits for this agent process and reads how it ended.
#
# The supervisor runs from a copy of this text, with the values below filled in, so it does not depend
# on the console or the script that started it.
$SupervisorTemplate = @'
$ErrorActionPreference = "Stop"
$AgentProcessId = __AGENT_PID__
$StartScript = '__START_SCRIPT__'
$InstallRoot = '__INSTALL_ROOT__'
$Port = __PORT__
$LogPath = '__LOG_PATH__'
$RestartsPath = '__RESTARTS_PATH__'
try {
    $Agent = Get-Process -Id $AgentProcessId -ErrorAction Stop
    # Opening the handle now is what keeps the exit code readable after the process is gone.
    $null = $Agent.Handle
    $Agent.WaitForExit()
    $ExitCode = $Agent.ExitCode
} catch {
    exit 0
}
# Not restarted: 0 is the agent leaving by itself; -1 is Stop-Process, which is how an update or a
# repair stops it before starting the new one; -1073741510 is Windows closing it at sign-out or
# shutdown.
if ($ExitCode -eq 0 -or $ExitCode -eq -1 -or $ExitCode -eq -1073741510) {
    Add-Content -Path $LogPath -Value "VeilAgent $AgentProcessId ended with code $ExitCode at $(Get-Date -Format o); left stopped."
    exit 0
}
# At most five restarts in ten minutes, so an agent that dies at once does not start forever.
$Now = Get-Date
$Recent = @()
try {
    if (Test-Path $RestartsPath) {
        $Recent = @(Get-Content -Path $RestartsPath | Where-Object { $_ } | ForEach-Object { [datetime]::Parse($_) } | Where-Object { ($Now - $_).TotalMinutes -lt 10 })
    }
} catch {
    $Recent = @()
}
if ($Recent.Count -ge 5) {
    Add-Content -Path $LogPath -Value "VeilAgent $AgentProcessId ended with code $ExitCode at $(Get-Date -Format o); restarted five times in ten minutes already, so left stopped."
    exit 0
}
$Stamps = @($Recent | ForEach-Object { $_.ToString("o") }) + @($Now.ToString("o"))
Set-Content -Path $RestartsPath -Value $Stamps
Add-Content -Path $LogPath -Value "VeilAgent $AgentProcessId ended with code $ExitCode at $(Get-Date -Format o); restarting."
# Windows needs a moment to release the port and the agent's files.
Start-Sleep -Seconds 2
& $StartScript -InstallRoot $InstallRoot -Port $Port
'@

function Start-VeilAgentSupervisor {
    param([int]$AgentProcessId)

    # The installed copy, not the disc this script may be running from: the disc is ejected after an update.
    $InstalledStartScript = Join-Path $InstallRoot "scripts\Start-VeilAgent.ps1"
    $RestartScript = if (Test-Path $InstalledStartScript) { $InstalledStartScript } else { $PSCommandPath }
    $RestartsPath = Join-Path $LogRoot "restarts.log"
    # Single quotes are doubled because each value lands inside a single-quoted string.
    $Source = $SupervisorTemplate
    $Source = $Source.Replace("__AGENT_PID__", "$AgentProcessId")
    $Source = $Source.Replace("__START_SCRIPT__", $RestartScript.Replace("'", "''"))
    $Source = $Source.Replace("__INSTALL_ROOT__", $InstallRoot.Replace("'", "''"))
    $Source = $Source.Replace("__PORT__", "$Port")
    $Source = $Source.Replace("__LOG_PATH__", $StartLogPath.Replace("'", "''"))
    $Source = $Source.Replace("__RESTARTS_PATH__", $RestartsPath.Replace("'", "''"))
    $Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Source))
    $Supervisor = Start-Process `
        -FilePath "powershell.exe" `
        -WindowStyle Hidden `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $Encoded) `
        -PassThru
    Add-Content -Path $StartLogPath -Value "VeilAgent supervisor started. PID=$($Supervisor.Id) watching PID=$AgentProcessId"
}

try {
    Start-VeilAgentSupervisor -AgentProcessId $Process.Id
} catch {
    # The agent runs without a supervisor rather than not at all.
    Add-Content -Path $StartLogPath -Value "VeilAgent supervisor could not be started: $($_.Exception.Message)"
}

$LoopbackReady = (Test-VeilAgentPort -Port $Port -ProbeAddress $ProbeHost) -and
    (Test-VeilAgentHealth -Port $Port -ProbeAddress $ProbeHost -RequirePackageIdentity:$RequirePackageIdentity)
$GuestAddressReady = $false
if ($RequireGuestAddress -and $GuestIPv4Addresses.Count -gt 0) {
    $GuestAddressReady = Test-VeilAgentGuestAddressHealth -Port $Port -Addresses $GuestIPv4Addresses -RequirePackageIdentity:$RequirePackageIdentity
}
if ($LoopbackReady -and ($GuestAddressReady -or -not $RequireGuestAddress)) {
    $ReadyDetail = if ($RequirePackageIdentity) { " with package identity" } else { "" }
    $AddressDetail = if ($GuestAddressReady) { " and a guest IPv4 address" } else { "; guest IPv4 verification was not required" }
    Add-Content -Path $StartLogPath -Value "VeilAgent answered agent.health.response on loopback$AddressDetail$ReadyDetail."
    Write-Host "VeilAgent started on ${ListenHost}:$Port; loopback health succeeded$AddressDetail$ReadyDetail."
} else {
    $FailureDetail = if ($RequirePackageIdentity) { " or package identity was not ready" } else { "" }
    $AddressRequirement = if ($RequireGuestAddress) { " and guest IPv4 health was required" } else { "" }
    Add-Content -Path $StartLogPath -Value "VeilAgent process started, but loopback health$AddressRequirement did not succeed$FailureDetail. Guest IPv4 addresses: $GuestIPv4Text. See $StdOutLogPath and $StdErrLogPath."
    throw "VeilAgent process started, but loopback health$AddressRequirement did not succeed$FailureDetail. Guest IPv4 addresses: $GuestIPv4Text. Run Collect-VeilAgentDiagnostics.ps1."
}
