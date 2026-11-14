using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class DisplayScaleTests
{
    // A 3024x1964 display whose recommended step is 200%: 100% is four steps below it.
    private static FakeBackend RetinaDisplayAt(int percent) =>
        new(minRelative: -4, currentRelative: -4 + Index(percent), maxRelative: 2);

    [Fact]
    public void MapsPercentsToStepsRelativeToTheRecommendedOne()
    {
        Assert.Equal(-4, DisplayScaleSteps.RelativeFor(100, -4, 2));
        Assert.Equal(0, DisplayScaleSteps.RelativeFor(200, -4, 2));
        Assert.Equal(200, DisplayScaleSteps.PercentFor(0, -4));
        Assert.Equal(100, DisplayScaleSteps.PercentFor(-4, -4));
        Assert.Null(DisplayScaleSteps.PercentFor(-5, -4));
        Assert.Null(DisplayScaleSteps.RelativeFor(110, -4, 2));
    }

    [Fact]
    public void LowersAStepTheDisplayDoesNotOffer()
    {
        // 1512x982 offers 100% and 125% only.
        Assert.Equal(-3, DisplayScaleSteps.RelativeFor(200, minRelative: -4, maxRelative: -3));
    }

    [Fact]
    public void RecordsTheUserScaleOnceThenSetsTheStep()
    {
        var backend = RetinaDisplayAt(125);
        var record = new FakeRecord();
        var manager = new DisplayScaleManager(backend, record);

        var first = manager.Apply(new DisplayScaleInput(200, false));
        var second = manager.Apply(new DisplayScaleInput(150, false));

        Assert.Equal(new DisplayScaleResult(true, 200, null), first);
        Assert.Equal(new DisplayScaleResult(true, 150, null), second);
        Assert.Equal(125, record.Value);
    }

    [Fact]
    public void RestoresTheRecordedScaleAndForgetsIt()
    {
        var backend = RetinaDisplayAt(100);
        var record = new FakeRecord();
        var manager = new DisplayScaleManager(backend, record);
        manager.Apply(new DisplayScaleInput(200, false));

        var result = manager.Apply(new DisplayScaleInput(null, true));

        Assert.Equal(new DisplayScaleResult(true, 100, null), result);
        Assert.Null(record.Value);
    }

    [Fact]
    public void RestoreWithoutARecordChangesNothing()
    {
        var backend = RetinaDisplayAt(150);
        var manager = new DisplayScaleManager(backend, new FakeRecord());

        var result = manager.Apply(new DisplayScaleInput(null, true));

        Assert.Equal(new DisplayScaleResult(true, 150, null), result);
        Assert.Equal(0, backend.Writes);
    }

    [Fact]
    public void ReportsTheScaleWindowsReadsBackRatherThanTheRequest()
    {
        var backend = RetinaDisplayAt(100);
        backend.IgnoresWrites = true;
        var manager = new DisplayScaleManager(backend, new FakeRecord());

        var result = manager.Apply(new DisplayScaleInput(200, false));

        Assert.Equal(new DisplayScaleResult(true, 100, null), result);
    }

    [Fact]
    public void ReportsUnavailableAndRefused()
    {
        var unavailable = new DisplayScaleManager(new FakeBackend(null), new FakeRecord())
            .Apply(new DisplayScaleInput(200, false));
        var refusingBackend = RetinaDisplayAt(100);
        refusingBackend.RefusesWrites = true;
        var refused = new DisplayScaleManager(refusingBackend, new FakeRecord())
            .Apply(new DisplayScaleInput(200, false));

        Assert.Equal(new DisplayScaleResult(false, null, DisplayScaleResult.Unavailable), unavailable);
        Assert.Equal(new DisplayScaleResult(false, 100, DisplayScaleResult.Refused), refused);
    }

    [Fact]
    public void TheRecordFileSurvivesARestart()
    {
        var path = Path.Combine(Path.GetTempPath(), $"veil-display-scale-{Guid.NewGuid():N}.json");
        try
        {
            new UserDisplayScaleFile(path).Save(125);
            Assert.Equal(125, new UserDisplayScaleFile(path).Load());
            new UserDisplayScaleFile(path).Clear();
            Assert.Null(new UserDisplayScaleFile(path).Load());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Theory]
    [InlineData("{\"scalePercent\":200}", 200)]
    [InlineData("{\"restoresUserScale\":true}", 100)]
    public async Task AnswersARequestWithTheAppliedScale(string body, int expected)
    {
        var manager = new DisplayScaleManager(RetinaDisplayAt(100), new FakeRecord());
        var session = new AgentSession(new AgentSessionDisplayResizeTests.RecordingWindowsDesktop(), new AgentSessionDisplayResizeTests.NoOpFrameCapture(), displayScale: manager);
        var request = JsonNode.Parse(body)!.AsObject();
        request["type"] = MessageTypes.DisplayScaleRequest;
        request["requestId"] = "req_scale";

        var replies = await session.HandleAsync(request);

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.DisplayScaleResponse, response["type"]!.GetValue<string>());
        Assert.Equal("req_scale", response["requestId"]!.GetValue<string>());
        Assert.True(response["accepted"]!.GetValue<bool>());
        Assert.Equal(expected, response["scalePercent"]!.GetValue<int>());
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"scalePercent\":110}")]
    [InlineData("{\"scalePercent\":200,\"restoresUserScale\":true}")]
    [InlineData("{\"restoresUserScale\":false}")]
    public async Task RejectsARequestThatIsNotExactlyOneOfTheTwoForms(string body)
    {
        var backend = RetinaDisplayAt(100);
        var session = new AgentSession(
            new AgentSessionDisplayResizeTests.RecordingWindowsDesktop(),
            new AgentSessionDisplayResizeTests.NoOpFrameCapture(),
            displayScale: new DisplayScaleManager(backend, new FakeRecord()));
        var request = JsonNode.Parse(body)!.AsObject();
        request["type"] = MessageTypes.DisplayScaleRequest;
        request["requestId"] = "req_scale_invalid";

        var replies = await session.HandleAsync(request);

        var error = Assert.Single(replies.DirectReplies);
        Assert.Equal("invalid_message", error["code"]!.GetValue<string>());
        Assert.Equal(0, backend.Writes);
    }

    private static int Index(int percent) => DisplayScaleSteps.Percents.ToList().IndexOf(percent);

    private sealed class FakeBackend(DisplayScaleState? state) : IDisplayScaleBackend
    {
        private DisplayScaleState? state = state;

        public FakeBackend(int minRelative, int currentRelative, int maxRelative)
            : this(new DisplayScaleState(minRelative, currentRelative, maxRelative))
        {
        }

        public int Writes { get; private set; }
        public bool IgnoresWrites { get; set; }
        public bool RefusesWrites { get; set; }

        public DisplayScaleState? Read() => state;

        public bool Write(int relative)
        {
            Writes++;
            if (RefusesWrites)
            {
                return false;
            }

            if (!IgnoresWrites && state is not null)
            {
                state = state with { CurrentRelative = relative };
            }

            return true;
        }
    }

    private sealed class FakeRecord : IUserDisplayScaleRecord
    {
        public int? Value { get; private set; }

        public int? Load() => Value;

        public void Save(int scalePercent) => Value = scalePercent;

        public void Clear() => Value = null;
    }
}
