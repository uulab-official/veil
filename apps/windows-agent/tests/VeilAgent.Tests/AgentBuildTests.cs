using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentBuildTests
{
    [Fact]
    public void ReportsTheProjectVersionWhenNoBuildIdWasStamped()
    {
        // A bundled build appends "+<build id>"; a plain test build reports the project version.
        Assert.StartsWith("0.1.0", AgentBuild.Version);
        Assert.DoesNotContain("1.0.0", AgentBuild.Version);
    }
}
