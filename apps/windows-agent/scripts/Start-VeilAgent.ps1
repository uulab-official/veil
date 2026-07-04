param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444
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
Add-Content -Path $StartLogPath -Value "VeilAgent start requested at $(Get-Date -Format o). InstallRoot=$InstallRoot Port=$Port"
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
        [int]$Attempts = 10
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
        [string[]]$Addresses
    )

    foreach ($Address in $Addresses) {
        Add-Content -Path $StartLogPath -Value "Testing agent.health.response on guest IPv4 address ws://${Address}:$Port/."
        if (Test-VeilAgentHealth -Port $Port -ProbeAddress $Address -Attempts 3) {
            Write-Host "VeilAgent answered agent.health.response on guest IPv4 address ws://${Address}:$Port/."
            Add-Content -Path $StartLogPath -Value "VeilAgent answered agent.health.response on guest IPv4 address ws://${Address}:$Port/."
            return $true
        }
    }

    return $false
}

$GuestIPv4Addresses = @(Get-VeilGuestIPv4Addresses)
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
    if (
        (Test-VeilAgentPort -Port $Port -ProbeAddress $ProbeHost) -and
        (Test-VeilAgentHealth -Port $Port -ProbeAddress $ProbeHost) -and
        $GuestIPv4Addresses.Count -gt 0 -and
        (Test-VeilAgentGuestAddressHealth -Port $Port -Addresses $GuestIPv4Addresses)
    ) {
        Add-Content -Path $StartLogPath -Value "Existing VeilAgent answered agent.health.response on loopback and a guest IPv4 address."
        Write-Host "VeilAgent is already running on ${ListenHost}:$Port; loopback and guest IPv4 agent.health.response probes succeeded."
        exit 0
    }

    Add-Content -Path $StartLogPath -Value "Existing VeilAgent process is present, but loopback plus guest IPv4 agent.health.response did not both succeed."
    throw "VeilAgent process is already running, but loopback plus guest IPv4 agent.health.response did not both succeed. Guest IPv4 addresses: $GuestIPv4Text. Run Collect-VeilAgentDiagnostics.ps1."
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

if (
    (Test-VeilAgentPort -Port $Port -ProbeAddress $ProbeHost) -and
    (Test-VeilAgentHealth -Port $Port -ProbeAddress $ProbeHost) -and
    $GuestIPv4Addresses.Count -gt 0 -and
    (Test-VeilAgentGuestAddressHealth -Port $Port -Addresses $GuestIPv4Addresses)
) {
    Add-Content -Path $StartLogPath -Value "VeilAgent answered agent.health.response on loopback and a guest IPv4 address."
    Write-Host "VeilAgent started on ${ListenHost}:$Port; loopback and guest IPv4 agent.health.response probes succeeded."
} else {
    Add-Content -Path $StartLogPath -Value "VeilAgent process started, but loopback plus guest IPv4 agent.health.response did not both succeed. Guest IPv4 addresses: $GuestIPv4Text. See $StdOutLogPath and $StdErrLogPath."
    throw "VeilAgent process started, but loopback plus guest IPv4 agent.health.response did not both succeed. Guest IPv4 addresses: $GuestIPv4Text. Run Collect-VeilAgentDiagnostics.ps1."
}
