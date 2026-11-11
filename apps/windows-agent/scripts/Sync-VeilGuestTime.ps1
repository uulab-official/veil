# Runs as SYSTEM from the VeilTimeSync scheduled task, which Install-VeilAgent.ps1 registers when it
# runs elevated. The limited-token agent starts the task after the Mac reports a stale guest clock.
#
# Deliberately takes no input. Accepting the host's time here would let any program running as the
# user set the system clock to anything, so this only asks W32Time to resync from network time.
$ErrorActionPreference = "Continue"

$Service = Get-Service -Name w32time -ErrorAction SilentlyContinue
if (-not $Service) {
    Write-Error "W32Time service is not installed."
    exit 1
}
if ($Service.Status -ne "Running") {
    Start-Service -Name w32time
    Start-Sleep -Seconds 2
}

# A freshly started W32Time can answer "no time data was available" until it has polled its peer,
# so retry briefly instead of failing the first attempt.
for ($Attempt = 1; $Attempt -le 4; $Attempt++) {
    w32tm /resync /rediscover | Out-Null
    if ($LASTEXITCODE -eq 0) {
        exit 0
    }
    Start-Sleep -Seconds 5
}

exit $LASTEXITCODE
