param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [int]$Port = 18444
)

$ErrorActionPreference = "Stop"

$LogRoot = Join-Path $InstallRoot "logs"
$LogPath = Join-Path $LogRoot "bootstrap.log"
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

Start-Transcript -Path $LogPath -Append | Out-Null
try {
    Write-Host "Bootstrap-VeilAgentFromMedia started at $(Get-Date -Format o)."
    Write-Host "ScriptRoot=$PSScriptRoot"
    Write-Host "InstallRoot=$InstallRoot"
    Write-Host "Port=$Port"

    $AgentRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $Installer = Join-Path $AgentRoot "Install Veil Agent.cmd"
    if (-not (Test-Path $Installer)) {
        throw "Install Veil Agent.cmd was not found at $Installer."
    }

    Write-Host "Running $Installer"
    $Process = Start-Process `
        -FilePath $Installer `
        -ArgumentList @("-InstallRoot", "`"$InstallRoot`"", "-Port", "$Port") `
        -WorkingDirectory $AgentRoot `
        -WindowStyle Minimized `
        -Wait `
        -PassThru

    Write-Host "Installer exited with code $($Process.ExitCode)."
    if ($Process.ExitCode -ne 0) {
        throw "Install Veil Agent.cmd exited with code $($Process.ExitCode)."
    }
} finally {
    Stop-Transcript | Out-Null
}
