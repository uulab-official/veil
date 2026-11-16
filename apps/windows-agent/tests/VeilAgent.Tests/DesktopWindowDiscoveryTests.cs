using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class DesktopWindowDiscoveryTests
{
    private static TopLevelWindowFacts Facts(
        string className = "Notepad",
        string title = "Untitled - Notepad",
        string processName = "Notepad",
        bool visible = true,
        bool minimized = false,
        bool cloaked = false,
        bool hasOwner = false,
        bool toolWindow = false,
        bool appWindow = false,
        bool noActivate = false
    ) => new(visible, minimized, cloaked, hasOwner, toolWindow, appWindow, noActivate, className, title, processName);

    [Fact]
    public void AnOrdinaryTitledWindowIsAnAppWindow()
    {
        Assert.True(AppWindowRules.IsAppWindow(Facts()));
        Assert.True(AppWindowRules.IsAppWindow(Facts(className: "CabinetWClass", title: "Documents", processName: "explorer")));
    }

    [Theory]
    [InlineData("Progman", "explorer")]
    [InlineData("WorkerW", "explorer")]
    [InlineData("Shell_TrayWnd", "explorer")]
    [InlineData("Windows.UI.Core.CoreWindow", "StartMenuExperienceHost")]
    [InlineData("XamlExplorerHostIslandWindow", "explorer")]
    [InlineData("ApplicationFrameWindow", "TextInputHost")]
    [InlineData("Windows.UI.Core.CoreWindow", "SearchHost")]
    public void ShellWindowsAreNotAppWindows(string className, string processName)
    {
        Assert.False(AppWindowRules.IsAppWindow(Facts(className: className, title: "Program Manager", processName: processName)));
    }

    [Fact]
    public void HiddenMinimizedCloakedAndUntitledWindowsAreLeftOut()
    {
        Assert.False(AppWindowRules.IsAppWindow(Facts(visible: false)));
        Assert.False(AppWindowRules.IsAppWindow(Facts(minimized: true)));
        Assert.False(AppWindowRules.IsAppWindow(Facts(cloaked: true)));
        Assert.False(AppWindowRules.IsAppWindow(Facts(title: " ")));
    }

    [Fact]
    public void ToolOwnedAndNeverFocusedWindowsNeedTheAppWindowStyle()
    {
        Assert.False(AppWindowRules.IsAppWindow(Facts(toolWindow: true)));
        Assert.False(AppWindowRules.IsAppWindow(Facts(hasOwner: true)));
        Assert.False(AppWindowRules.IsAppWindow(Facts(noActivate: true)));
        Assert.True(AppWindowRules.IsAppWindow(Facts(hasOwner: true, appWindow: true)));
        Assert.True(AppWindowRules.IsAppWindow(Facts(toolWindow: true, appWindow: true)));
    }

    private static readonly WindowsAppDescriptor Notepad = new(
        "winapp_notepad", "Notepad", "notepad.exe", "Microsoft", "icon_notepad",
        AppUserModelId: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App");

    private static readonly WindowsAppDescriptor Clock = new(
        "start_clock", "시계", @"shell:AppsFolder\Microsoft.WindowsAlarms_8wekyb3d8bbwe!App", "Microsoft", "icon_clock",
        AppUserModelId: "Microsoft.WindowsAlarms_8wekyb3d8bbwe!App",
        LaunchAumid: "Microsoft.WindowsAlarms_8wekyb3d8bbwe!App");

    private static readonly WindowsAppDescriptor PowerShellWithArguments = new(
        "start_ps_args", "PowerShell (x86)", @"C:\Windows\System32\powershell.exe", "", "icon_ps_args",
        ShortcutArguments: "-NoExit");

    private static readonly WindowsAppDescriptor PowerShell = new(
        "start_ps", "PowerShell", @"C:\Windows\System32\powershell.exe", "", "icon_ps");

    private static DiscoveredAppWindow Found(
        string windowId,
        string processName,
        string? path = null,
        string? aumid = null,
        string title = "Window"
    ) => new(Window(windowId, title), processName, path, aumid);

    private static LaunchedWindow Window(string windowId, string title = "Window") => new(
        WindowId: windowId,
        Hwnd: 0,
        ProcessId: 4242,
        Title: title,
        Bounds: new WindowRect(10, 20, 640, 480),
        State: "normal",
        Focused: true
    );

    [Fact]
    public void AWindowIsMatchedByAppUserModelIdThenPathThenProgramName()
    {
        WindowsAppDescriptor[] apps = [Notepad, Clock, PowerShellWithArguments, PowerShell];

        // A UWP app's window belongs to ApplicationFrameHost.exe.
        var clock = Found("hwnd:1", "ApplicationFrameHost", @"C:\Windows\System32\ApplicationFrameHost.exe",
            "Microsoft.WindowsAlarms_8wekyb3d8bbwe!App");
        Assert.Same(Clock, RunningAppCatalog.Match(clock, apps));

        // Several shortcuts start one program; the one without arguments is the app.
        var shell = Found("hwnd:2", "powershell", @"c:\windows\system32\POWERSHELL.EXE");
        Assert.Same(PowerShell, RunningAppCatalog.Match(shell, apps));

        // A built-in app declares only its file name.
        var notepad = Found("hwnd:3", "Notepad", @"C:\Program Files\WindowsApps\Notepad\Notepad.exe");
        Assert.Same(Notepad, RunningAppCatalog.Match(notepad, apps));
    }

    [Fact]
    public void AnUnknownProgramAndAnUnknownUwpAppMatchNothing()
    {
        WindowsAppDescriptor[] apps = [Notepad, Clock];

        Assert.Null(RunningAppCatalog.Match(Found("hwnd:1", "explorer", @"C:\Windows\explorer.exe"), apps));
        Assert.Null(RunningAppCatalog.Match(
            Found("hwnd:2", "ApplicationFrameHost", @"C:\Windows\System32\ApplicationFrameHost.exe", "Contoso.App_abc!App"),
            apps));
    }

    [Fact]
    public void AnUnknownProgramBecomesARunningAppNamedByItsFileDescription()
    {
        var explorer = Found("hwnd:1", "explorer", @"C:\Windows\explorer.exe", title: "문서");
        var second = Found("hwnd:2", "explorer", @"C:\WINDOWS\Explorer.EXE", title: "다운로드");

        var app = RunningAppCatalog.Describe(explorer, _ => " Windows 탐색기 ");
        var sameApp = RunningAppCatalog.Describe(second, _ => "Windows 탐색기");

        Assert.StartsWith(RunningAppCatalog.IdPrefix, app.Id);
        Assert.Equal(app.Id.Length, RunningAppCatalog.IdPrefix.Length + 16);
        Assert.Equal(app.Id, sameApp.Id);
        Assert.Equal("Windows 탐색기", app.Name);
        Assert.Equal(@"C:\Windows\explorer.exe", app.Executable);
        Assert.Null(app.LaunchAumid);
        Assert.True(RunningAppCatalog.IsRunningAppId(app.Id));
        Assert.False(RunningAppCatalog.IsRunningAppId("start_0123456789abcdef"));
    }

    [Fact]
    public void AProgramWithoutADescriptionIsNamedByItsProcess()
    {
        var app = RunningAppCatalog.Describe(Found("hwnd:1", "contoso", @"C:\Tools\contoso.exe"), _ => null);

        Assert.Equal("contoso", app.Name);
    }

    [Fact]
    public void AnUnknownUwpAppIsNamedByItsWindowAndLaunchedByAppUserModelId()
    {
        var window = Found("hwnd:1", "ApplicationFrameHost", @"C:\Windows\System32\ApplicationFrameHost.exe",
            "Contoso.App_abc!App", title: "Contoso");
        var other = Found("hwnd:2", "ApplicationFrameHost", @"C:\Windows\System32\ApplicationFrameHost.exe",
            "Fabrikam.App_abc!App", title: "Fabrikam");

        var app = RunningAppCatalog.Describe(window, _ => "Application Frame Host");
        var otherApp = RunningAppCatalog.Describe(other, _ => "Application Frame Host");

        Assert.Equal("Contoso", app.Name);
        Assert.Equal("Contoso.App_abc!App", app.LaunchAumid);
        Assert.NotEqual(app.Id, otherApp.Id);
    }

    private sealed class DesktopWithWindows : IWindowsDesktop
    {
        public List<DiscoveredAppWindow> AppWindows { get; } = [];
        public HashSet<string> Closed { get; } = [];
        public Dictionary<string, LaunchedWindow> Current { get; } = [];
        public TaskCompletionSource<LaunchedWindow>? PendingLaunch { get; set; }
        public List<WindowsAppDescriptor> Launched { get; } = [];

        public IReadOnlyList<DiscoveredAppWindow> DiscoverAppWindows(IReadOnlySet<string> knownWindowIds) =>
            AppWindows.Where(found => !knownWindowIds.Contains(found.Window.WindowId)).ToArray();

        public LaunchedWindow CurrentWindow(LaunchedWindow window) =>
            Current.TryGetValue(window.WindowId, out var current) ? current : window;

        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken)
        {
            Launched.Add(app);
            return PendingLaunch?.Task ?? Task.FromResult(Window("hwnd:launched", app.Name));
        }

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];

        public bool IsWindowStillOpen(string windowId) => !Closed.Contains(windowId);

        public Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task SetClipboardTextAsync(string text, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public bool TryConsumeHostClipboardEcho(string text) => false;
    }

    private sealed class NoFrames : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    private sealed class FixedStartMenu(params WindowsAppDescriptor[] apps) : IStartMenuCatalogSource
    {
        public Task<IReadOnlyList<WindowsAppDescriptor>> GetAppsAsync(TimeSpan maxWait, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<WindowsAppDescriptor>>(apps);
    }

    private static async Task<List<JsonObject>> RunDiscoveryAsync(AgentSession session, IWindowsDesktop desktop)
    {
        var streamer = new WindowDiscoveryStreamer(session, desktop, interval: TimeSpan.FromMilliseconds(5));
        var broadcasts = new List<JsonObject>();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(60));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => streamer.StreamAsync(
            (message, _) =>
            {
                broadcasts.Add(message);
                return Task.CompletedTask;
            },
            cancellation.Token
        ));
        return broadcasts;
    }

    [Fact]
    public async Task AWindowOpenedInsideWindowsIsAnnouncedOnceUnderItsApp()
    {
        var desktop = new DesktopWithWindows();
        desktop.AppWindows.Add(Found("hwnd:0000000A", "Notepad", @"C:\Apps\Notepad.exe", title: "notes.txt - Notepad"));
        desktop.AppWindows.Add(Found("hwnd:0000000B", "contoso", @"C:\Tools\contoso.exe", title: "Contoso"));
        desktop.AppWindows.Add(Found("hwnd:0000000C", "explorer", @"C:\Windows\explorer.exe", title: "문서"));
        var session = new AgentSession(desktop, new NoFrames(), startMenu: new FixedStartMenu());

        var broadcasts = await RunDiscoveryAsync(session, desktop);

        Assert.Equal(3, broadcasts.Count);
        Assert.All(broadcasts, message => Assert.Equal("window.created", message["type"]!.GetValue<string>()));
        Assert.Equal("winapp_notepad", broadcasts[0]["appId"]!.GetValue<string>());
        Assert.Equal("notes.txt - Notepad", broadcasts[0]["title"]!.GetValue<string>());
        Assert.StartsWith("proc_", broadcasts[1]["appId"]!.GetValue<string>());
        // File Explorer is a built-in app, though its window belongs to the shell's process.
        Assert.Equal("winapp_explorer", broadcasts[2]["appId"]!.GetValue<string>());
    }

    [Fact]
    public async Task DiscoveryWaitsWhileALaunchIsLookingForItsWindow()
    {
        var desktop = new DesktopWithWindows { PendingLaunch = new TaskCompletionSource<LaunchedWindow>() };
        var session = new AgentSession(desktop, new NoFrames(), startMenu: new FixedStartMenu());
        var launch = session.HandleAsync(new JsonObject
        {
            ["type"] = "app.launch.request",
            ["requestId"] = "req_launch",
            ["appId"] = "winapp_notepad"
        });
        // The window appears on the desktop before the launch has reported it.
        desktop.AppWindows.Add(Found("hwnd:0000000A", "Notepad", @"C:\Apps\Notepad.exe"));

        Assert.True(session.IsLaunching);
        Assert.Empty(await RunDiscoveryAsync(session, desktop));

        desktop.PendingLaunch.SetResult(Window("hwnd:0000000A"));
        var replies = await launch;

        Assert.False(session.IsLaunching);
        Assert.Equal("hwnd:0000000A", replies.DirectReplies[1]["windowId"]!.GetValue<string>());
        // Tracked by the launch, so discovery has nothing left to announce.
        Assert.Empty(await RunDiscoveryAsync(session, desktop));
    }

    [Fact]
    public async Task WindowListTracksUnreportedWindowsAndAnswersWithTheirCurrentState()
    {
        var desktop = new DesktopWithWindows();
        desktop.AppWindows.Add(Found("hwnd:0000000A", "charmap", @"C:\Windows\System32\charmap.exe", title: "문자표"));
        desktop.AppWindows.Add(Found("hwnd:0000000B", "Notepad", @"C:\Apps\Notepad.exe", title: "old title"));
        desktop.Current["hwnd:0000000A"] = Window("hwnd:0000000A", "문자표") with { Resizable = false };
        desktop.Current["hwnd:0000000B"] = Window("hwnd:0000000B", "new title") with
        {
            Bounds = new WindowRect(100, 200, 800, 600)
        };
        var session = new AgentSession(desktop, new NoFrames(), startMenu: new FixedStartMenu());

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = "window.list.request",
            ["requestId"] = "req_list"
        });

        Assert.Equal("window.list.response", replies.DirectReplies[0]["type"]!.GetValue<string>());
        Assert.Equal("req_list", replies.DirectReplies[0]["requestId"]!.GetValue<string>());
        Assert.Equal(
            ["hwnd:0000000A", "hwnd:0000000B"],
            replies.DirectReplies[0]["windowIds"]!.AsArray().Select(node => node!.GetValue<string>()).Order().ToArray()
        );
        var created = replies.DirectReplies.Skip(1).ToDictionary(message => message["windowId"]!.GetValue<string>());
        Assert.Equal(2, created.Count);
        Assert.False(created["hwnd:0000000A"]["resizable"]!.GetValue<bool>());
        Assert.Null(created["hwnd:0000000B"]["resizable"]);
        Assert.Equal("new title", created["hwnd:0000000B"]["title"]!.GetValue<string>());
        Assert.Equal(800, created["hwnd:0000000B"]["bounds"]!["width"]!.GetValue<int>());
        Assert.Empty(replies.BroadcastEvents);

        // Already tracked, so the discovery stream does not announce them a second time.
        Assert.Empty(await RunDiscoveryAsync(session, desktop));
    }

    [Fact]
    public async Task WindowListLeavesOutAWindowThatHasClosed()
    {
        var desktop = new DesktopWithWindows();
        desktop.AppWindows.Add(Found("hwnd:0000000A", "Notepad", @"C:\Apps\Notepad.exe"));
        var session = new AgentSession(desktop, new NoFrames(), startMenu: new FixedStartMenu());
        _ = await session.HandleAsync(new JsonObject { ["type"] = "window.list.request", ["requestId"] = "first" });
        desktop.AppWindows.Clear();
        desktop.Closed.Add("hwnd:0000000A");

        var replies = await session.HandleAsync(new JsonObject { ["type"] = "window.list.request", ["requestId"] = "second" });

        Assert.Single(replies.DirectReplies);
        Assert.Empty(replies.DirectReplies[0]["windowIds"]!.AsArray());
    }

    [Fact]
    public async Task ARunningAppIsListedAsRunningAndCanBeLaunchedById()
    {
        var desktop = new DesktopWithWindows();
        desktop.AppWindows.Add(Found("hwnd:0000000B", "contoso", @"C:\Tools\contoso.exe", title: "Contoso"));
        var session = new AgentSession(desktop, new NoFrames(), startMenu: new FixedStartMenu(PowerShell));
        var broadcasts = await RunDiscoveryAsync(session, desktop);
        var appId = broadcasts.Single()["appId"]!.GetValue<string>();

        var list = await session.HandleAsync(new JsonObject { ["type"] = "app.list.request", ["requestId"] = "req_apps" });
        var apps = list.DirectReplies[0]["apps"]!.AsArray();
        var running = apps.Single(app => app!["id"]!.GetValue<string>() == appId)!;

        Assert.True(running["running"]!.GetValue<bool>());
        Assert.Equal(@"C:\Tools\contoso.exe", running["exePath"]!.GetValue<string>());
        Assert.All(
            apps.Where(app => app!["id"]!.GetValue<string>() != appId),
            app => Assert.Null(app!["running"])
        );

        var launch = await session.HandleAsync(new JsonObject
        {
            ["type"] = "app.launch.request",
            ["requestId"] = "req_launch",
            ["appId"] = appId
        });

        Assert.Equal("app.launch.response", launch.DirectReplies[0]["type"]!.GetValue<string>());
        Assert.Equal(appId, desktop.Launched.Single().Id);
    }

    [Fact]
    public async Task HealthAdvertisesDesktopWindowsOnlyOnWindows()
    {
        var session = new AgentSession(new DesktopWithWindows(), new NoFrames(), startMenu: new FixedStartMenu());

        var health = await session.HandleAsync(new JsonObject { ["type"] = "agent.health.request", ["requestId"] = "h" });

        Assert.Equal(
            OperatingSystem.IsWindows(),
            health.DirectReplies[0]["capabilities"]!["desktopWindows"]!.GetValue<bool>()
        );
    }
}
