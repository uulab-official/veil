using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentSessionShutdownTests
{
    [Fact]
    public async Task StartsAWindowsShutdownAndAccepts()
    {
        var shutdown = new RecordingShutdown();
        var session = Session(shutdown);

        var replies = await session.HandleAsync(Request());

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.SystemShutdownResponse, response["type"]!.GetValue<string>());
        Assert.Equal("req_system_shutdown_1", response["requestId"]!.GetValue<string>());
        Assert.True(response["accepted"]!.GetValue<bool>());
        Assert.Equal(1, shutdown.Starts);
    }

    [Fact]
    public async Task ReportsWhyWindowsCouldNotStartShuttingDown()
    {
        var session = Session(new RecordingShutdown { Failure = new InvalidOperationException("shutdown.exe exited with code 1190.") });

        var replies = await session.HandleAsync(Request());

        var response = Assert.Single(replies.DirectReplies);
        Assert.False(response["accepted"]!.GetValue<bool>());
        Assert.Contains("1190", response["reason"]!.GetValue<string>());
    }

    private static AgentSession Session(IGuestShutdown shutdown) => new(
        new AgentSessionDisplayResizeTests.RecordingWindowsDesktop(),
        new AgentSessionDisplayResizeTests.NoOpFrameCapture(),
        guestShutdown: shutdown
    );

    private static JsonObject Request() => new()
    {
        ["type"] = MessageTypes.SystemShutdownRequest,
        ["requestId"] = "req_system_shutdown_1"
    };

    private sealed class RecordingShutdown : IGuestShutdown
    {
        public int Starts { get; private set; }
        public Exception? Failure { get; init; }

        public void Start()
        {
            Starts += 1;
            if (Failure is not null)
            {
                throw Failure;
            }
        }
    }
}
