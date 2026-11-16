using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// Installs Triton's GPU driver (<c>viogpu3d</c>) from the disc the host put in the removable drive, after the
/// user approves Windows' administrator prompt (<c>gpu.driver.install.request</c>).
/// </summary>
/// <remarks>
/// The host sends this only while Windows runs on Veil's GPU runtime: on the software runtime the driver
/// would take the display away (docs/checklists/2026-11-10-triton-gpu-acceleration-evaluation.md).
///
/// The request names nothing. The elevated script finds the disc labelled <see cref="VolumeLabel"/> itself,
/// copies the package into a new folder under the Windows directory, and checks there, after the copy and
/// before anything runs, that the catalog and the INF are byte for byte the ones Veil ships and that the
/// catalog's signature is valid. The catalog holds the hash of every other file in the package, and pnputil
/// refuses a package whose files do not match it. A program running as the user that mounts its own disc
/// with this label therefore gets nothing installed but this exact driver, and asking for administrator
/// approval is something it could already do by itself.
/// </remarks>
public sealed class GpuDriverInstall
{
    public const string VolumeLabel = "VEIL_GPU";
    public const string PackageFolder = "viogpu3d";
    public const string InfFileName = "viogpu3d.inf";
    /// <summary>The service the INF installs for the display device.</summary>
    public const string ServiceName = "VioGpu3D";

    /// <summary>
    /// SHA-256 of the package files that pin it: osy/kvm-guest-drivers-windows v0.5,
    /// <c>viogpu3d-arm64x-signed.zip</c> (attestation-signed by Microsoft), the build Veil ships.
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> PinnedHashes = new Dictionary<string, string>
    {
        ["viogpu3d.cat"] = "a7a8f2b5ae8c323b5a8108a9793f3f6b4ecf2103f317c02038351ff3300380b9",
        ["viogpu3d.inf"] = "3bc89b2ff4687477f644d882cd0361fcf710766e2bd06ade5e03ba50a1914326"
    };

    private readonly IElevatedLauncher launcher;
    private readonly Func<IEnumerable<ToolsUpdateDrive>> opticalDrives;
    private readonly Func<string, bool> fileExists;
    private readonly Func<bool> isInstalled;
    private readonly string statusPath;
    private int running;
    private volatile string? declinedAt;

    public GpuDriverInstall(
        IElevatedLauncher? launcher = null,
        Func<IEnumerable<ToolsUpdateDrive>>? opticalDrives = null,
        Func<string, bool>? fileExists = null,
        Func<bool>? isInstalled = null,
        string? statusPath = null)
    {
        this.launcher = launcher ?? new WindowsElevatedLauncher();
        this.opticalDrives = opticalDrives ?? ToolsUpdate.ReadyOpticalDrives;
        this.fileExists = fileExists ?? File.Exists;
        this.isInstalled = isInstalled ?? (() => VirtioGpuDisplay.IsDriverInstalled(ServiceName));
        this.statusPath = statusPath ?? DefaultStatusPath;
    }

    /// <summary>Where the elevated script records how the last install ended; readable by the user.</summary>
    public static string DefaultStatusPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Veil", "gpu-driver-install.json");

    /// <summary>
    /// Asks for approval and answers at once: the prompt may wait for the user for minutes. The outcome is
    /// read from health (<see cref="Status"/>).
    /// </summary>
    public JsonObject Start()
    {
        if (!launcher.IsWindows)
        {
            return Outcome(false, "unsupported", "This agent is not running on Windows.");
        }
        if (isInstalled())
        {
            return Outcome(true, "already-installed", null);
        }
        if (FindPackageInf() is null)
        {
            return Outcome(true, "media-missing", $"No disc labelled {VolumeLabel} with {PackageFolder}\\{InfFileName} is in a drive.");
        }
        if (Interlocked.Exchange(ref running, 1) != 0)
        {
            return Outcome(true, "already-running", "Windows is already asking for approval.");
        }

        declinedAt = null;
        var script = InstallScript();
        _ = Task.Run(() =>
        {
            try
            {
                if (!launcher.RunElevatedPowerShell(script))
                {
                    declinedAt = DateTimeOffset.UtcNow.ToString("o");
                    Console.Error.WriteLine("GpuDriverInstall: the approval prompt was declined.");
                }
            }
            catch (Exception error)
            {
                Console.Error.WriteLine($"GpuDriverInstall: {error.GetType().Name}: {error.Message}");
            }
            finally
            {
                Volatile.Write(ref running, 0);
            }
        });
        return Outcome(true, "approval-requested", null);
    }

    /// <summary>For health: whether the driver is installed, and how the last attempt ended.</summary>
    public JsonObject Status()
    {
        var status = new JsonObject
        {
            ["installed"] = launcher.IsWindows && isInstalled(),
            ["installing"] = Volatile.Read(ref running) != 0
        };
        if (declinedAt is { } declined)
        {
            status["lastInstall"] = new JsonObject { ["outcome"] = "declined", ["finishedAt"] = declined };
        }
        else if (ReadLastInstall() is { } last)
        {
            status["lastInstall"] = last;
        }
        return status;
    }

