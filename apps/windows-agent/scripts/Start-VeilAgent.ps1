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

$RunningAgent = Get-Process -Name "VeilAgent" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $AgentExe } |
    Select-Object -First 1
if ($RunningAgent) {
    Add-Content -Path $StartLogPath -Value "VeilAgent is already running from the installed app. PID=$($RunningAgent.Id)"
    if (Test-VeilAgentPort -Port $Port -ProbeAddress $ProbeHost) {
        Add-Content -Path $StartLogPath -Value "Existing VeilAgent is listening on ${ListenHost}:$Port; local probe ws://${ProbeHost}:$Port/ succeeded."
        Write-Host "VeilAgent is already running on ${ListenHost}:$Port; local probe ws://${ProbeHost}:$Port/ succeeded."
        exit 0
    }

    Add-Content -Path $StartLogPath -Value "Existing VeilAgent process is present, but port $Port is not reachable yet."
    throw "VeilAgent process is already running, but ws://${ProbeHost}:$Port/ is not reachable. Run Collect-VeilAgentDiagnostics.ps1."
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

if (Test-VeilAgentPort -Port $Port -ProbeAddress $ProbeHost) {
    Add-Content -Path $StartLogPath -Value "VeilAgent is listening on ${ListenHost}:$Port; local probe ws://${ProbeHost}:$Port/ succeeded."
    Write-Host "VeilAgent started on ${ListenHost}:$Port; local probe ws://${ProbeHost}:$Port/ succeeded."
} else {
    Add-Content -Path $StartLogPath -Value "VeilAgent process started, but ws://${ProbeHost}:$Port/ did not become reachable. See $StdOutLogPath and $StdErrLogPath."
    throw "VeilAgent process started, but ws://${ProbeHost}:$Port/ did not become reachable. Run Collect-VeilAgentDiagnostics.ps1."
}
