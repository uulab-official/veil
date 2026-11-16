using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;
using System.Text;
using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>Starts a program with administrator rights, which Windows asks the user to approve.</summary>
public interface IElevatedLauncher
{
    bool IsWindows { get; }

    /// <summary>The current user's SID, or null when it cannot be read.</summary>
    string? CurrentUserSid { get; }

    /// <summary>
    /// Runs PowerShell with the script as administrator and waits for the approval prompt to be answered.
    /// </summary>
    /// <returns>False when the user declined.</returns>
    bool RunElevatedPowerShell(string script);
}

/// <summary>
/// Handles <c>time.sync.repair.request</c>: registers the <c>VeilTimeSync</c> task on a Windows whose tools
/// were installed without administrator rights, so its clock can be corrected again.
/// </summary>
/// <remarks>
/// Without the task a guest clock that fell behind stays wrong, as after the Mac slept or a session was
/// resumed: the agent may not set the clock itself. Registering the task needs administrator rights once,
/// so Windows shows its approval prompt, which the host shows on the Mac.
///
/// The elevated command is built here and passed to PowerShell encoded. It runs nothing from a file a
/// program running as the user could have replaced before the prompt is approved, and the task it
/// registers runs only programs in the Windows directory.
/// </remarks>
public sealed class GuestTimeSyncRepair
{
    private readonly IElevatedLauncher launcher;
    private int running;

    public GuestTimeSyncRepair(IElevatedLauncher? launcher = null)
    {
        this.launcher = launcher ?? new WindowsElevatedLauncher();
    }

    /// <summary>
    /// Starts the repair and answers at once: the prompt may wait for the user for minutes. The outcome is
    /// read with the next <c>time.sync.request</c>.
    /// </summary>
    public JsonObject Start()
    {
        if (!launcher.IsWindows)
        {
            return Status(false, "unsupported", "This agent is not running on Windows.");
        }
        if (launcher.CurrentUserSid is not { } sid || !IsSid(sid))
        {
            return Status(true, "failed", "The current user could not be identified.");
        }
        if (Interlocked.Exchange(ref running, 1) != 0)
        {
            return Status(true, "already-running", "Windows is already asking for approval.");
        }

        var script = RegistrationScript(GuestTimeSync.ResyncTaskName, sid);
        _ = Task.Run(() =>
        {
            try
            {
                if (!launcher.RunElevatedPowerShell(script))
                {
                    Console.Error.WriteLine("GuestTimeSyncRepair: the approval prompt was declined.");
                }
            }
            catch (Exception error)
            {
                Console.Error.WriteLine($"GuestTimeSyncRepair: {error.GetType().Name}: {error.Message}");
            }
            finally
            {
                Volatile.Write(ref running, 0);
            }
        });
        return Status(true, "approval-requested", null);
    }

    /// <summary>A SID in its string form: letters, digits, and hyphens only, so it is safe inside the script.</summary>
    internal static bool IsSid(string value) =>
        value.StartsWith("S-1-", StringComparison.Ordinal)
        && value.Length <= 184
        && value.All(character => char.IsAsciiDigit(character) || character == '-' || character == 'S');

    /// <summary>
    /// The PowerShell run as administrator. The task runs as SYSTEM and takes no input: it starts the Windows
    /// Time service and asks it to resync from network time, both by full path. The user is granted read and
    /// execute on that one task, so the agent can start it and cannot change it.
    /// </summary>
    internal static string RegistrationScript(string taskName, string userSid) => string.Join("\n", [
        "$ErrorActionPreference = 'Stop'",
        "$system = Join-Path $env:SystemRoot 'System32'",
        "$command = '/c \"\"' + (Join-Path $system 'sc.exe') + '\" start w32time & \"' + (Join-Path $system 'w32tm.exe') + '\" /resync /rediscover\"'",
        "$action = New-ScheduledTaskAction -Execute (Join-Path $system 'cmd.exe') -Argument $command",
        "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest",
        "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew",
        $"Register-ScheduledTask -TaskName '{taskName}' -Action $action -Principal $principal -Settings $settings -Force | Out-Null",
        "$scheduler = New-Object -ComObject 'Schedule.Service'",
        "$scheduler.Connect()",
        $"$task = $scheduler.GetFolder('\\').GetTask('{taskName}')",
        "$descriptor = $task.GetSecurityDescriptor(4)",
        $"$ace = '(A;;GRGX;;;{userSid})'",
        "if (-not $descriptor.Contains($ace)) { $task.SetSecurityDescriptor($descriptor + $ace, 0) }",
        // Windows refuses corrections over 15 hours by default, which is the long-sleep case itself.
        "$config = 'HKLM:\\SYSTEM\\CurrentControlSet\\Services\\W32Time\\Config'",
        "Set-ItemProperty -Path $config -Name MaxPosPhaseCorrection -Value 0xFFFFFFFF -Type DWord",
        "Set-ItemProperty -Path $config -Name MaxNegPhaseCorrection -Value 0xFFFFFFFF -Type DWord",
        "& (Join-Path $system 'w32tm.exe') /config /update | Out-Null",
        $"Start-ScheduledTask -TaskName '{taskName}'"
    ]);

    private static JsonObject Status(bool isSupported, string outcome, string? message) => new()
    {
        ["isSupported"] = isSupported,
        ["outcome"] = outcome,
        ["message"] = message
    };
}

public sealed class WindowsElevatedLauncher : IElevatedLauncher
{
    private const int ErrorCancelled = 1223;

    public bool IsWindows => OperatingSystem.IsWindows();

    public string? CurrentUserSid
    {
        get
        {
            if (!OperatingSystem.IsWindows())
            {
                return null;
            }
            using var identity = WindowsIdentity.GetCurrent();
            return identity.User?.Value;
        }
    }

    public bool RunElevatedPowerShell(string script)
    {
        // -EncodedCommand takes the script as UTF-16 in Base64, so nothing in it needs quoting.
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        try
        {
            // The "runas" verb is what makes Windows ask for approval:
            // https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shellexecuteexw
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(system, "WindowsPowerShell", "v1.0", "powershell.exe"),
                Arguments = $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand {encoded}",
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden
            });
            process?.WaitForExit(120_000);
            return true;
        }
        catch (Win32Exception error) when (error.NativeErrorCode == ErrorCancelled)
        {
            return false;
        }
    }
}
