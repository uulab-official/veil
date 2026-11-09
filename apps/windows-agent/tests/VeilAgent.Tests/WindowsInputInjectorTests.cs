using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowsInputInjectorTests
{
    [Fact]
    public void MapsMouseEventsToRealButtonTransitions()
    {
        Assert.Equal(WindowsInputInjector.MOUSEEVENTF_LEFTDOWN, WindowsInputInjector.MouseButtonFlags("leftDown"));
        Assert.Equal(WindowsInputInjector.MOUSEEVENTF_LEFTUP, WindowsInputInjector.MouseButtonFlags("leftUp"));
        Assert.Equal(WindowsInputInjector.MOUSEEVENTF_RIGHTDOWN, WindowsInputInjector.MouseButtonFlags("rightDown"));
        Assert.Equal(WindowsInputInjector.MOUSEEVENTF_WHEEL, WindowsInputInjector.MouseButtonFlags("scroll"));
        // A move carries no button flag: the button pressed by leftDown stays down in Windows' own input
        // state, which is what lets a drag paint in Paint. Posted WM_MOUSEMOVE had no button state at all.
        Assert.Equal(0u, WindowsInputInjector.MouseButtonFlags("move"));
        Assert.Null(WindowsInputInjector.MouseButtonFlags("doubleTap"));
    }

    [Theory]
    [InlineData(0, 0, 0, 0)]
    [InlineData(2047, 1279, 65535, 65535)]
    [InlineData(1024, 640, 32784, 32793)]
    [InlineData(-50, 5000, 0, 65535)]
    public void NormalizesScreenPixelsAcrossTheVirtualDesktop(int x, int y, int expectedX, int expectedY)
    {
        var normalized = WindowsInputInjector.NormalizeToVirtualDesktop(x, y, 0, 0, 2048, 1280);

        Assert.Equal((expectedX, expectedY), normalized);
    }

    [Fact]
    public void KeepsTheInputStructBlittableSoTheUnionIsNotOverwritten()
    {
        // A non-blittable union member made the marshaler write the empty keyboard member over the mouse
        // member, so every injected mouse event was a no-op.
        var size = System.Runtime.InteropServices.Marshal.SizeOf<WindowsInputInjector.NativeInput>();
        Assert.Equal(IntPtr.Size == 8 ? 40 : 28, size);
        Assert.Equal(size, System.Runtime.CompilerServices.Unsafe.SizeOf<WindowsInputInjector.NativeInput>());
        Assert.True(IsBlittable<WindowsInputInjector.NativeInput>());
    }

    private static bool IsBlittable<T>() where T : struct
    {
        try
        {
            var handle = System.Runtime.InteropServices.GCHandle.Alloc(new T[1], System.Runtime.InteropServices.GCHandleType.Pinned);
            handle.Free();
            return true;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    [Fact]
    public void NormalizesToTheTabletRangeForTheHostPointer()
    {
        Assert.Equal((32767, 32767), WindowsInputInjector.NormalizeToVirtualDesktop(2047, 1279, 0, 0, 2048, 1280, GuestPointerPosition.MaximumAbsolute));
        Assert.Equal((0, 0), WindowsInputInjector.NormalizeToVirtualDesktop(0, 0, 0, 0, 2048, 1280, GuestPointerPosition.MaximumAbsolute));
    }

    [Fact]
    public void WrapsAKeyInItsModifiers()
    {
        var down = WindowsInputInjector.KeySequence("keyDown", 0x5A, ["ctrl"]);
        var up = WindowsInputInjector.KeySequence("keyUp", 0x5A, ["ctrl"]);

        Assert.Equal(new[] { (0x11, false), (0x5A, false) }, down);
        Assert.Equal(new[] { (0x5A, true), (0x11, true) }, up);
        Assert.Empty(WindowsInputInjector.KeySequence("keyPress", 0x5A, []));
    }

    [Fact]
    public void MarksNavigationKeysAsExtended()
    {
        Assert.True(WindowsInputInjector.IsExtendedKey(0x25));
        Assert.True(WindowsInputInjector.IsExtendedKey(0x2E));
        Assert.False(WindowsInputInjector.IsExtendedKey(0x5A));
    }

    [Theory]
    [InlineData(50, 40, 1182, 600, 50, 40)]
    [InlineData(400, 100, 1182, 600, 98, 100)]
    [InlineData(-30, -10, 600, 400, 0, 0)]
    [InlineData(500, 100, 1500, 900, 0, 0)]
    public void MovesAWindowOntoTheWorkAreaWhenItFits(
        int left, int top, int width, int height, int expectedLeft, int expectedTop)
    {
        var placed = WindowsInputInjector.PlaceWithin(left, top, width, height, 0, 0, 1280, 720);

        Assert.Equal((expectedLeft, expectedTop), placed);
    }
}
