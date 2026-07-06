using Veil.Agent;

namespace VeilAgent.Tests;

public class SingleInstanceGuardTests
{
    private static AgentEndpoint UniqueEndpoint() =>
        new(Host: "0.0.0.0", Port: Random.Shared.Next(20000, 60000));

    [Fact]
    public void FirstAcquireOwnsTheMutex()
    {
        var endpoint = UniqueEndpoint();
        using var guard = SingleInstanceGuard.TryAcquire(endpoint);

        Assert.True(guard.HasOwnership);
    }

    [Fact]
    public void SecondAcquireForTheSamePortDoesNotOwnTheMutex()
    {
        if (!OperatingSystem.IsWindows())
        {
            // Named Mutex cross-instance mutual exclusion ("Local\..." session-scoped kernel
            // objects) is a Windows-specific OS feature. .NET's named Mutex support on non-Windows
            // platforms does not reliably reproduce single-instance semantics, so this invariant can
            // only be verified when actually running on Windows (CI or a Windows dev machine).
            return;
        }

        var endpoint = UniqueEndpoint();
        using var first = SingleInstanceGuard.TryAcquire(endpoint);
        using var second = SingleInstanceGuard.TryAcquire(endpoint);

        Assert.True(first.HasOwnership);
        Assert.False(second.HasOwnership);
    }

    [Fact]
    public async Task DisposeFromADifferentThreadThanAcquireDoesNotThrow()
    {
        // Regression test for the real crash this guard once had: Program.cs is a top-level async
        // Main that acquires the guard synchronously, then disposes it (via `using`) after
        // `await server.RunAsync()`. A console app's thread pool does not guarantee the dispose runs
        // on the same OS thread as the acquire, and .NET's Mutex.ReleaseMutex() throws
        // ApplicationException when the releasing thread differs from the acquiring thread. This test
        // reproduces that exact cross-thread pattern.
        var endpoint = UniqueEndpoint();
        var guard = SingleInstanceGuard.TryAcquire(endpoint);
        Assert.True(guard.HasOwnership);

        var exception = await Record.ExceptionAsync(() => Task.Run(guard.Dispose));

        Assert.Null(exception);
    }
}
