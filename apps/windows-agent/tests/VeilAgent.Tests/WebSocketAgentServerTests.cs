using System.Net.Sockets;
using Veil.Agent;

namespace VeilAgent.Tests;

public class WebSocketAgentServerTests
{
    [Theory]
    [InlineData(SocketError.ConnectionAborted)]
    [InlineData(SocketError.ConnectionReset)]
    [InlineData(SocketError.Interrupted)]
    public void KeepsTheAgentListenerAliveAfterTransientAcceptFailures(SocketError error)
    {
        Assert.True(WebSocketAgentServer.IsTransientAcceptSocketError(error));
    }

    [Fact]
    public void DoesNotTreatPermanentAcceptFailuresAsTransient()
    {
        Assert.False(WebSocketAgentServer.IsTransientAcceptSocketError(SocketError.AccessDenied));
    }
}
