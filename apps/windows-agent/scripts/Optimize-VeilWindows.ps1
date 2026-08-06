param(
    [Parameter(Mandatory = $true)]
    [string]$GuestToolsPath,
    [Parameter(Mandatory = $true)]
    [string]$RepairScriptPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\Veil\Agent",
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"

function Test-VeilAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-VeilElevatedOptimization {
    $ArgumentLine = @(
        "-NoProfile",
        "-ExecutionPolicy Bypass",
        "-File `"$PSCommandPath`"",
        "-GuestToolsPath `"$GuestToolsPath`"",
        "-RepairScriptPath `"$RepairScriptPath`"",
        "-InstallRoot `"$InstallRoot`"",
        "-Elevated"
    ) -join " "

    $Process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList $ArgumentLine `
        -Verb RunAs `
        -WindowStyle Normal `
        -Wait `
        -PassThru `
        -ErrorAction Stop
    exit $Process.ExitCode
}

if (-not (Test-VeilAdministrator)) {
    Invoke-VeilElevatedOptimization
}

if (-not (Test-Path -LiteralPath $GuestToolsPath)) {
    throw "UTM Guest Tools installer was not found at $GuestToolsPath."
}
if (-not (Test-Path -LiteralPath $RepairScriptPath)) {
    throw "Veil agent repair script was not found at $RepairScriptPath."
}

Write-Host "Installing UTM Guest Tools from $GuestToolsPath."
$GuestToolsProcess = Start-Process `
    -FilePath $GuestToolsPath `
    -ArgumentList "/S" `
    -Wait `
    -PassThru `
    -WindowStyle Hidden
if ($GuestToolsProcess.ExitCode -ne 0) {
    throw "UTM Guest Tools installer exited with code $($GuestToolsProcess.ExitCode)."
}

Write-Host "Repairing Veil agent connectivity with the same elevated approval."
& $RepairScriptPath -InstallRoot $InstallRoot -Elevated
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw "Veil agent connectivity repair exited with code $LASTEXITCODE."
}

Write-Host "Windows optimization completed."
