using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class ClipboardTextStreamerTests
{
    private sealed class ScriptedWindowsDesktop : IWindowsDesktop
    {
        private readonly Queue<Func<string?>> script;

        public ScriptedWindowsDesktop(Queue<Func<string?>> script)
        {
            this.script = script;
        }

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken)
        {
            if (script.Count == 0)
            {
                return Task.FromResult<string?>(null);
            }

            return Task.FromResult(script.Dequeue()());
        }

        public bool TryConsumeHostClipboardEcho(string text) => false;

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) =>
            throw new NotSupportedException();

        public bool IsWindowStillOpen(string windowId) => throw new NotSupportedException();

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    [Fact]
    public async Task TransientReadFailureDoesNotStopTheStream()
    {
        // Regression test: a transient clipboard read failure (Windows clipboard access is
        // contended by design -- any app can briefly hold OpenClipboard) must not permanently kill
        // clipboard sync for the rest of the agent's process lifetime, the same way
        // WindowFrameStreamer already tolerates transient per-tick capture failures.
        var script = new Queue<Func<string?>>();
        script.Enqueue(() => throw new InvalidOperationException("OpenClipboard failed."));
        script.Enqueue(() => "hello after the failure");

        var desktop = new ScriptedWindowsDesktop(script);
        var streamer = new ClipboardTextStreamer(desktop, interval: TimeSpan.FromMilliseconds(5));

        var broadcasts = new List<string>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message["text"]!.GetValue<string>());
                cancellation.Cancel();
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        Assert.Equal(["hello after the failure"], broadcasts);
    }

    [Fact]
    public async Task DoesNotBroadcastWhenClipboardTextIsUnchanged()
    {
        var script = new Queue<Func<string?>>();
        script.Enqueue(() => "same text");
        script.Enqueue(() => "same text");
        script.Enqueue(() => "different text");

        var desktop = new ScriptedWindowsDesktop(script);
        var streamer = new ClipboardTextStreamer(desktop, interval: TimeSpan.FromMilliseconds(5));

        var broadcasts = new List<string>();
        using var cancellation = new CancellationTokenSource();

        var streamTask = streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message["text"]!.GetValue<string>());
                if (broadcasts.Count >= 2)
                {
                    cancellation.Cancel();
                }
                return Task.CompletedTask;
            },
            cancellation.Token
        );

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamTask);

        Assert.Equal(["same text", "different text"], broadcasts);
    }
}
