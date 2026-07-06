using System.Diagnostics;
using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowsDesktopMatchingTests
{
    [Fact]
    public void MatchesWhenExecutableNameEqualsProcessName()
    {
        var currentProcess = Process.GetCurrentProcess();
        var app = new WindowsAppDescriptor(
            Id: "test_app",
            Name: "Test App",
            Executable: $"{currentProcess.ProcessName}.exe",
            Publisher: "Test",
            IconId: "icon_test"
        );

        Assert.True(WindowsDesktop.DoesProcessMatchApp((uint)currentProcess.Id, app));
    }

    [Fact]
    public void DoesNotMatchWhenNeitherExecutableNorAlternatesMatch()
    {
        var currentProcess = Process.GetCurrentProcess();
        var app = new WindowsAppDescriptor(
            Id: "test_app",
            Name: "Test App",
            Executable: "definitely-not-this-process.exe",
            Publisher: "Test",
            IconId: "icon_test",
            AlternateExecutables: ["also-not-this-process"]
        );

        Assert.False(WindowsDesktop.DoesProcessMatchApp((uint)currentProcess.Id, app));
    }

    [Fact]
    public void MatchesViaAlternateExecutableWhenPrimaryExecutableDoesNotMatch()
    {
        // Regression test for the Windows 11 Calculator case: calc.exe is a launcher stub, and the
        // actual top-level window belongs to a differently-named process (CalculatorApp.exe). The
        // descriptor's primary Executable intentionally does not match the running process here;
        // only the alternate name should make the match succeed.
        var currentProcess = Process.GetCurrentProcess();
        var app = new WindowsAppDescriptor(
            Id: "test_app",
            Name: "Test App",
            Executable: "definitely-not-this-process.exe",
            Publisher: "Test",
            IconId: "icon_test",
            AlternateExecutables: [currentProcess.ProcessName]
        );

        Assert.True(WindowsDesktop.DoesProcessMatchApp((uint)currentProcess.Id, app));
    }

    [Fact]
    public void ReturnsFalseForAnUnknownProcessId()
    {
        var app = new WindowsAppDescriptor(
            Id: "test_app",
            Name: "Test App",
            Executable: "whatever.exe",
            Publisher: "Test",
            IconId: "icon_test"
        );

        Assert.False(WindowsDesktop.DoesProcessMatchApp(uint.MaxValue, app));
    }

    [Fact]
    public void DefaultWindowDiscoveryTimeoutIsFiveSeconds()
    {
        var app = new WindowsAppDescriptor(
            Id: "test_app",
            Name: "Test App",
            Executable: "whatever.exe",
            Publisher: "Test",
            IconId: "icon_test"
        );

        Assert.Equal(TimeSpan.FromSeconds(5), app.WindowDiscoveryTimeout);
    }

    [Fact]
    public void WindowDiscoveryTimeoutOverrideIsRespected()
    {
        var app = new WindowsAppDescriptor(
            Id: "test_app",
            Name: "Test App",
            Executable: "whatever.exe",
            Publisher: "Test",
            IconId: "icon_test",
            WindowDiscoveryTimeoutOverride: TimeSpan.FromSeconds(12)
        );

        Assert.Equal(TimeSpan.FromSeconds(12), app.WindowDiscoveryTimeout);
    }
}
