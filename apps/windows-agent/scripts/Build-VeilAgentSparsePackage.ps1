param(
    [string]$PackageVersion = "0.1.0.0",
    [string]$Publisher = "CN=UULab",
    [string]$PackageName = "UULab.Veil.Agent",
    [string]$ApplicationId = "VeilAgent",
    [string]$OutputRoot = "",
    [string]$CertificatePfxPath = "",
    [string]$CertificatePassword = "",
    [switch]$CreateDevelopmentCertificate,
    [switch]$TrustDevelopmentCertificate
)

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentRoot = Resolve-Path (Join-Path $ScriptRoot "..")
$PackageRoot = Join-Path $AgentRoot "package"
$SourceManifestPath = Join-Path $PackageRoot "AppxManifest.xml"
$OutputRoot = if ($OutputRoot) { $OutputRoot } else { $PackageRoot }
$PackagePath = Join-Path $OutputRoot "VeilAgent.Identity.msix"
$DevelopmentCertificatePath = Join-Path $OutputRoot "VeilAgent.Identity.cer"
$DevelopmentPfxPath = Join-Path $OutputRoot "VeilAgent.Identity.pfx"

function Resolve-WindowsSdkTool {
    param([string]$ToolName)

    $Command = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }

    $WindowsKitsRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (-not (Test-Path $WindowsKitsRoot)) {
        throw "$ToolName was not found and Windows SDK bin directory does not exist at $WindowsKitsRoot."
    }

    $Candidates = Get-ChildItem -Path $WindowsKitsRoot -Recurse -Filter $ToolName -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\(x64|arm64|x86)\\$([regex]::Escape($ToolName))$" } |
        Sort-Object FullName -Descending
    if (-not $Candidates) {
        throw "$ToolName was not found. Install the Windows SDK before building the Veil sparse package."
    }

    return $Candidates[0].FullName
}

if (-not (Test-Path $SourceManifestPath)) {
    throw "Sparse package manifest was not found at $SourceManifestPath."
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

if ($CreateDevelopmentCertificate) {
    $PasswordText = if ($CertificatePassword) { $CertificatePassword } else { "veil-development" }
    $SecurePassword = ConvertTo-SecureString -String $PasswordText -Force -AsPlainText
    $Certificate = New-SelfSignedCertificate `
        -Type Custom `
        -Subject $Publisher `
        -KeyUsage DigitalSignature `
        -FriendlyName "Veil Agent development package signing" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
    Export-PfxCertificate -Cert $Certificate -FilePath $DevelopmentPfxPath -Password $SecurePassword | Out-Null
    Export-Certificate -Cert $Certificate -FilePath $DevelopmentCertificatePath | Out-Null
    $CertificatePfxPath = $DevelopmentPfxPath
    $CertificatePassword = $PasswordText
    Write-Host "Created development signing certificate at $DevelopmentPfxPath and public certificate at $DevelopmentCertificatePath."
}

if (-not $CertificatePfxPath) {
    throw "Provide -CertificatePfxPath or pass -CreateDevelopmentCertificate."
}
if (-not (Test-Path $CertificatePfxPath)) {
    throw "Certificate PFX was not found at $CertificatePfxPath."
}

$MakeAppx = Resolve-WindowsSdkTool "MakeAppx.exe"
$SignTool = Resolve-WindowsSdkTool "SignTool.exe"
$StagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("VeilAgentSparsePackage-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $StagingRoot | Out-Null

try {
    $ManifestXml = Get-Content -Path $SourceManifestPath -Raw
    $ManifestXml = $ManifestXml `
        -replace 'Name="UULab\.Veil\.Agent"', "Name=`"$PackageName`"" `
        -replace 'Publisher="CN=UULab"', "Publisher=`"$Publisher`"" `
        -replace 'Version="0\.1\.0\.0"', "Version=`"$PackageVersion`"" `
        -replace 'Id="VeilAgent"', "Id=`"$ApplicationId`""
    $ManifestXml | Set-Content -Path (Join-Path $StagingRoot "AppxManifest.xml") -Encoding UTF8

    if (Test-Path $PackagePath) {
        Remove-Item -Path $PackagePath -Force
    }

    & $MakeAppx pack /o /d $StagingRoot /nv /p $PackagePath
    if ($LASTEXITCODE -ne 0) {
        throw "MakeAppx.exe failed with exit code $LASTEXITCODE."
    }

    $SignArguments = @("sign", "/fd", "SHA256", "/f", $CertificatePfxPath)
    if ($CertificatePassword) {
        $SignArguments += @("/p", $CertificatePassword)
    }
    $SignArguments += $PackagePath

    & $SignTool @SignArguments
    if ($LASTEXITCODE -ne 0) {
        throw "SignTool.exe failed with exit code $LASTEXITCODE."
    }
} finally {
    if (Test-Path $StagingRoot) {
        Remove-Item -Path $StagingRoot -Recurse -Force
    }
}

if ($TrustDevelopmentCertificate) {
    if (-not (Test-Path $DevelopmentCertificatePath)) {
        $Certificate = Get-PfxCertificate -FilePath $CertificatePfxPath
        Export-Certificate -Cert $Certificate -FilePath $DevelopmentCertificatePath | Out-Null
    }
    Import-Certificate -FilePath $DevelopmentCertificatePath -CertStoreLocation Cert:\CurrentUser\TrustedPeople | Out-Null
    Write-Host "Trusted development certificate in Cert:\CurrentUser\TrustedPeople."
}

Write-Host "Veil sparse identity package built and signed at $PackagePath."
