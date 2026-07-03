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
            mutex.ReleaseMutex();
            ownsMutex = false;
        }

        mutex.Dispose();
    }
}
