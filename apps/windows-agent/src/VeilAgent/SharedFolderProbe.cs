using System.Diagnostics;
using System.Security.Principal;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Veil.Agent;

/// <summary>
/// Reports, and where possible prepares, the folder Windows shares back to macOS.
///
/// The share lives in the guest and is mounted on the Mac, rather than the other way around, because
/// that is the only direction with no host prerequisites: Windows ships an SMB server, macOS ships an
/// SMB client, and QEMU usermode networking already forwards a host port into the guest. The host-side
/// reasoning for ruling out virtio-9p, virtio-fs, and QEMU's built-in SMB lives in
/// QEMUWindowsSharedFolder.swift.
/// </summary>
public interface IWindowsSharedFolderProbe
{
    JsonObject ReadStatus(string shareName, string guestDirectoryPath);

    Task<JsonObject> EnsureAsync(string shareName, string guestDirectoryPath, CancellationToken cancellationToken);
}

/// <summary>
/// Operating-system operations the probe needs, behind a seam so the reported states can be tested
/// without creating real SMB shares.
/// </summary>
public interface ISharedFolderSystem
{
    bool IsWindows { get; }

    bool IsElevated { get; }

    bool IsServerListening { get; }

    bool DirectoryExists(string path);

    void CreateDirectory(string path);

    bool ShareExists(string shareName);

    bool CanWriteThroughShare(string shareName);

    bool TryCreateShare(string shareName, string directoryPath, out string? error);
}

public sealed class SharedFolderProbe : IWindowsSharedFolderProbe
{
    // Mirrors validateSharedFolderRequest in packages/protocol/src/messages.mjs. The share name and
    // path reach a PowerShell command line, so they are validated here rather than trusted, even
    // though the host is the only sender.
    private static readonly Regex SafeShareName = new("^[A-Za-z0-9._-]{1,64}$", RegexOptions.Compiled);
    private static readonly Regex SafeGuestDirectoryPath = new(
        @"^[A-Za-z]:\\[^""'|&;<>%\r\n]*$",
        RegexOptions.Compiled
    );

    // Mirrors QEMUWindowsSharedFolderTransport.shareName / .guestDirectoryPath on the host. The host
    // sends both on every request so the two sides cannot silently disagree; these are only the
    // fallbacks used when reporting status without a request, such as inside the health response.
    public const string DefaultShareName = "VeilShared";
    public const string DefaultGuestDirectoryPath = @"C:\VeilShared";

    private readonly ISharedFolderSystem system;

    public SharedFolderProbe(ISharedFolderSystem? system = null)
    {
        this.system = system ?? new WindowsSharedFolderSystem();
    }

    public JsonObject ReadStatus(string shareName, string guestDirectoryPath)
    {
        if (!system.IsWindows)
        {
            return Status(
                shareName,
                guestDirectoryPath,
                isSupported: false,
                directoryExists: false,
                isShared: false,
                isWritable: false,
                serverListening: false,
                requiresElevation: false,
                recommendedAction: "unsupported-on-this-host",
                message: "Folder sharing needs the Windows SMB server, which only exists on Windows."
            );
        }

        if (!IsRequestSafe(shareName, guestDirectoryPath, out var rejection))
        {
            return Status(
                shareName,
                guestDirectoryPath,
                isSupported: true,
                directoryExists: false,
                isShared: false,
                isWritable: false,
                serverListening: false,
                requiresElevation: false,
                recommendedAction: "invalid-request",
                message: rejection
            );
        }

        var directoryExists = system.DirectoryExists(guestDirectoryPath);
        var serverListening = system.IsServerListening;
        // A share cannot be reported without the directory behind it: the host treats that combination
        // as a guest bug, and it would send someone debugging the Mac mount instead of the guest.
        var isShared = directoryExists && system.ShareExists(shareName);
        var isWritable = isShared && system.CanWriteThroughShare(shareName);

        return Status(
            shareName,
            guestDirectoryPath,
            isSupported: true,
            directoryExists: directoryExists,
            isShared: isShared,
            isWritable: isWritable,
            serverListening: serverListening,
            // Publishing an SMB share always needs an administrator, so this stays true until the share
            // exists. It describes the remaining work, not the agent's current token.
            requiresElevation: !isShared,
            recommendedAction: RecommendedAction(
                directoryExists: directoryExists,
                isShared: isShared,
                isWritable: isWritable,
                serverListening: serverListening
            )
        );
    }

    public async Task<JsonObject> EnsureAsync(
        string shareName,
        string guestDirectoryPath,
        CancellationToken cancellationToken
    )
    {
        if (!system.IsWindows || !IsRequestSafe(shareName, guestDirectoryPath, out _))
        {
            return ReadStatus(shareName, guestDirectoryPath);
        }

        string? message = null;

        if (!system.DirectoryExists(guestDirectoryPath))
        {
            try
            {
                // Works without elevation: the default ACL on a drive root already lets a standard user
                // create a directory there. Publishing the share is the part that needs an administrator.
                system.CreateDirectory(guestDirectoryPath);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                message = $"Could not create {guestDirectoryPath}: {error.Message}";
            }
        }

        if (message is null
            && system.DirectoryExists(guestDirectoryPath)
            && !system.ShareExists(shareName))
        {
            if (system.IsElevated)
            {
                if (!system.TryCreateShare(shareName, guestDirectoryPath, out var shareError))
                {
                    message = shareError ?? "Creating the SMB share failed.";
                }
            }
            else
            {
                message = "The agent created the folder but cannot publish an SMB share without administrator rights.";
            }
        }

        await Task.CompletedTask;

        var status = ReadStatus(shareName, guestDirectoryPath);
        if (message is not null)
        {
            status["message"] = message;
        }

        return status;
    }

