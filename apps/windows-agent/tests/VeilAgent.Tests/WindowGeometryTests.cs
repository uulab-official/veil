using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowGeometryTests
{
    [Fact]
    public void UsesTheVisibleFrameInsideTheInvisibleResizeBorders()
    {
        // Windows 11 at 100%: 7 px invisible borders left, right, and bottom.
        var geometry = WindowGeometry.FromRects(
            new WindowRect(93, 50, 1038, 622),
            new WindowRect(100, 50, 1024, 615)
        );

        Assert.Equal(new WindowRect(100, 50, 1024, 615), geometry.Visible);
        Assert.Equal(7, geometry.InsetX);
        Assert.Equal(0, geometry.InsetY);
        Assert.Equal(14, geometry.ExtraWidth);
        Assert.Equal(7, geometry.ExtraHeight);
    }

    [Fact]
    public void KeepsTheFrameInsideTheOuterRectangle()
    {
        var geometry = WindowGeometry.FromRects(
            new WindowRect(0, 0, 800, 600),
            new WindowRect(-10, -10, 900, 700)
        );

        Assert.Equal(new WindowRect(0, 0, 800, 600), geometry.Visible);
    }

    [Fact]
    public void FallsBackToTheOuterRectangleForAnEmptyFrame()
    {
        var outer = new WindowRect(10, 10, 300, 200);

        var geometry = WindowGeometry.FromRects(outer, new WindowRect(500, 500, 0, 0));

        Assert.Equal(outer, geometry.Visible);
    }
}
