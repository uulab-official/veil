using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowsDesktopAppStartTests
{
    [Fact]
    public void AppsStartInTheUserProfileRatherThanTheAgentFolder()
    {
        var app = new WindowsAppDescriptor("winapp_paint", "Paint", "mspaint.exe", "Microsoft", "icon_paint");

        var startInfo = WindowsDesktop.AppStartInfo(app, "--new");

        Assert.Equal(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), startInfo.WorkingDirectory);
        Assert.NotEqual(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar), startInfo.WorkingDirectory);
        Assert.Equal("mspaint.exe", startInfo.FileName);
        Assert.Equal("--new", startInfo.Arguments);
        Assert.True(startInfo.UseShellExecute);
    }
}
