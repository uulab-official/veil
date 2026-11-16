using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class ToolsUpdateTests
{
    private const string EntryPoint = @"H:\Veil Guest Agent\U.cmd";

    private static ToolsUpdate Update(
        IEnumerable<ToolsUpdateDrive> drives,
        IEnumerable<string> files,
        List<string> started,
        Exception? startFailure = null
    ) => new(
        opticalDrives: () => drives,
        fileExists: files.Contains,
        start: path =>
        {
            if (startFailure is not null)
            {
                throw startFailure;
            }
            started.Add(path);
        }
    );

    [Fact]
    public void StartsTheEntryPointOnTheDiscLabelledForVeil()
    {
        var started = new List<string>();
        var update = Update(
            [new ToolsUpdateDrive(@"D:\", "VEIL_AUTO"), new ToolsUpdateDrive(@"H:\", "veil_tools")],
            // The boot disc has the bundle too, but only the update disc is run.
            [@"D:\Veil Guest Agent\U.cmd", EntryPoint],
            started
        );

        var result = update.Run();

        Assert.True(result.Started);
        Assert.Equal(EntryPoint, result.EntryPoint);
        Assert.Equal([EntryPoint], started);
    }

    [Fact]
    public void RunsNothingWithoutTheDisc()
    {
        var started = new List<string>();
        var otherLabel = Update([new ToolsUpdateDrive(@"H:\", "SETUP")], [EntryPoint], started);
        var noEntryPoint = Update([new ToolsUpdateDrive(@"H:\", "VEIL_TOOLS")], [], started);

        Assert.Equal("tools_media_missing", otherLabel.Run().ErrorCode);
        Assert.Equal("tools_media_missing", noEntryPoint.Run().ErrorCode);
        Assert.Empty(started);
    }

    [Fact]
    public void ReportsAStartFailure()
    {
        var update = Update(
            [new ToolsUpdateDrive("H:", "VEIL_TOOLS")],
            [EntryPoint],
            [],
            new InvalidOperationException("cmd.exe did not start.")
        );

        var result = update.Run();

        Assert.False(result.Started);
        Assert.Equal("tools_update_failed", result.ErrorCode);
        Assert.Equal(EntryPoint, result.EntryPoint);
    }

    private static AgentSession Session(ToolsUpdate update) => new(
        new AgentSessionDisplayResizeTests.RecordingWindowsDesktop(),
        new NoFrames(),
        toolsUpdate: update
    );

    private sealed class NoFrames : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    [Fact]
    public async Task TheRequestStartsTheUpdateAndIgnoresAnyPathItCarries()
    {
        var started = new List<string>();
        var session = Session(Update([new ToolsUpdateDrive(@"H:\", "VEIL_TOOLS")], [EntryPoint], started));

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = "tools.update.request",
            ["requestId"] = "req_tools_update",
            ["protocolVersion"] = 1,
            // Not part of the message. Whatever a sender adds, only the disc's own entry point runs.
            ["path"] = @"C:\Users\Public\evil.cmd",
            ["command"] = "calc.exe"
        });

        var response = replies.DirectReplies.Single();
        Assert.Equal("tools.update.response", response["type"]!.GetValue<string>());
        Assert.Equal("req_tools_update", response["requestId"]!.GetValue<string>());
        Assert.True(response["accepted"]!.GetValue<bool>());
        Assert.Equal(EntryPoint, response["entryPoint"]!.GetValue<string>());
        Assert.Equal([EntryPoint], started);
    }

    [Fact]
    public async Task TheRequestAnswersWithAnErrorWhenNoDiscIsInserted()
    {
        var started = new List<string>();
        var session = Session(Update([], [], started));

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = "tools.update.request",
            ["requestId"] = "req_tools_update"
        });

        var response = replies.DirectReplies.Single();
        Assert.Equal("error", response["type"]!.GetValue<string>());
        Assert.Equal("tools_media_missing", response["code"]!.GetValue<string>());
        Assert.Empty(started);
    }
}
