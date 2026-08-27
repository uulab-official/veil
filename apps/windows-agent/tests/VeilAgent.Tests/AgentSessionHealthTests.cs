using System.Text.Json.Nodes;
using Veil.Agent;

namespace VeilAgent.Tests;

public class AgentSessionHealthTests
{
    private sealed class FakePackageIdentityProbe : IPackageIdentityProbe
    {
        public FakePackageIdentityProbe(bool hasPackageIdentity)
        {
            HasPackageIdentity = hasPackageIdentity;
        }

        public bool HasPackageIdentity { get; }
    }

    private sealed class FakeSparsePackageStatusProbe : ISparsePackageStatusProbe
    {
        public JsonObject? Status { get; init; }

        public JsonObject? ReadStatus() => Status;
    }

    private sealed class FakeNotificationAccessProbe : IWindowsNotificationAccessProbe
    {
        public bool WasRequested { get; private set; }
        public bool? RequestPackageIdentityInput { get; private set; }

        public JsonObject Status { get; init; } = new()
        {
            ["isSupported"] = true,
            ["canListen"] = false,
            ["accessStatus"] = "packageIdentityRequired",
            ["recommendedAction"] = "prepare-sparse-package",
            ["requiresPackageIdentity"] = true
        };

        public JsonObject ReadStatus(bool hasPackageIdentity)
        {
            Status["packageIdentityInput"] = hasPackageIdentity;
            return Status;
        }

        public Task<JsonObject> RequestAccessAsync(bool hasPackageIdentity, CancellationToken cancellationToken)
        {
            WasRequested = true;
            RequestPackageIdentityInput = hasPackageIdentity;
            Status["packageIdentityInput"] = hasPackageIdentity;
            return Task.FromResult(Status);
        }
    }

    private sealed class FakeSharedFolderProbe : IWindowsSharedFolderProbe
    {
        public int EnsureCount { get; private set; }
        public int ReadCount { get; private set; }
        public string? LastShareName { get; private set; }
        public string? LastGuestDirectoryPath { get; private set; }
        public bool IsShared { get; init; }

        // A fresh object per call on purpose: a JsonObject can only be attached to one parent, so
        // returning a cached instance would throw the second time health was requested.
        public JsonObject ReadStatus(string shareName, string guestDirectoryPath)
        {
            ReadCount++;
            LastShareName = shareName;
            LastGuestDirectoryPath = guestDirectoryPath;
            return new JsonObject
            {
                ["isSupported"] = true,
                ["shareName"] = shareName,
                ["guestDirectoryPath"] = guestDirectoryPath,
                ["directoryExists"] = true,
                ["isShared"] = IsShared,
                ["isWritable"] = IsShared,
                ["serverListening"] = true,
                ["requiresElevation"] = !IsShared,
                ["requiresCredentials"] = true,
                ["recommendedAction"] = IsShared ? "mount-on-mac" : "create-share-elevated"
            };
        }

        public Task<JsonObject> EnsureAsync(
            string shareName,
            string guestDirectoryPath,
            CancellationToken cancellationToken
        )
        {
            EnsureCount++;
            return Task.FromResult(ReadStatus(shareName, guestDirectoryPath));
        }
    }

    private sealed class NoOpWindowsDesktop : IWindowsDesktop
    {
        public Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds) => [];

        public bool IsWindowStillOpen(string windowId) => false;

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

    private sealed class NoOpFrameCapture : IWindowFrameCapture
    {
        public Task<WindowFrame> CaptureFrameAsync(LaunchedWindow window, int sequence, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task HealthResponseReportsInjectedPackageIdentityState(bool hasPackageIdentity)
    {
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(hasPackageIdentity)
        );

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.AgentHealthResponse, response["type"]!.GetValue<string>());
        Assert.Equal(hasPackageIdentity, response["capabilities"]!["packageIdentity"]!.GetValue<bool>());
    }

