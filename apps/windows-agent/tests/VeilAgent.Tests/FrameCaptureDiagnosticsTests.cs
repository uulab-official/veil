using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class FrameCaptureDiagnosticsTests
{
    [Fact]
    public void ReportsASmoothedMeanAndTheWorstTimePerPhase()
    {
        var diagnostics = new FrameCaptureDiagnostics();

        diagnostics.Record("capture", 10);
        diagnostics.Record("capture", 30);
        diagnostics.RecordMethod(FrameCaptureDiagnostics.ScreenCopyStrategy);

        var snapshot = diagnostics.Snapshot();
        var capture = snapshot["phases"]!["capture"]!;
        Assert.Equal(12, capture["meanMilliseconds"]!.GetValue<double>());
        Assert.Equal(30, capture["maxMilliseconds"]!.GetValue<double>());
        Assert.Equal(2, capture["count"]!.GetValue<long>());
        Assert.Equal(1, snapshot["methods"]!["screen"]!.GetValue<long>());
        Assert.Equal("auto", snapshot["strategy"]!.GetValue<string>());
    }

    [Fact]
    public void ChangingTheStrategyStartsTheTimesOver()
    {
        var diagnostics = new FrameCaptureDiagnostics();
        diagnostics.Record("capture", 10);

        Assert.True(diagnostics.SetStrategy(FrameCaptureDiagnostics.PrintWindowStrategy));

        var snapshot = diagnostics.Snapshot();
        Assert.Equal("printWindow", snapshot["strategy"]!.GetValue<string>());
        Assert.Empty(snapshot["phases"]!.AsObject());
    }

    [Fact]
    public void IgnoresAnUnknownStrategy()
    {
        var diagnostics = new FrameCaptureDiagnostics();

        Assert.False(diagnostics.SetStrategy("magic"));
        Assert.Equal(FrameCaptureDiagnostics.AutomaticStrategy, diagnostics.Strategy);
    }

    [Fact]
    public async Task HealthCarriesCaptureTimesAndTheStrategyMessageIsAcknowledged()
    {
        var session = new AgentSession(
            new AgentSessionDisplayResizeTests.RecordingWindowsDesktop(),
            new AgentSessionDisplayResizeTests.NoOpFrameCapture()
        );

        var health = Assert.Single((await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health_1"
        })).DirectReplies);
        Assert.NotNull(health["frameCapture"]?["strategy"]);

        try
        {
            var ack = Assert.Single((await session.HandleAsync(new JsonObject
            {
                ["type"] = MessageTypes.FrameCaptureStrategySet,
                ["requestId"] = "req_strategy_1",
                ["strategy"] = "auto"
            })).DirectReplies);
            Assert.Equal(MessageTypes.OperationAck, ack["type"]!.GetValue<string>());

            var rejected = Assert.Single((await session.HandleAsync(new JsonObject
            {
                ["type"] = MessageTypes.FrameCaptureStrategySet,
                ["requestId"] = "req_strategy_2",
                ["strategy"] = "magic"
            })).DirectReplies);
            Assert.Equal("invalid_message", rejected["code"]!.GetValue<string>());
        }
        finally
        {
            FrameCaptureDiagnostics.Shared.SetStrategy(FrameCaptureDiagnostics.AutomaticStrategy);
        }
    }
}
