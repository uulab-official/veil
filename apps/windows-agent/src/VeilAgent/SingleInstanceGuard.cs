namespace Veil.Agent;

public sealed class SingleInstanceGuard : IDisposable
{
    private readonly Mutex mutex;
    private bool ownsMutex;

    private SingleInstanceGuard(Mutex mutex, bool ownsMutex, string mutexName)
    {
        this.mutex = mutex;
        this.ownsMutex = ownsMutex;
        MutexName = mutexName;
    }

    public bool HasOwnership => ownsMutex;

    public string MutexName { get; }

    public static SingleInstanceGuard TryAcquire(AgentEndpoint endpoint)
    {
        var mutexName = $@"Local\VeilAgent-{endpoint.Port}";
        var mutex = new Mutex(initiallyOwned: false, name: mutexName);
        var ownsMutex = false;
        try
        {
            ownsMutex = mutex.WaitOne(TimeSpan.Zero);
        }
        catch (AbandonedMutexException)
        {
            ownsMutex = true;
        }

        return new SingleInstanceGuard(mutex, ownsMutex, mutexName);
    }

    public void Dispose()
    {
        if (ownsMutex)
        {
            try
            {
                mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
                // ReleaseMutex requires the releasing thread to match the thread that acquired the
                // mutex. Program.cs disposes this guard after `await server.RunAsync()`, and a
                // console app's thread pool does not guarantee thread affinity across awaits, so the
                // dispose can legitimately run on a different thread than TryAcquire did. Windows
                // releases a process's named mutexes automatically on exit, so skipping the explicit
                // release here is safe and avoids masking whatever caused the agent to shut down with
                // an unrelated "unsynchronized block of code" crash.
            }

            ownsMutex = false;
        }

        mutex.Dispose();
    }
}
