using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Veil.Agent;

namespace VeilAgent.Tests;

public class StartMenuCatalogTests
{
    private const string CommonRoot = @"C:\ProgramData\Microsoft\Windows\Start Menu\Programs";
    private const string UserRoot = @"C:\Users\me\AppData\Roaming\Microsoft\Windows\Start Menu\Programs";

    private static StartMenuShortcut Shortcut(
        string relativePath,
        string target,
        string arguments = "",
        string root = CommonRoot,
        string? workingDirectory = null
    ) => new(root, $@"{root}\{relativePath}", target, arguments, workingDirectory, "Contoso");

    private static IReadOnlyList<WindowsAppDescriptor> FromShortcuts(params StartMenuShortcut[] shortcuts) =>
        StartMenuCatalog.FromShortcuts(shortcuts, _ => true);

    [Theory]
    [InlineData("Uninstall Contoso", @"C:\Program Files\Contoso\contoso.exe")]
    [InlineData("Contoso 제거", @"C:\Program Files\Contoso\contoso.exe")]
    [InlineData("Contoso", @"C:\Program Files\Contoso\uninstall.exe")]
    [InlineData("Contoso", @"C:\Program Files\Contoso\unins000.exe")]
    [InlineData("Contoso README", @"C:\Program Files\Contoso\contoso.exe")]
    [InlineData("Contoso Help", @"C:\Program Files\Contoso\contoso.exe")]
    [InlineData("Contoso Website", @"C:\Program Files\Contoso\contoso.exe")]
    [InlineData("Contoso", @"C:\Program Files\Contoso\Help.exe")]
    public void DropsUninstallersAndDocumentationLinks(string name, string target)
    {
        Assert.True(StartMenuCatalog.IsExcludedShortcut(name, target));
        Assert.Empty(FromShortcuts(Shortcut($@"Contoso\{name}.lnk", target)));
    }

    [Fact]
    public void KeepsAnAppWhoseInstallFolderMerelyContainsAnExcludedWord()
    {
        // Only the shortcut and target names count: an app installed under "Help Desk Tools" is still an app.
        Assert.False(StartMenuCatalog.IsExcludedShortcut("Ticket Viewer", @"C:\Program Files\Help Desk Tools\viewer.exe"));
    }

    [Fact]
    public void KeepsOnlyShortcutsToExistingExecutables()
    {
        var apps = StartMenuCatalog.FromShortcuts(
            [
                Shortcut("Contoso.lnk", @"C:\Program Files\Contoso\contoso.exe"),
                Shortcut("Manual.lnk", @"C:\Program Files\Contoso\manual.pdf"),
                Shortcut("Computer Management.lnk", @"C:\Windows\System32\compmgmt.msc"),
                Shortcut("Gone.lnk", @"C:\Program Files\Gone\gone.exe"),
                Shortcut("Folder.lnk", "")
            ],
            path => !path.Contains("Gone", StringComparison.Ordinal)
        );

        var app = Assert.Single(apps);
        Assert.Equal("Contoso", app.Name);
        Assert.Equal(@"C:\Program Files\Contoso\contoso.exe", app.Executable);
        Assert.Equal("Contoso", app.Publisher);
        Assert.Null(app.LaunchAumid);
    }

    [Fact]
    public void ListsTheSameTargetAndArgumentsOnce()
    {
        var apps = FromShortcuts(
            Shortcut("Contoso.lnk", @"C:\Program Files\Contoso\contoso.exe"),
            Shortcut("Contoso.lnk", @"C:\PROGRAM FILES\Contoso\Contoso.exe", root: UserRoot),
            Shortcut("Contoso Safe Mode.lnk", @"C:\Program Files\Contoso\contoso.exe", "--safe-mode")
        );

        Assert.Equal(["Contoso", "Contoso Safe Mode"], apps.Select(app => app.Name));
        Assert.Equal("--safe-mode", apps[1].ShortcutArguments);
        Assert.Null(apps[0].ShortcutArguments);
    }

