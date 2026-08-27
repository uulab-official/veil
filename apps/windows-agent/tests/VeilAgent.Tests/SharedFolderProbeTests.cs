using Veil.Agent;

namespace VeilAgent.Tests;

public class SharedFolderProbeTests
{
    private sealed class FakeSharedFolderSystem : ISharedFolderSystem
    {
        public bool IsWindows { get; init; } = true;
        public bool IsElevated { get; init; }
        public bool IsServerListening { get; init; } = true;
        public bool DirectoryPresent { get; set; }
        public bool SharePresent { get; set; }
        public bool ShareWritable { get; init; }
        public bool ShareCreationSucceeds { get; init; } = true;
        public string? ShareCreationError { get; init; }
        public bool CreateDirectoryThrows { get; init; }

        public List<string> CreatedDirectories { get; } = [];
        public List<(string ShareName, string DirectoryPath)> CreatedShares { get; } = [];
        public int WriteProbeCount { get; private set; }

        public bool DirectoryExists(string path) => DirectoryPresent;

        public void CreateDirectory(string path)
        {
            if (CreateDirectoryThrows)
            {
                throw new UnauthorizedAccessException("access denied");
            }

            CreatedDirectories.Add(path);
            DirectoryPresent = true;
        }

        public bool ShareExists(string shareName) => SharePresent;

        public bool CanWriteThroughShare(string shareName)
        {
            WriteProbeCount++;
            return ShareWritable;
        }

        public bool TryCreateShare(string shareName, string directoryPath, out string? error)
        {
            if (!ShareCreationSucceeds)
            {
                error = ShareCreationError;
                return false;
            }

            CreatedShares.Add((shareName, directoryPath));
            SharePresent = true;
            error = null;
            return true;
        }
    }

    private const string ShareName = SharedFolderProbe.DefaultShareName;
    private const string GuestPath = SharedFolderProbe.DefaultGuestDirectoryPath;

