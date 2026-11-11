using Veil.Agent;

namespace VeilAgent.Tests;

public sealed class HostFolderMountTests
{
    private const string Token = "6f1d0c9a2b7e4f30a8d5c1e9b2f47a60";

    private sealed class FakeMapper : IDriveMapper
    {
        public Dictionary<string, string> Mappings { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> LocalVolumes { get; } = new(StringComparer.OrdinalIgnoreCase);
        public List<(string Unc, string Label)> Labels { get; } = [];
        public string? MapError { get; init; }

        public string? RemoteNameOf(string drive) => Mappings.TryGetValue(drive, out var remote) ? remote : null;
        public bool IsLocalVolume(string drive) => LocalVolumes.Contains(drive);
        public string? Map(string drive, string uncPath)
        {
            if (MapError is not null) return MapError;
            Mappings[drive] = uncPath;
            return null;
        }
        public string? Unmap(string drive) { Mappings.Remove(drive); return null; }
        public void SetLabel(string uncPath, string label) => Labels.Add((uncPath, label));
    }

    [Fact]
    public void MapsTheWebDavPathAndNamesIt()
    {
        var mapper = new FakeMapper();
        var result = new HostFolderMount(mapper).Mount(50123, Token, "M", "Mac");

        Assert.True(result.IsMounted);
        Assert.Equal($@"\\10.0.2.2@50123\{Token}", mapper.Mappings["M:"]);
        Assert.Equal(("\\\\10.0.2.2@50123\\" + Token, "Mac"), Assert.Single(mapper.Labels));
    }

    [Fact]
    public void ReplacesAnOlderVeilMappingButNotSomeoneElses()
    {
        var mapper = new FakeMapper();
        mapper.Mappings["M:"] = @"\\10.0.2.2@40000\oldtokenoldtokenold";
        Assert.True(new HostFolderMount(mapper).Mount(50123, Token, "M", "Mac").IsMounted);
        Assert.EndsWith(Token, mapper.Mappings["M:"]);

        mapper.Mappings["N:"] = @"\\fileserver\share";
        var refused = new HostFolderMount(mapper).Mount(50123, Token, "N", "Mac");
        Assert.False(refused.IsMounted);
        Assert.Equal(@"\\fileserver\share", mapper.Mappings["N:"]);
    }

    [Fact]
    public void RefusesALocalDriveAndReportsAMapFailure()
    {
        var mapper = new FakeMapper();
        mapper.LocalVolumes.Add("D:");
        Assert.False(new HostFolderMount(mapper).Mount(50123, Token, "D", "Mac").IsMounted);

        var failing = new HostFolderMount(new FakeMapper { MapError = "error 67" }).Mount(50123, Token, "M", "Mac");
        Assert.False(failing.IsMounted);
        Assert.Equal("error 67", failing.Message);
    }

    [Fact]
    public void UnmountsOnlyVeilMappings()
    {
        var mapper = new FakeMapper();
        mapper.Mappings["M:"] = $@"\\10.0.2.2@50123\{Token}";
        mapper.Mappings["N:"] = @"\\fileserver\share";
        var mount = new HostFolderMount(mapper);

        Assert.False(mount.Unmount("M").IsMounted);
        Assert.True(mount.Unmount("N").IsMounted);
        Assert.True(mapper.Mappings.ContainsKey("N:"));
    }

    [Theory]
    [InlineData("a&calc", false)]
    [InlineData("short", false)]
    [InlineData(Token, true)]
    public void AcceptsOnlyCommandSafeTokens(string token, bool valid) =>
        Assert.Equal(valid, HostFolderMount.IsValidToken(token));

    [Theory]
    [InlineData("C", false)]
    [InlineData("M", true)]
    [InlineData("MM", false)]
    public void AcceptsDriveLettersDThroughZ(string letter, bool valid) =>
        Assert.Equal(valid, HostFolderMount.IsValidDriveLetter(letter));
}
