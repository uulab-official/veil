using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowFrameChangeTrackerTests
{
    [Fact]
    public void FirstBufferIsChangedAndIdenticalBufferIsUnchanged()
    {
        var tracker = new WindowFrameChangeTracker();

        Assert.True(tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 }));
        Assert.False(tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 }));
    }

    [Fact]
    public void ChangedBytesAndChangedDimensionsProduceAFrame()
    {
        var tracker = new WindowFrameChangeTracker();
        tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 });

        Assert.True(tracker.HasChanged("hwnd:1", new byte[] { 1, 9, 3, 4 }));
        Assert.True(tracker.HasChanged("hwnd:1", new byte[] { 1, 9, 3, 4, 5 }));
    }

    [Fact]
    public void TracksWindowsIndependently()
    {
        var tracker = new WindowFrameChangeTracker();

        Assert.True(tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 }));
        Assert.True(tracker.HasChanged("hwnd:2", new byte[] { 1, 2, 3, 4 }));
        Assert.False(tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 }));
        Assert.False(tracker.HasChanged("hwnd:2", new byte[] { 1, 2, 3, 4 }));
    }

    [Fact]
    public void ForgetMakesTheNextBufferAChangedFirstFrame()
    {
        var tracker = new WindowFrameChangeTracker();
        tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 });
        Assert.False(tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 }));

        tracker.Forget("hwnd:1");

        Assert.True(tracker.HasChanged("hwnd:1", new byte[] { 1, 2, 3, 4 }));
    }
}
