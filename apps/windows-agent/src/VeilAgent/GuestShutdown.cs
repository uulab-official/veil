using System.Diagnostics;

namespace Veil.Agent;

public interface IGuestShutdown
{
    /// <summary>Starts a normal Windows shutdown; returns once it has been requested.</summary>
    void Start();
}

/// <summary>
/// Shuts Windows down the way the Start menu does. The host asks for this instead of pressing the
/// ACPI power button, which Windows can leave unanswered.
/// </summary>
public sealed class WindowsGuestShutdown : IGuestShutdown
{
    public void Start()
    {
        var shutdownPath = Path.Combine(Environment.SystemDirectory, "shutdown.exe");
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = shutdownPath,
            // No /f: Windows asks apps to close, so a document with changes can still be saved.
            Arguments = "/s /t 0",
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Environment.SystemDirectory
        }) ?? throw new InvalidOperationException("shutdown.exe could not be started.");
        process.WaitForExit(10_000);
        if (process.HasExited && process.ExitCode != 0)
        {
            throw new InvalidOperationException($"shutdown.exe exited with code {process.ExitCode}.");
        }
    }
}