    [Fact]
    public void KeepsTheShortcutsStartFolder()
    {
        var app = Assert.Single(FromShortcuts(
            Shortcut("Contoso.lnk", @"C:\Program Files\Contoso\contoso.exe", workingDirectory: @"C:\Program Files\Contoso")
        ));

        Assert.Equal(@"C:\Program Files\Contoso", app.WorkingDirectory);
    }

    [Theory]
    [InlineData(@"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Accessories\Paint.lnk", "Accessories")]
    [InlineData(@"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Windows Tools\System\Thing.lnk", "Windows Tools/System")]
    [InlineData(@"C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Contoso.lnk", null)]
    [InlineData(@"c:\programdata\microsoft\windows\start menu\programs\Accessories\Paint.lnk", "Accessories")]
    [InlineData(@"D:\Elsewhere\Contoso.lnk", null)]
    public void ComputesTheFolderRelativeToPrograms(string shortcutPath, string? expected)
    {
        Assert.Equal(expected, StartMenuCatalog.FolderFor(CommonRoot, shortcutPath));
        Assert.Equal(expected, StartMenuCatalog.FolderFor(CommonRoot + @"\", shortcutPath));
    }

    [Fact]
    public void ShortcutAppsCarryTheirFolder()
    {
        var app = Assert.Single(FromShortcuts(Shortcut(@"Accessories\Remote Desktop Connection.lnk", @"C:\Windows\System32\mstsc.exe")));

        Assert.Equal("Accessories", app.Folder);
        Assert.Equal("Remote Desktop Connection", app.Name);
    }

    [Fact]
    public void IdsAreStableAndAcceptedByTheHost()
    {
        var first = FromShortcuts(Shortcut("Contoso.lnk", @"C:\Program Files\Contoso\contoso.exe", "--a"))[0].Id;
        var again = FromShortcuts(Shortcut("Renamed.lnk", @"c:\program files\contoso\CONTOSO.exe", "--A", root: UserRoot))[0].Id;
        var other = FromShortcuts(Shortcut("Contoso.lnk", @"C:\Program Files\Contoso\contoso.exe", "--b"))[0].Id;
        var packaged = StartMenuCatalog.FromPackagedApps([new("Contoso", "Contoso.App_abc!App", "Contoso")])[0].Id;

        Assert.Equal(first, again);
        Assert.NotEqual(first, other);
        Assert.Equal(StartMenuCatalog.StableId("Contoso.App_abc!App"), packaged);
        foreach (var id in new[] { first, other, packaged })
        {
            // The host's VeilURLRoute.isValidAppId: 1-128 ASCII letters, digits, '_', '-', or '.'.
            Assert.Matches(new Regex("^start_[0-9a-f]{16}$"), id);
            Assert.Matches(new Regex("^[A-Za-z0-9_.-]{1,128}$"), id);
        }
    }

    [Fact]
    public void SkipsPackagedEntriesWithoutAUsableName()
    {
        var apps = StartMenuCatalog.FromPackagedApps(
        [
            new("", "Contoso.Blank_abc!App", "Contoso"),
            new("ms-resource:AppName", "Contoso.Unresolved_abc!App", "Contoso"),
            new("Contoso Mail", "", "Contoso"),
            new("Contoso Notes", "Contoso.Notes_abc!App", "Contoso"),
            new("Contoso Notes", "contoso.notes_abc!app", "Contoso")
        ]);

        var app = Assert.Single(apps);
        Assert.Equal("Contoso Notes", app.Name);
        Assert.Equal("Contoso.Notes_abc!App", app.LaunchAumid);
        Assert.Equal("Contoso.Notes_abc!App", app.AppUserModelId);
        Assert.Equal(@"shell:AppsFolder\Contoso.Notes_abc!App", app.Executable);
        Assert.Null(app.Folder);
    }

    [Fact]
    public void LeavesOutStartMenuEntriesThatAreBuiltInApps()
    {
        var builtIns = new[]
        {
            new WindowsAppDescriptor("winapp_notepad", "Notepad", "notepad.exe", "Microsoft", "icon_notepad", AppUserModelId: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"),
            new WindowsAppDescriptor("winapp_calculator", "Calculator", "calc.exe", "Microsoft", "icon_calculator", AlternateExecutables: ["CalculatorApp"], AppUserModelId: "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App")
        };
        var catalog = StartMenuCatalog.Combine(
            FromShortcuts(
                Shortcut(@"Accessories\Notepad.lnk", @"C:\Windows\System32\notepad.exe"),
                Shortcut("Calc Launcher.lnk", @"C:\Program Files\WindowsApps\CalculatorApp.exe"),
                Shortcut("Contoso.lnk", @"C:\Program Files\Contoso\contoso.exe")
            ),
            StartMenuCatalog.FromPackagedApps(
            [
                new("Calculator", "microsoft.windowscalculator_8wekyb3d8bbwe!App", "Microsoft"),
                new("Terminal", "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App", "Microsoft")
            ])
        );

        var remaining = StartMenuCatalog.WithoutBuiltIns(builtIns, catalog);

        Assert.Equal(["Contoso", "Terminal"], remaining.Select(app => app.Name));
    }

    [Fact]
    public async Task ReturnsNothingRatherThanWaitingPastTheLimitForTheFirstDiscovery()
    {
        using var release = new ManualResetEventSlim();
        var catalog = new StartMenuCatalog(() =>
        {
            release.Wait(TimeSpan.FromSeconds(10));
            return [ContosoApp()];
        });

        var apps = await catalog.GetAppsAsync(TimeSpan.FromMilliseconds(50), CancellationToken.None);
        Assert.Empty(apps);

        release.Set();
        await catalog.StartRefresh();
        Assert.Single(await catalog.GetAppsAsync(TimeSpan.FromMilliseconds(50), CancellationToken.None));
    }

    [Fact]
    public async Task RediscoversAtMostOncePerRefreshInterval()
    {
        var now = DateTimeOffset.Parse("2026-11-11T09:00:00Z");
        var discoveries = 0;
        var catalog = new StartMenuCatalog(
            () =>
            {
                Interlocked.Increment(ref discoveries);
                return [ContosoApp()];
            },
            refreshInterval: TimeSpan.FromMinutes(5),
            now: () => now
        );

        await catalog.StartRefresh();
        await catalog.GetAppsAsync(TimeSpan.FromSeconds(2), CancellationToken.None);
        await catalog.StartRefresh();
        Assert.Equal(1, discoveries);

        now = now.AddMinutes(5);
        await catalog.StartRefresh();
        Assert.Equal(2, discoveries);
    }

    [Fact]
    public async Task KeepsThePreviousListWhenADiscoveryFails()
    {
        var now = DateTimeOffset.Parse("2026-11-11T09:00:00Z");
        var fail = false;
        var catalog = new StartMenuCatalog(
            () => fail ? throw new InvalidOperationException("package manager unavailable") : [ContosoApp()],
            refreshInterval: TimeSpan.FromMinutes(5),
            now: () => now
        );
        await catalog.StartRefresh();

        fail = true;
        now = now.AddMinutes(6);
        await catalog.StartRefresh();

        Assert.Single(await catalog.GetAppsAsync(TimeSpan.Zero, CancellationToken.None));
    }

    [Fact]
    public void ShortcutArgumentsComeBeforeAnyFileArgument()
    {
        Assert.Equal("--profile work \"C:\\a.txt\"", WindowsDesktop.CombineArguments("--profile work", "\"C:\\a.txt\""));
        Assert.Equal("--profile work", WindowsDesktop.CombineArguments("--profile work", null));
        Assert.Equal(string.Empty, WindowsDesktop.CombineArguments(null, null));
    }

    [Fact]
    public void ShortcutAppsStartWithTheirArguments()
    {
        var app = ContosoApp() with { ShortcutArguments = "--profile work", WorkingDirectory = @"Z:\does-not-exist" };

        var startInfo = WindowsDesktop.AppStartInfo(app, null);

        Assert.Equal(@"C:\Program Files\Contoso\contoso.exe", startInfo.FileName);
        Assert.Equal("--profile work", startInfo.Arguments);
        // A start folder that no longer exists would make the launch fail; the user profile is used instead.
        Assert.Equal(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), startInfo.WorkingDirectory);
    }

    [Fact]
    public void PackagedAppsDoNotMatchProcessesByTheirShellPath()
    {
        var app = StartMenuCatalog.FromPackagedApps([new("Calculator", "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App", "Microsoft")])[0];

        Assert.Empty(WindowsDesktop.CandidateProcessNames(app));
    }

    [Fact]
    public async Task AppListIncludesStartMenuAppsAfterTheBuiltInApps()
    {
        var session = new AgentSession(
            new RecordingDesktop(),
            new NoFrames(),
            startMenu: new FixedStartMenu(
                ContosoApp() with { Folder = "Contoso Tools" },
                // Notepad from the Start menu is the built-in Notepad, so it is not listed again.
                ContosoApp() with { Id = StartMenuCatalog.StableId(@"C:\Windows\System32\notepad.exe"), Name = "Notepad", Executable = @"C:\Windows\System32\notepad.exe" }
            )
        );

        var replies = await session.HandleAsync(new JsonObject { ["type"] = MessageTypes.AppListRequest, ["requestId"] = "req_apps" });

        var apps = replies.DirectReplies[0]["apps"]!.AsArray().Select(app => app!.AsObject()).ToArray();
        Assert.Equal(["winapp_notepad", "winapp_calculator", "winapp_paint", "winapp_explorer", ContosoApp().Id], apps.Select(app => app["id"]!.GetValue<string>()));
        Assert.All(apps.Take(4), app => Assert.False(app.ContainsKey("folder")));
        Assert.Equal("Contoso Tools", apps[4]["folder"]!.GetValue<string>());
        Assert.Equal(@"C:\Program Files\Contoso\contoso.exe", apps[4]["exePath"]!.GetValue<string>());
    }

    [Fact]
    public async Task LaunchesAStartMenuAppByItsId()
    {
        var desktop = new RecordingDesktop();
        var session = new AgentSession(desktop, new NoFrames(), startMenu: new FixedStartMenu(ContosoApp()));

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AppLaunchRequest,
            ["requestId"] = "req_launch",
            ["appId"] = ContosoApp().Id
        });

        Assert.Equal(MessageTypes.AppLaunchResponse, replies.DirectReplies[0]["type"]!.GetValue<string>());
        Assert.Equal(ContosoApp().Id, Assert.Single(desktop.Launched).Id);
        var created = replies.DirectReplies[1];
        Assert.Equal(MessageTypes.WindowCreated, created["type"]!.GetValue<string>());
        Assert.Equal(ContosoApp().Id, created["appId"]!.GetValue<string>());
    }

