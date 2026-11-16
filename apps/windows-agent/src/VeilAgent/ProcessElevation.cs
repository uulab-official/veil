using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Whether a process runs at a higher integrity level than the agent, as an installer does once its User
/// Account Control prompt is approved.
/// </summary>
/// <remarks>
/// Windows drops input a lower-integrity process injects into a higher one's windows (User Interface
/// Privilege Isolation), and <c>SendInput</c> does not say so:
/// <see href="https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput"/>. The agent runs
/// without administrator rights on purpose, so such a window was shown on the Mac and ignored every click
/// and key. The host is told which windows these are and sends their input through the virtual hardware
/// instead, which Windows takes from anyone at the keyboard.
///
/// A process whose token cannot be read is counted as higher: input through the hardware works for every
/// window, so the mistake that costs nothing is the one made.
/// </remarks>
public static class ProcessElevation
{
    private const long CacheMilliseconds = 5_000;
    private static readonly ConcurrentDictionary<int, (bool Above, long At)> Cache = new();
    private static readonly Lazy<int?> OwnLevel = new(() => OperatingSystem.IsWindows() ? LevelOf(GetCurrentProcess()) : null);

    /// <summary>Whether the process is above the agent. Remembered for five seconds per process.</summary>
    public static bool IsAboveAgent(int processId)
    {
        if (!OperatingSystem.IsWindows() || processId <= 0 || processId == Environment.ProcessId)
        {
            return false;
        }

        var now = Environment.TickCount64;
        if (Cache.TryGetValue(processId, out var cached) && now - cached.At < CacheMilliseconds)
        {
            return cached.Above;
        }

        var above = Probe(processId);
        Cache[processId] = (above, now);
        if (Cache.Count > 512)
        {
            foreach (var (key, value) in Cache)
            {
                if (now - value.At >= CacheMilliseconds)
                {
                    Cache.TryRemove(key, out _);
                }
            }
        }
        return above;
    }

    /// <summary>Reads the answer from what opening the process and its token gave.</summary>
    /// <param name="processExists">False when the process is gone, which is not a higher level.</param>
    /// <param name="ownLevel">The agent's integrity level, or null when it could not be read.</param>
    /// <param name="targetLevel">The process's level, or null when its token could not be read.</param>
    public static bool IsAbove(bool processExists, int? ownLevel, int? targetLevel)
    {
        if (!processExists)
        {
            return false;
        }
        if (targetLevel is not { } target)
        {
            return true;
        }
        return ownLevel is { } own && target > own;
    }

    private static bool Probe(int processId)
    {
        var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)processId);
        if (process == 0)
        {
            // Gone, or one Windows will not even name: the first is not higher, the second is.
            return IsAbove(Marshal.GetLastWin32Error() == ERROR_ACCESS_DENIED, OwnLevel.Value, null);
        }

        try
        {
            return IsAbove(true, OwnLevel.Value, LevelOf(process));
        }
        finally
        {
            _ = CloseHandle(process);
        }
    }

    /// <summary>
    /// The integrity level of a process: the last part of the SID in its token's mandatory label, 0x2000 for
    /// a normal program and 0x3000 for one run as administrator.
    /// <see href="https://learn.microsoft.com/windows/win32/secauthz/mandatory-integrity-control"/>
    /// </summary>
    private static int? LevelOf(nint process)
    {
        if (!OpenProcessToken(process, TOKEN_QUERY, out var token))
        {
            return null;
        }

        try
        {
            _ = GetTokenInformation(token, TokenIntegrityLevel, 0, 0, out var length);
            if (length <= 0)
            {
                return null;
            }

            var buffer = Marshal.AllocHGlobal(length);
            try
            {
                if (!GetTokenInformation(token, TokenIntegrityLevel, buffer, length, out _))
                {
                    return null;
                }

                // TOKEN_MANDATORY_LABEL starts with a pointer to the SID.
                var sid = Marshal.ReadIntPtr(buffer);
                var count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                return count == 0 ? null : Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(count - 1)));
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            _ = CloseHandle(token);
        }
    }

    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const uint TOKEN_QUERY = 0x0008;
    private const int TokenIntegrityLevel = 25;
    private const int ERROR_ACCESS_DENIED = 5;

    [DllImport("kernel32.dll")]
    private static extern nint GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern nint OpenProcess(uint access, bool inherit, uint processId);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(nint handle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(nint process, uint access, out nint token);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetTokenInformation(nint token, int kind, nint buffer, int length, out int needed);

    [DllImport("advapi32.dll")]
    private static extern nint GetSidSubAuthorityCount(nint sid);

    [DllImport("advapi32.dll")]
    private static extern nint GetSidSubAuthority(nint sid, uint index);
}
