using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// Running totals of processor time for the agent and for Windows as a whole, reported with
/// <c>agent.health.response</c>. Two answers a few seconds apart give the share of the guest's processors
/// the agent took and how busy the guest was, without anything having to be run inside Windows.
/// </summary>
public static class ProcessorDiagnostics
{
    public static JsonObject Snapshot()
    {
        var result = new JsonObject
        {
            ["processorCount"] = Environment.ProcessorCount,
            ["uptimeSeconds"] = Math.Round(Environment.TickCount64 / 1000.0, 3)
        };

        try
        {
            using var process = Process.GetCurrentProcess();
            result["agentSeconds"] = Math.Round(process.TotalProcessorTime.TotalSeconds, 3);
        }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
        {
            result["agentSeconds"] = null;
        }

        // Summed over all processors. Kernel time includes idle time, so busy time is kernel plus user
        // less idle: https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-getsystemtimes
        if (OperatingSystem.IsWindows() && GetSystemTimes(out var idle, out var kernel, out var user))
        {
            result["idleSeconds"] = Seconds(idle);
            result["busySeconds"] = Math.Round(Seconds(kernel) + Seconds(user) - Seconds(idle), 3);
        }

        return result;
    }

    private static double Seconds(long fileTime) => Math.Round(fileTime / 10_000_000.0, 3);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out long idleTime, out long kernelTime, out long userTime);
}