    [Fact]
    public void ReportsUnsupportedOffWindows()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem
        {
            IsWindows = false,
            IsServerListening = true,
            DirectoryPresent = true,
            SharePresent = true
        });

        var status = probe.ReadStatus(ShareName, GuestPath);

        Assert.False(status["isSupported"]!.GetValue<bool>());
        // An unsupported host must not also claim a working share; the protocol validator rejects that
        // combination because it would let a stub agent look like a real one.
        Assert.False(status["isShared"]!.GetValue<bool>());
        Assert.False(status["serverListening"]!.GetValue<bool>());
        Assert.Equal("unsupported-on-this-host", status["recommendedAction"]!.GetValue<string>());
    }

    [Theory]
    [InlineData("has space")]
    [InlineData("semi;colon")]
    [InlineData("quote'mark")]
    [InlineData("")]
    public void RejectsUnsafeShareNames(string shareName)
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem { DirectoryPresent = true, SharePresent = true });

        var status = probe.ReadStatus(shareName, GuestPath);

        Assert.Equal("invalid-request", status["recommendedAction"]!.GetValue<string>());
        Assert.False(status["isShared"]!.GetValue<bool>());
    }

    [Theory]
    [InlineData(@"VeilShared")]
    [InlineData(@"\VeilShared")]
    [InlineData(@"C:\Veil\..\Windows")]
    [InlineData("C:\\Veil'; rm")]
    public void RejectsUnsafeGuestPaths(string guestPath)
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem { DirectoryPresent = true, SharePresent = true });

        var status = probe.ReadStatus(ShareName, guestPath);

        Assert.Equal("invalid-request", status["recommendedAction"]!.GetValue<string>());
    }

    [Fact]
    public void ReportsFirewallBeforeAnythingElseWhenServerIsUnreachable()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem
        {
            IsServerListening = false,
            DirectoryPresent = true,
            SharePresent = true,
            ShareWritable = true
        });

        var status = probe.ReadStatus(ShareName, GuestPath);

        // A share the Mac cannot reach is indistinguishable from no share at all, so the unreachable
        // server is the first thing reported rather than the last.
        Assert.Equal("enable-smb-firewall", status["recommendedAction"]!.GetValue<string>());
        Assert.False(status["serverListening"]!.GetValue<bool>());
    }

    [Fact]
    public void NeverReportsShareWithoutItsDirectory()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem
        {
            DirectoryPresent = false,
            SharePresent = true,
            ShareWritable = true
        });

        var status = probe.ReadStatus(ShareName, GuestPath);

        Assert.False(status["directoryExists"]!.GetValue<bool>());
        Assert.False(status["isShared"]!.GetValue<bool>());
        Assert.False(status["isWritable"]!.GetValue<bool>());
        Assert.Equal("create-guest-directory", status["recommendedAction"]!.GetValue<string>());
    }

    [Fact]
    public void NeverReportsWritableWithoutShared()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem
        {
            DirectoryPresent = true,
            SharePresent = false,
            ShareWritable = true
        });

        var status = probe.ReadStatus(ShareName, GuestPath);

        Assert.False(status["isWritable"]!.GetValue<bool>());
    }

    [Fact]
    public void DoesNotProbeWritabilityThroughAShareThatDoesNotExist()
    {
        var system = new FakeSharedFolderSystem { DirectoryPresent = true, SharePresent = false };
        var probe = new SharedFolderProbe(system);

        probe.ReadStatus(ShareName, GuestPath);

        // Writing a probe file into a nonexistent share would land in the local filesystem under an
        // unexpected path rather than failing cleanly.
        Assert.Equal(0, system.WriteProbeCount);
    }

    [Fact]
    public void SuppliesTheElevatedCommandWhileTheShareIsMissing()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem { DirectoryPresent = true, SharePresent = false });

        var status = probe.ReadStatus(ShareName, GuestPath);

        Assert.True(status["requiresElevation"]!.GetValue<bool>());
        var command = status["shareCommand"]!.GetValue<string>();
        Assert.Contains("New-SmbShare", command);
        Assert.Contains(ShareName, command);
        Assert.Contains(GuestPath, command);
        Assert.Equal("create-share-elevated", status["recommendedAction"]!.GetValue<string>());
    }

    [Fact]
    public void StopsAskingForElevationOnceTheShareExists()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem
        {
            DirectoryPresent = true,
            SharePresent = true,
            ShareWritable = true
        });

        var status = probe.ReadStatus(ShareName, GuestPath);

        Assert.False(status["requiresElevation"]!.GetValue<bool>());
        Assert.Null(status["shareCommand"]);
        Assert.Equal("mount-on-mac", status["recommendedAction"]!.GetValue<string>());
    }

    [Fact]
    public void DistinguishesAReadOnlyShareFromAMissingOne()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem
        {
            DirectoryPresent = true,
            SharePresent = true,
            ShareWritable = false
        });

        var status = probe.ReadStatus(ShareName, GuestPath);

        Assert.True(status["isShared"]!.GetValue<bool>());
        Assert.False(status["isWritable"]!.GetValue<bool>());
        Assert.Equal("grant-share-write-access", status["recommendedAction"]!.GetValue<string>());
    }

    [Fact]
    public async Task EnsureCreatesTheDirectoryWithoutElevation()
    {
        var system = new FakeSharedFolderSystem { DirectoryPresent = false, IsElevated = false };
        var probe = new SharedFolderProbe(system);

        var status = await probe.EnsureAsync(ShareName, GuestPath, CancellationToken.None);

        Assert.Contains(GuestPath, system.CreatedDirectories);
        Assert.Empty(system.CreatedShares);
        Assert.True(status["directoryExists"]!.GetValue<bool>());
        Assert.False(status["isShared"]!.GetValue<bool>());
        Assert.Contains("administrator", status["message"]!.GetValue<string>());
    }

    [Fact]
    public async Task EnsurePublishesTheShareWhenAlreadyElevated()
    {
        var system = new FakeSharedFolderSystem
        {
            DirectoryPresent = false,
            IsElevated = true,
            ShareWritable = true
        };
        var probe = new SharedFolderProbe(system);

        var status = await probe.EnsureAsync(ShareName, GuestPath, CancellationToken.None);

        Assert.Contains((ShareName, GuestPath), system.CreatedShares);
        Assert.True(status["isShared"]!.GetValue<bool>());
        Assert.True(status["isWritable"]!.GetValue<bool>());
        Assert.Null(status["message"]);
    }

    [Fact]
    public async Task EnsureReportsWhyShareCreationFailed()
    {
        var system = new FakeSharedFolderSystem
        {
            DirectoryPresent = true,
            IsElevated = true,
            ShareCreationSucceeds = false,
            ShareCreationError = "New-SmbShare: name already in use"
        };
        var probe = new SharedFolderProbe(system);

        var status = await probe.EnsureAsync(ShareName, GuestPath, CancellationToken.None);

        Assert.Equal("New-SmbShare: name already in use", status["message"]!.GetValue<string>());
        Assert.False(status["isShared"]!.GetValue<bool>());
    }

    [Fact]
    public async Task EnsureReportsADirectoryItCouldNotCreate()
    {
        var system = new FakeSharedFolderSystem
        {
            DirectoryPresent = false,
            CreateDirectoryThrows = true,
            IsElevated = true
        };
        var probe = new SharedFolderProbe(system);

        var status = await probe.EnsureAsync(ShareName, GuestPath, CancellationToken.None);

        Assert.False(status["directoryExists"]!.GetValue<bool>());
        Assert.Contains("Could not create", status["message"]!.GetValue<string>());
        // Publishing a share over a folder that does not exist would leave a broken share behind.
        Assert.Empty(system.CreatedShares);
    }

    [Fact]
    public async Task EnsureDoesNotActOnAnUnsafeRequest()
    {
        var system = new FakeSharedFolderSystem { DirectoryPresent = false, IsElevated = true };
        var probe = new SharedFolderProbe(system);

        var status = await probe.EnsureAsync("bad name", @"C:\Veil'; rm", CancellationToken.None);

        Assert.Empty(system.CreatedDirectories);
        Assert.Empty(system.CreatedShares);
        Assert.Equal("invalid-request", status["recommendedAction"]!.GetValue<string>());
    }

    [Fact]
    public void ReportsCredentialsAsAStandingRequirement()
    {
        var probe = new SharedFolderProbe(new FakeSharedFolderSystem
        {
            DirectoryPresent = true,
            SharePresent = true,
            ShareWritable = true
        });

        var status = probe.ReadStatus(ShareName, GuestPath);

        // Not a detection of password state. SMB always refuses a blank-password network sign-in, and
        // the mount prompt is where the password is supplied.
        Assert.True(status["requiresCredentials"]!.GetValue<bool>());
    }

    [Fact]
    public void ShareCommandQuotesNothingItCannotControl()
    {
        var command = SharedFolderProbe.ShareCommand(ShareName, GuestPath);

        Assert.DoesNotContain(";", command);
        Assert.DoesNotContain("|", command);
        Assert.DoesNotContain("&", command);
    }
}
