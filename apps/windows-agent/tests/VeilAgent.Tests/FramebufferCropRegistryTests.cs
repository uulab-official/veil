using Veil.Agent;

namespace VeilAgent.Tests;

[Collection("FramebufferCropRegistry")]
public class FramebufferCropRegistryTests
{
    [Fact]
    public void ACropListLapsesUnlessTheHostRepeatsIt()
    {
        FramebufferCropRegistry.Set(new[] { "hwnd:1" }, nowMilliseconds: 10_000);

        Assert.True(FramebufferCropRegistry.IsCropped("hwnd:1", nowMilliseconds: 15_000));
        Assert.False(FramebufferCropRegistry.IsCropped("hwnd:2", nowMilliseconds: 15_000));
        Assert.False(FramebufferCropRegistry.IsCropped("hwnd:1", nowMilliseconds: 16_001));

        FramebufferCropRegistry.Set(Array.Empty<string>(), nowMilliseconds: 16_002);
        Assert.False(FramebufferCropRegistry.IsCropped("hwnd:1", nowMilliseconds: 16_003));
        FramebufferCropRegistry.Clear();
    }
}
