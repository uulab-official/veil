param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-arm64",
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Resolve-Path (Join-Path $ScriptRoot "..")
$ProjectPath = Join-Path $AgentRoot "src\VeilAgent\VeilAgent.csproj"
$BundleRoot = Join-Path $AgentRoot "app"
$SelfContained = -not $FrameworkDependent

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet was not found. Install the .NET 8 SDK before publishing the Veil guest agent bundle."
}

if (Test-Path $BundleRoot) {
    Remove-Item -Path $BundleRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $BundleRoot | Out-Null

dotnet publish $ProjectPath `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained:$SelfContained `
    --output $BundleRoot

$AgentExe = Join-Path $BundleRoot "VeilAgent.exe"
if (-not (Test-Path $AgentExe)) {
    throw "dotnet publish completed, but VeilAgent.exe was not found at $AgentExe."
}

Write-Host "VeilAgent bundle published to $BundleRoot."
Write-Host "Run Install Veil Agent.cmd from the same bundle inside Windows to install without the .NET SDK."
