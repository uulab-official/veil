using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Veil.Agent;

/// <summary>
/// Operating-system clock operations behind a seam, so every reported outcome can be tested without
/// changing a real clock.
/// </summary>
public interface IGuestClock
{
    bool IsWindows { get; }

    DateTimeOffset UtcNow { get; }

    /// <summary>
    /// Sets the system clock. Returns false with <paramref name="privilegeNotHeld"/> set when the
    /// agent's token cannot hold <c>SeSystemtimePrivilege</c>, which is the normal case for the
    /// limited-token interactive agent.
    /// </summary>
    bool TrySetSystemTime(DateTimeOffset utc, out bool privilegeNotHeld, out string? error);

    /// <summary>
    /// Starts the elevated-install <c>VeilTimeSync</c> scheduled task. True only means the task
    /// started; it says nothing about whether NTP answered.
    /// </summary>
    bool TryStartResyncTask(out string? error);
}

/// <summary>
/// Handles <c>time.sync.request</c>: after a suspend/resume or a long Mac sleep Windows resumes with a
/// stale clock and nothing inside the guest notices, so the host says what time it is.
/// </summary>
public sealed class GuestTimeSync
{
    public const int ThresholdMilliseconds = 2000;
    public const string ResyncTaskName = "VeilTimeSync";

    // Mirrors validateTimeSyncRequest in packages/protocol/src/messages.mjs.
    private static readonly Regex IsoUtc = new(
        @"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?Z$",
        RegexOptions.Compiled
    );

    private static readonly HashSet<string> KnownReasons = new(StringComparer.Ordinal)
    {
        "agent-connected",
        "mac-wake",
        "vm-resume",
        "manual"
    };

    private readonly IGuestClock clock;

    public GuestTimeSync(IGuestClock? clock = null)
    {
        this.clock = clock ?? new WindowsGuestClock();
    }

    public JsonObject Handle(JsonObject request)
    {
        string? hostUtcText = null;
        string? reason = null;
        try
        {
            hostUtcText = request["hostUtc"]?.GetValue<string>();
            reason = request["reason"]?.GetValue<string>();
        }
        catch (InvalidOperationException)
        {
            // A non-string value is handled as an invalid request below.
        }

        if (!clock.IsWindows)
        {
            return Status(
                isSupported: false,
                guestUtcBefore: null,
                skewMilliseconds: null,
                outcome: "unsupported",
                method: "none",
                requiresElevation: false,
                recommendedAction: "unsupported-on-this-host",
                message: "This agent is not running on Windows."
            );
        }

        if (!TryParseHostUtc(hostUtcText, out var hostUtc) || reason is null || !KnownReasons.Contains(reason))
        {
            return Status(
                isSupported: true,
                guestUtcBefore: null,
                skewMilliseconds: null,
                outcome: "invalid-request",
                method: "none",
                requiresElevation: false,
                recommendedAction: "invalid-request",
                message: "time.sync.request needs an ISO 8601 UTC hostUtc between 2020 and 2100 and a known reason."
            );
        }

        var before = clock.UtcNow;
        var skew = (long)Math.Round((hostUtc - before).TotalMilliseconds);
        if (Math.Abs(skew) <= ThresholdMilliseconds)
        {
            return Status(true, before, skew, "in-sync", "none", false, "none", null);
        }

        var direction = skew > 0 ? "behind" : "ahead of";
        if (clock.TrySetSystemTime(hostUtc, out var privilegeNotHeld, out var setError))
        {
            return Status(
                true, before, skew, "corrected", "set-system-time", false, "none",
                $"Windows clock was {Math.Abs(skew)} ms {direction} macOS and has been set from the host."
            );
        }

        if (clock.TryStartResyncTask(out var taskError))
        {
            return Status(
                true, before, skew, "resync-requested", "resync-task", false, "wait-for-network-time",
                $"Windows clock is {Math.Abs(skew)} ms {direction} macOS. The {ResyncTaskName} task was started to resync from network time; send time.sync.request again to confirm."
            );
        }

        if (privilegeNotHeld)
        {
            return Status(
                true, before, skew, "failed", "none", true, "install-time-sync-task-elevated",
                $"Windows clock is {Math.Abs(skew)} ms {direction} macOS. The agent cannot set the clock with a limited token and the {ResyncTaskName} task is not available ({taskError ?? "not registered"}). Re-run Install-VeilAgent.ps1 as administrator once."
            );
        }

        return Status(
            true, before, skew, "failed", "none", false, "none",
            $"Windows clock is {Math.Abs(skew)} ms {direction} macOS and could not be corrected: {setError ?? "SetSystemTime failed"}; {taskError ?? "resync task unavailable"}."
        );
    }

    internal static bool TryParseHostUtc(string? text, out DateTimeOffset value)
    {
        value = default;
        if (text is null || !IsoUtc.IsMatch(text))
        {
            return false;
        }

        if (!DateTimeOffset.TryParse(
                text,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out value))
        {
            return false;
        }

        // A host clock outside this window is far more likely to be broken than right.
        return value.Year >= 2020 && value.Year <= 2100;
    }

