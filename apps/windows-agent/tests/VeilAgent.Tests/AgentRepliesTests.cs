using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentRepliesTests
{
    [Fact]
    public void SerializesUnchangedFrameAsPayloadFreeLivenessEvidence()
    {
        var json = AgentReplies.SerializeUnchangedFrame(
            "hwnd:0003029A",
            42,
            new DateTimeOffset(2026, 7, 31, 0, 14, 2, TimeSpan.Zero)
        );
        var message = JsonNode.Parse(json)!.AsObject();

        Assert.Equal("window.frame.unchanged", message["type"]!.GetValue<string>());
        Assert.Equal("hwnd:0003029A", message["windowId"]!.GetValue<string>());
        Assert.Equal(42, message["sequence"]!.GetValue<int>());
        Assert.Equal("2026-07-31T00:14:02.0000000+00:00", message["capturedAt"]!.GetValue<string>());
        Assert.False(message.ContainsKey("encodedData"));
    }
}
