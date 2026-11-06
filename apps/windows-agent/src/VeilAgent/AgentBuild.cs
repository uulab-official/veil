using System.Reflection;

namespace Veil.Agent;

/// <summary>
/// The version agent health reports. A bundled build carries "0.1.0+&lt;build id&gt;", which the host
/// compares with the tools it ships to offer a tools update.
/// </summary>
internal static class AgentBuild
{
    internal static string Version { get; } =
        typeof(AgentBuild).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion
        ?? "0.1.0";
}