    /// <summary>
    /// Exact command a user runs in an elevated PowerShell to publish the share.
    /// </summary>
    public static string ShareCommand(string shareName, string guestDirectoryPath) =>
        $"New-SmbShare -Name {shareName} -Path {guestDirectoryPath} -FullAccess $env:USERNAME";

    private static bool IsRequestSafe(string shareName, string guestDirectoryPath, out string? rejection)
    {
        if (string.IsNullOrEmpty(shareName) || !SafeShareName.IsMatch(shareName))
        {
            rejection = "shareName must be 1-64 characters of letters, digits, dot, dash, or underscore.";
            return false;
        }

        if (string.IsNullOrEmpty(guestDirectoryPath)
            || !SafeGuestDirectoryPath.IsMatch(guestDirectoryPath)
            || guestDirectoryPath.Contains("..", StringComparison.Ordinal))
        {
            rejection = "guestDirectoryPath must be an absolute Windows path with no traversal or shell metacharacters.";
            return false;
        }

        rejection = null;
        return true;
    }

    private static string RecommendedAction(
        bool directoryExists,
        bool isShared,
        bool isWritable,
        bool serverListening
    )
    {
        if (!serverListening)
        {
            return "enable-smb-firewall";
        }

        if (!directoryExists)
        {
            return "create-guest-directory";
        }

        if (!isShared)
        {
            return "create-share-elevated";
        }

        return isWritable ? "mount-on-mac" : "grant-share-write-access";
    }

    private static JsonObject Status(
        string shareName,
        string guestDirectoryPath,
        bool isSupported,
        bool directoryExists,
        bool isShared,
        bool isWritable,
        bool serverListening,
        bool requiresElevation,
        string recommendedAction,
        string? message = null
    )
    {
        var status = new JsonObject
        {
            ["isSupported"] = isSupported,
            ["shareName"] = shareName,
            ["guestDirectoryPath"] = guestDirectoryPath,
            ["directoryExists"] = directoryExists,
            ["isShared"] = isShared,
            ["isWritable"] = isWritable,
            ["serverListening"] = serverListening,
            ["requiresElevation"] = requiresElevation,
            // Not a detection. SMB refuses a network sign-in for a blank-password account, and the agent
            // does not inspect password state, so this reports the standing requirement rather than
            // claiming to have checked it. The password is supplied to macOS at mount time and never
            // travels over this protocol.
            ["requiresCredentials"] = isSupported,
            ["recommendedAction"] = recommendedAction
        };

        // Required by the protocol validator exactly when elevation is what is blocking the share, so
        // the host never has to invent the command itself.
        if (requiresElevation && !isShared)
        {
            status["shareCommand"] = ShareCommand(shareName, guestDirectoryPath);
        }

        if (message is not null)
        {
            status["message"] = message;
        }

        return status;
    }
}

public sealed class WindowsSharedFolderSystem : ISharedFolderSystem
{
    private const string LoopbackHost = "localhost";

    public bool IsWindows => OperatingSystem.IsWindows();

    public bool IsElevated
    {
        get
        {
            if (!OperatingSystem.IsWindows())
            {
                return false;
            }

            try
            {
                using var identity = WindowsIdentity.GetCurrent();
                return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch (Exception error) when (error is UnauthorizedAccessException or InvalidOperationException)
            {
                return false;
            }
        }
    }

    /// <summary>
    /// Reached through the loopback SMB path rather than by inspecting services, because that answers
    /// the question the Mac actually asks: can something connect and enumerate a share. A share that
    /// exists while the firewall drops every connection looks identical from macOS, so it must not look
    /// healthy here.
    /// </summary>
    public bool IsServerListening => SafeDirectoryExists($@"\\{LoopbackHost}\IPC$");

    public bool DirectoryExists(string path) => SafeDirectoryExists(path);

    public void CreateDirectory(string path) => Directory.CreateDirectory(path);

    public bool ShareExists(string shareName) => SafeDirectoryExists($@"\\{LoopbackHost}\{shareName}");

    public bool CanWriteThroughShare(string shareName)
    {
        // Writability is tested through the share, not the local folder. Local write access says nothing
        // about the share permissions the Mac will be subject to.
        var probePath = Path.Combine($@"\\{LoopbackHost}\{shareName}", $".veil-write-probe-{Guid.NewGuid():N}");
        try
        {
            File.WriteAllBytes(probePath, []);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }
        finally
        {
            try
            {
                if (File.Exists(probePath))
                {
                    File.Delete(probePath);
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                // A leftover zero-byte probe file is preferable to failing the status report over it.
            }
        }
    }

    public bool TryCreateShare(string shareName, string directoryPath, out string? error)
    {
        // Argument list rather than a command string, and single-quoted values whose contents the caller
        // has already restricted to characters that cannot terminate a quote.
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(
            $"New-SmbShare -Name '{shareName}' -Path '{directoryPath}' -FullAccess $env:USERNAME"
        );

        try
        {
            using var process = Process.Start(startInfo);
            if (process is null)
            {
                error = "PowerShell could not be started to create the SMB share.";
                return false;
            }

            var standardError = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode == 0)
            {
                error = null;
                return true;
            }

            error = string.IsNullOrWhiteSpace(standardError)
                ? $"New-SmbShare exited with code {process.ExitCode}."
                : standardError.Trim();
            return false;
        }
        catch (Exception failure)
        {
            error = $"{failure.GetType().Name}: {failure.Message}";
            return false;
        }
    }

    private static bool SafeDirectoryExists(string path)
    {
        try
        {
            return Directory.Exists(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
