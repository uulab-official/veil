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
$BackupRoot = Join-Path $AgentRoot "app.previous"
$BundleLockPath = Join-Path $AgentRoot ".veil-agent-bundle.lock"
$PublishStagingRoot = Join-Path $AgentRoot ".publish-staging-$([Guid]::NewGuid().ToString('N'))"
$PublishNextRoot = Join-Path $PublishStagingRoot "next"
$PublishPreviousRoot = Join-Path $PublishStagingRoot "previous"
$SelfContained = -not $FrameworkDependent

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet was not found. Install the .NET 8 SDK before publishing the Veil guest agent bundle."
}

$BundleLockStream = $null
$bundleLockAcquired = $false
$publishRetiredCurrent = $false
$publishPromoted = $false
$preservePublishRecovery = $false
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

    New-Item -ItemType Directory -Force -Path $PublishNextRoot | Out-Null
    # Compile beside the live bundle. A failed compiler must never turn a working guest
    # agent into an empty directory.
    dotnet publish $ProjectPath `
        --configuration $Configuration `
        --runtime $Runtime `
        --self-contained:$SelfContained `
        -p:EnableWindowsTargeting=true `
        --output $PublishNextRoot
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE."
    }

    $RequiredArtifacts = @(
        "VeilAgent.exe",
        "VeilAgent.dll",
        "VeilAgent.deps.json",
        "VeilAgent.runtimeconfig.json"
    )
    foreach ($Artifact in $RequiredArtifacts) {
        $ArtifactPath = Join-Path $PublishNextRoot $Artifact
        if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) -or (Get-Item -LiteralPath $ArtifactPath).Length -eq 0) {
            throw "dotnet publish did not produce a complete bundle: missing or empty $ArtifactPath."
        }
    }

    if (Test-Path -LiteralPath $BundleRoot) {
        Move-Item -LiteralPath $BundleRoot -Destination $PublishPreviousRoot
        $publishRetiredCurrent = $true
    }
    Move-Item -LiteralPath $PublishNextRoot -Destination $BundleRoot
    $publishPromoted = $true

    if ($publishRetiredCurrent) {
        # Keep the previous complete bundle for recovery. The live bundle is already
        # usable before this rotation starts.
        if (Test-Path -LiteralPath $BackupRoot) {
            Remove-Item -LiteralPath $BackupRoot -Recurse -Force
        }
        Move-Item -LiteralPath $PublishPreviousRoot -Destination $BackupRoot
    }

    Write-Host "VeilAgent bundle published to $BundleRoot."
    if (Test-Path -LiteralPath $BackupRoot) {
        Write-Host "Previous VeilAgent bundle retained at $BackupRoot."
    }
    Write-Host "Run Install Veil Agent.cmd from the same bundle inside Windows to install without the .NET SDK."
} catch {
    if ($publishRetiredCurrent -and -not $publishPromoted -and -not (Test-Path -LiteralPath $BundleRoot) -and (Test-Path -LiteralPath $PublishPreviousRoot)) {
        try {
            Move-Item -LiteralPath $PublishPreviousRoot -Destination $BundleRoot
            Write-Warning "Publish failed; the previous VeilAgent bundle was restored."
        } catch {
            $preservePublishRecovery = $true
            Write-Warning "Publish failed and rollback could not complete. Recover the previous bundle from $PublishPreviousRoot."
        }
    } elseif ($publishRetiredCurrent -and (Test-Path -LiteralPath $PublishPreviousRoot)) {
        $preservePublishRecovery = $true
        Write-Warning "Publish failed after promotion; the previous bundle is retained at $PublishPreviousRoot."
    }
    throw
} finally {
    try {
        if (-not $preservePublishRecovery -and (Test-Path -LiteralPath $PublishStagingRoot)) {
            Remove-Item -LiteralPath $PublishStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
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