    internal string? FindPackageInf() =>
        opticalDrives()
            .Where(drive => string.Equals(drive.VolumeLabel, VolumeLabel, StringComparison.OrdinalIgnoreCase))
            .Select(drive => (drive.Root.EndsWith('\\') ? drive.Root : drive.Root + "\\") + PackageFolder + "\\" + InfFileName)
            .FirstOrDefault(fileExists);

    private JsonObject? ReadLastInstall()
    {
        try
        {
            if (!File.Exists(statusPath))
            {
                return null;
            }
            // Written by Windows PowerShell 5.1 as UTF-8 with a byte order mark, which ReadAllText skips.
            if (JsonNode.Parse(File.ReadAllText(statusPath)) is not JsonObject recorded)
            {
                return null;
            }
            // Only the expected fields, each a short string or a number: the file sits where other programs
            // running as the user could write it.
            var result = new JsonObject();
            foreach (var key in new[] { "outcome", "finishedAt", "message" })
            {
                if (recorded[key] is JsonValue value && value.TryGetValue<string>(out var text))
                {
                    result[key] = text.Length > 400 ? text[..400] : text;
                }
            }
            if (recorded["exitCode"] is JsonValue code && code.TryGetValue<int>(out var exitCode))
            {
                result["exitCode"] = exitCode;
            }
            return result.Count == 0 ? null : result;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            return null;
        }
    }

    private static JsonObject Outcome(bool isSupported, string outcome, string? message) => new()
    {
        ["isSupported"] = isSupported,
        ["outcome"] = outcome,
        ["message"] = message
    };

    /// <summary>
    /// The PowerShell run as administrator. It takes no input from the request or from the user's files:
    /// the label, folder, hashes and paths are all fixed here. pnputil exit code 3010 means installed, with
    /// a restart to finish.
    /// </summary>
    internal static string InstallScript()
    {
        var hashes = string.Join("; ", PinnedHashes.Select(pair => $"'{pair.Key}' = '{pair.Value}'"));
        return string.Join("\n", [
            "$ErrorActionPreference = 'Stop'",
            "$statusDirectory = Join-Path $env:ProgramData 'Veil'",
            "$statusPath = Join-Path $statusDirectory 'gpu-driver-install.json'",
            "function Write-VeilStatus([string]$outcome, $exitCode, [string]$message) {",
            "  New-Item -ItemType Directory -Force -Path $statusDirectory | Out-Null",
            "  if ($message.Length -gt 400) { $message = $message.Substring(0, 400) }",
            "  [ordered]@{ outcome = $outcome; exitCode = $exitCode; message = $message; finishedAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress | Set-Content -LiteralPath $statusPath -Encoding UTF8",
            "}",
            "$work = Join-Path $env:SystemRoot ('Temp\\veil-gpu-driver-' + [guid]::NewGuid().ToString('N'))",
            "try {",
            $"  $volume = Get-Volume | Where-Object {{ $_.FileSystemLabel -eq '{VolumeLabel}' -and $_.DriveType -eq 'CD-ROM' -and $_.DriveLetter }} | Select-Object -First 1",
            $"  if (-not $volume) {{ Write-VeilStatus 'media-missing' $null 'No {VolumeLabel} disc is in a drive.'; exit 1 }}",
            $"  $source = $volume.DriveLetter + ':\\{PackageFolder}'",
            "  New-Item -ItemType Directory -Path $work | Out-Null",
            "  Copy-Item -Path (Join-Path $source '*') -Destination $work",
            $"  $expected = @{{ {hashes} }}",
            "  foreach ($name in $expected.Keys) {",
            "    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $work $name)).Hash.ToLowerInvariant()",
            "    if ($hash -ne $expected[$name]) { Write-VeilStatus 'rejected-package' $null ($name + ' is not the driver package Veil ships.'); exit 1 }",
            "  }",
            "  $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $work 'viogpu3d.cat')",
            "  if ($signature.Status -ne 'Valid') { Write-VeilStatus 'rejected-package' $null ('The driver catalog signature is ' + $signature.Status + '.'); exit 1 }",
            $"  $output = & (Join-Path $env:SystemRoot 'System32\\pnputil.exe') /add-driver (Join-Path $work '{InfFileName}') /install 2>&1 | Out-String",
            "  $code = $LASTEXITCODE",
            "  if ($code -eq 0 -or $code -eq 3010) { Write-VeilStatus 'installed' $code $null } else { Write-VeilStatus 'failed' $code $output.Trim() }",
            "} catch {",
            "  Write-VeilStatus 'failed' $null $_.Exception.Message",
            "} finally {",
            "  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }",
            "}"
        ]);
    }
}
