using System.Text;
using Veil.Agent;

namespace VeilAgent.Tests;

public sealed class VirtioSerialPortProbeTests
{
    [Fact]
    public void UsesTheUpstreamVioserInformationIoctlCode()
    {
        Assert.Equal(0x00222002u, VirtioSerialPortProbe.GetInformationIoctlCode());
    }

    [Fact]
    public void ParsesPortNameAndConnectionStateFromVioserResponse()
    {
        var response = new byte[32];
        response[5] = 1;
        response[6] = 0;
        Encoding.ASCII.GetBytes("org.veil.agent").CopyTo(response, 7);

        var result = VirtioSerialPortProbe.ParsePortInfo(
            "\\\\?\\vioserial#port",
            response,
            7 + "org.veil.agent".Length + 1
        );

        Assert.Equal("org.veil.agent", result.PortName);
        Assert.True(result.HostConnected);
        Assert.False(result.GuestConnected);
    }

    [Fact]
    public void DoesNotInventANameWhenTheDriverReturnsNoName()
    {
        var result = VirtioSerialPortProbe.ParsePortInfo(
            "device",
            new byte[8],
            8
        );

        Assert.Null(result.PortName);
        Assert.False(result.HostConnected);
        Assert.False(result.GuestConnected);
    }
}