    private static JsonObject Status(
        bool isSupported,
        DateTimeOffset? guestUtcBefore,
        long? skewMilliseconds,
        string outcome,
        string method,
        bool requiresElevation,
        string recommendedAction,
        string? message
    )
    {
        var status = new JsonObject
        {
            ["isSupported"] = isSupported,
            ["thresholdMilliseconds"] = ThresholdMilliseconds,
            ["outcome"] = outcome,
            ["method"] = method,
            ["requiresElevation"] = requiresElevation,
            ["recommendedAction"] = recommendedAction,
            ["message"] = message
        };

        if (guestUtcBefore is { } before)
        {
            status["guestUtcBefore"] = before.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
        }

        if (skewMilliseconds is { } skew)
        {
            status["skewMilliseconds"] = skew;
        }

        return status;
    }
}

public sealed class WindowsGuestClock : IGuestClock
{
    private const int ErrorNotAllAssigned = 1300;
    private const int ErrorPrivilegeNotHeld = 1314;
    private const uint TokenAdjustPrivileges = 0x0020;
    private const uint TokenQuery = 0x0008;
    private const uint SePrivilegeEnabled = 0x00000002;

    public bool IsWindows => OperatingSystem.IsWindows();

    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;

    public bool TrySetSystemTime(DateTimeOffset utc, out bool privilegeNotHeld, out string? error)
    {
        privilegeNotHeld = false;
        error = null;

        if (!EnableSystemTimePrivilege(out var enableError))
        {
            privilegeNotHeld = enableError is ErrorNotAllAssigned or ErrorPrivilegeNotHeld;
            error = $"SeSystemtimePrivilege unavailable (Win32 error {enableError})";
            return false;
        }

        var value = utc.UtcDateTime;
        var systemTime = new SystemTime
        {
            Year = (ushort)value.Year,
            Month = (ushort)value.Month,
            DayOfWeek = (ushort)value.DayOfWeek,
            Day = (ushort)value.Day,
            Hour = (ushort)value.Hour,
            Minute = (ushort)value.Minute,
            Second = (ushort)value.Second,
            Milliseconds = (ushort)value.Millisecond
        };

        if (SetSystemTime(ref systemTime))
        {
            return true;
        }

        var setError = Marshal.GetLastWin32Error();
        privilegeNotHeld = setError == ErrorPrivilegeNotHeld;
        error = $"SetSystemTime failed (Win32 error {setError})";
        return false;
    }

    public bool TryStartResyncTask(out string? error)
    {
        error = null;
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                ArgumentList = { "/Run", "/TN", GuestTimeSync.ResyncTaskName },
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            if (process is null)
            {
                error = "schtasks.exe could not be started";
                return false;
            }

            var stderr = process.StandardError.ReadToEndAsync();
            _ = process.StandardOutput.ReadToEndAsync();
            if (!process.WaitForExit(10_000))
            {
                process.Kill();
                error = "schtasks.exe timed out";
                return false;
            }

            if (process.ExitCode != 0)
            {
                error = $"schtasks /Run exited {process.ExitCode}: {stderr.Result.Trim()}";
                return false;
            }

            return true;
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            error = exception.Message;
            return false;
        }
    }

    private static bool EnableSystemTimePrivilege(out int win32Error)
    {
        win32Error = 0;
        if (!OpenProcessToken(GetCurrentProcess(), TokenAdjustPrivileges | TokenQuery, out var token))
        {
            win32Error = Marshal.GetLastWin32Error();
            return false;
        }

        try
        {
            if (!LookupPrivilegeValue(null, "SeSystemtimePrivilege", out var luid))
            {
                win32Error = Marshal.GetLastWin32Error();
                return false;
            }

            var privileges = new TokenPrivileges
            {
                PrivilegeCount = 1,
                Luid = luid,
                Attributes = SePrivilegeEnabled
            };

            if (!AdjustTokenPrivileges(token, false, ref privileges, 0, IntPtr.Zero, IntPtr.Zero))
            {
                win32Error = Marshal.GetLastWin32Error();
                return false;
            }

            // AdjustTokenPrivileges succeeds even when the token does not hold the privilege at all;
            // the only signal is ERROR_NOT_ALL_ASSIGNED.
            win32Error = Marshal.GetLastWin32Error();
            return win32Error != ErrorNotAllAssigned;
        }
        finally
        {
            CloseHandle(token);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SystemTime
    {
        public ushort Year;
        public ushort Month;
        public ushort DayOfWeek;
        public ushort Day;
        public ushort Hour;
        public ushort Minute;
        public ushort Second;
        public ushort Milliseconds;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenPrivileges
    {
        public uint PrivilegeCount;
        public Luid Luid;
        public uint Attributes;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetSystemTime(ref SystemTime systemTime);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr processHandle, uint desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool LookupPrivilegeValue(string? systemName, string name, out Luid luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(
        IntPtr tokenHandle,
        bool disableAllPrivileges,
        ref TokenPrivileges newState,
        uint bufferLength,
        IntPtr previousState,
        IntPtr returnLength
    );
}