    [Fact]
    public async Task HealthResponseIncludesNotificationListenerStatus()
    {
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(true),
            notificationAccessProbe: new FakeNotificationAccessProbe
            {
                Status = new JsonObject
                {
                    ["isSupported"] = true,
                    ["canListen"] = true,
                    ["accessStatus"] = "allowed",
                    ["recommendedAction"] = "run-notification-proof",
                    ["requiresPackageIdentity"] = true
                }
            }
        );

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        var response = Assert.Single(replies.DirectReplies);
        var notificationListener = Assert.IsType<JsonObject>(response["notificationListener"]);
        Assert.True(notificationListener["isSupported"]!.GetValue<bool>());
        Assert.True(notificationListener["canListen"]!.GetValue<bool>());
        Assert.Equal("allowed", notificationListener["accessStatus"]!.GetValue<string>());
        Assert.Equal("run-notification-proof", notificationListener["recommendedAction"]!.GetValue<string>());
        Assert.True(notificationListener["packageIdentityInput"]!.GetValue<bool>());
    }

    [Fact]
    public async Task NotificationListenerRequestReturnsLatestConsentStatus()
    {
        var notificationAccessProbe = new FakeNotificationAccessProbe
        {
            Status = new JsonObject
            {
                ["isSupported"] = true,
                ["canListen"] = false,
                ["accessStatus"] = "unspecified",
                ["recommendedAction"] = "request-notification-listener-consent",
                ["requiresPackageIdentity"] = true
            }
        };
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(true),
            notificationAccessProbe: notificationAccessProbe
        );

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.NotificationListenerRequest,
            ["requestId"] = "req_notification_listener"
        });

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.NotificationListenerResponse, response["type"]!.GetValue<string>());
        Assert.False(response["accepted"]!.GetValue<bool>());
        Assert.True(notificationAccessProbe.WasRequested);
        Assert.True(notificationAccessProbe.RequestPackageIdentityInput);
        var notificationListener = Assert.IsType<JsonObject>(response["notificationListener"]);
        Assert.Equal("unspecified", notificationListener["accessStatus"]!.GetValue<string>());
        Assert.Equal("request-notification-listener-consent", notificationListener["recommendedAction"]!.GetValue<string>());
        Assert.True(notificationListener["packageIdentityInput"]!.GetValue<bool>());
    }

    [Fact]
    public async Task HealthResponseIncludesSparsePackageStatusWhenAvailable()
    {
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(false),
            new FakeSparsePackageStatusProbe
            {
                Status = new JsonObject
                {
                    ["statusPath"] = @"C:\Users\veil\AppData\Local\Veil\Agent\package\sparse-package-status.json",
                    ["stage"] = "packageSigned",
                    ["succeeded"] = false,
                    ["message"] = "SignTool signed the sparse identity package.",
                    ["updatedAt"] = "2026-07-10T05:40:00.0000000+09:00",
                    ["packagePath"] = @"C:\Users\veil\AppData\Local\Veil\Agent\package\VeilAgent.Identity.msix",
                    ["certificatePath"] = @"C:\Users\veil\AppData\Local\Veil\Agent\package\VeilAgent.Identity.cer"
                }
            }
        );

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        var response = Assert.Single(replies.DirectReplies);
        var status = Assert.IsType<JsonObject>(response["packageIdentityStatus"]);
        Assert.Equal("packageSigned", status["stage"]!.GetValue<string>());
        Assert.False(status["succeeded"]!.GetValue<bool>());
        Assert.Equal(
            @"C:\Users\veil\AppData\Local\Veil\Agent\package\sparse-package-status.json",
            status["statusPath"]!.GetValue<string>()
        );
    }

    [Fact]
    public void WindowsPackageIdentityProbeReturnsFalseOutsideWindows()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        Assert.False(new WindowsPackageIdentityProbe().HasPackageIdentity);
    }

    [Fact]
    public async Task HealthResponseAdvertisesAndReportsTheSharedFolder()
    {
        var sharedFolderProbe = new FakeSharedFolderProbe { IsShared = false };
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(true),
            sharedFolderProbe: sharedFolderProbe
        );

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        var response = Assert.Single(replies.DirectReplies);
        Assert.True(response["capabilities"]!["sharedFolder"]!.GetValue<bool>());
        var sharedFolder = Assert.IsType<JsonObject>(response["sharedFolder"]);
        Assert.Equal(SharedFolderProbe.DefaultShareName, sharedFolder["shareName"]!.GetValue<string>());
        Assert.Equal(SharedFolderProbe.DefaultGuestDirectoryPath, sharedFolder["guestDirectoryPath"]!.GetValue<string>());
        Assert.Equal("create-share-elevated", sharedFolder["recommendedAction"]!.GetValue<string>());
    }

    [Fact]
    public async Task HealthNeverPreparesTheShareAsASideEffect()
    {
        var sharedFolderProbe = new FakeSharedFolderProbe();
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(true),
            sharedFolderProbe: sharedFolderProbe
        );

        await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.AgentHealthRequest,
            ["requestId"] = "req_health"
        });

        // Health is polled. Creating folders or publishing shares from it would make a read turn into a
        // write several times a minute.
        Assert.Equal(0, sharedFolderProbe.EnsureCount);
        Assert.Equal(1, sharedFolderProbe.ReadCount);
    }

    [Fact]
    public async Task SharedFolderRequestPreparesTheShareUsingTheHostSuppliedNames()
    {
        var sharedFolderProbe = new FakeSharedFolderProbe { IsShared = true };
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(true),
            sharedFolderProbe: sharedFolderProbe
        );

        var replies = await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.SharedFolderRequest,
            ["requestId"] = "req_shared_folder",
            ["shareName"] = "TeamShare",
            ["guestDirectoryPath"] = @"C:\TeamShare"
        });

        var response = Assert.Single(replies.DirectReplies);
        Assert.Equal(MessageTypes.SharedFolderResponse, response["type"]!.GetValue<string>());
        Assert.Equal("req_shared_folder", response["requestId"]!.GetValue<string>());
        Assert.Equal(1, sharedFolderProbe.EnsureCount);
        // The host names the share so a mismatch between what the Mac mounts and what Windows published
        // cannot pass unnoticed.
        Assert.Equal("TeamShare", sharedFolderProbe.LastShareName);
        Assert.Equal(@"C:\TeamShare", sharedFolderProbe.LastGuestDirectoryPath);
        Assert.Equal("TeamShare", response["sharedFolder"]!["shareName"]!.GetValue<string>());
    }

    [Fact]
    public async Task SharedFolderRequestFallsBackToDefaultsForAnOlderHost()
    {
        var sharedFolderProbe = new FakeSharedFolderProbe();
        var session = new AgentSession(
            new NoOpWindowsDesktop(),
            new NoOpFrameCapture(),
            new FakePackageIdentityProbe(true),
            sharedFolderProbe: sharedFolderProbe
        );

        await session.HandleAsync(new JsonObject
        {
            ["type"] = MessageTypes.SharedFolderRequest,
            ["requestId"] = "req_shared_folder"
        });

        Assert.Equal(SharedFolderProbe.DefaultShareName, sharedFolderProbe.LastShareName);
        Assert.Equal(SharedFolderProbe.DefaultGuestDirectoryPath, sharedFolderProbe.LastGuestDirectoryPath);
    }
}