    [Fact]
    public async Task RefusesAnIdTheStartMenuDoesNotHave()
    {
        var desktop = new RecordingDesktop();
        var session = new AgentSession(desktop, new NoFrames(), startMenu: new FixedStartMenu(ContosoApp()));

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AppLaunchRequest,
            ["requestId"] = "req_launch",
            ["appId"] = "start_0000000000000000"
        });

        Assert.Equal("app_not_found", replies.DirectReplies[0]["code"]!.GetValue<string>());
        Assert.Empty(desktop.Launched);
    }

    private static WindowsAppDescriptor ContosoApp() =>
        StartMenuCatalog.FromShortcuts([Shortcut("Contoso.lnk", @"C:\Program Files\Contoso\contoso.exe")], _ => true)[0];

    private sealed class FixedStartMenu(params WindowsAppDescriptor[] apps) : IStartMenuCatalogSource
    {
        public Task<IReadOnlyList<WindowsAppDescriptor>> GetAppsAsync(TimeSpan maxWait, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<WindowsAppDescriptor>>(apps);
    }

    private sealed class NoFrames : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    private sealed class RecordingDesktop : IWindowsDesktop
    {
        public List<WindowsAppDescriptor> Launched { get; } = [];

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken)
        {
            Launched.Add(app);
            return Task.FromResult(new LaunchedWindow("hwnd:00000040", 0x40, 5120, app.Name, new WindowRect(0, 0, 800, 600), "normal", true));
        }

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];
        public bool IsWindowStillOpen(string windowId) => true;
        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) => Task.FromResult(false);
        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) => Task.FromResult<string?>(null);
        public bool TryConsumeHostClipboardEcho(string text) => false;
    }
}
