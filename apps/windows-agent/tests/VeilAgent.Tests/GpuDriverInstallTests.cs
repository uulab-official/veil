using System.Text.Json.Nodes;
using Veil.Agent;
using Xunit;

namespace VeilAgent.Tests;

public sealed class GpuDriverInstallTests
{
    private static readonly ToolsUpdateDrive GpuDisc = new(@"H:\", GpuDriverInstall.VolumeLabel);
    private const string Inf = @"H:\viogpu3d\viogpu3d.inf";

    [Fact]
    public async Task AsksForApprovalWithTheFixedScriptAndAnswersAtOnce()
    {
        var launcher = new FakeLauncher();
        var install = Make(launcher, drives: [GpuDisc]);

        var result = install.Start();

        Assert.Equal("approval-requested", result["outcome"]?.GetValue<string>());
        var script = await launcher.Script.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Contains("FileSystemLabel -eq 'VEIL_GPU'", script);
        Assert.Contains("pnputil.exe') /add-driver", script);
        Assert.Contains("Get-AuthenticodeSignature", script);
        foreach (var hash in GpuDriverInstall.PinnedHashes.Values)
        {
            Assert.Contains(hash, script);
        }
        // Nothing from the disc path the agent saw goes into the script; the elevated side finds the disc.
        Assert.DoesNotContain("H:", script);
        Assert.True(install.Status()["installing"]!.GetValue<bool>());
        launcher.Release.SetResult();
    }

    [Fact]
    public void RefusesWithoutTheDiscOrWhenAlreadyInstalled()
    {
        Assert.Equal("media-missing", Make(new FakeLauncher(), drives: []).Start()["outcome"]?.GetValue<string>());
        Assert.Equal("media-missing", Make(new FakeLauncher(), drives: [new ToolsUpdateDrive(@"H:\", "VEIL_TOOLS")]).Start()["outcome"]?.GetValue<string>());
        Assert.Equal("already-installed", Make(new FakeLauncher(), drives: [GpuDisc], installed: true).Start()["outcome"]?.GetValue<string>());
        Assert.Equal("unsupported", Make(new FakeLauncher { IsWindows = false }, drives: [GpuDisc]).Start()["outcome"]?.GetValue<string>());
    }

    [Fact]
    public async Task OnlyOnePromptAtATime()
    {
        var launcher = new FakeLauncher();
        var install = Make(launcher, drives: [GpuDisc]);
        install.Start();
        await launcher.Script.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal("already-running", install.Start()["outcome"]?.GetValue<string>());
        launcher.Release.SetResult();
    }

    [Fact]
    public async Task ReportsADeclinedPrompt()
    {
        var launcher = new FakeLauncher { Approves = false };
        var install = Make(launcher, drives: [GpuDisc]);
        install.Start();
        launcher.Release.SetResult();
        for (var i = 0; i < 50 && install.Status()["lastInstall"] is null; i++)
        {
            await Task.Delay(20);
        }
        Assert.Equal("declined", install.Status()["lastInstall"]?["outcome"]?.GetValue<string>());
    }

    [Fact]
    public void ReadsOnlyTheExpectedFieldsOfTheStatusFile()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".json");
        try
        {
            File.WriteAllText(path, "\uFEFF{\"outcome\":\"installed\",\"exitCode\":0,\"message\":null,\"finishedAt\":\"2026-11-15T09:00:00Z\",\"extra\":{\"x\":1}}");
            var status = Make(new FakeLauncher(), drives: [], installed: true, statusPath: path).Status();
            Assert.True(status["installed"]!.GetValue<bool>());
            var last = status["lastInstall"]!.AsObject();
            Assert.Equal("installed", last["outcome"]?.GetValue<string>());
            Assert.Equal(0, last["exitCode"]?.GetValue<int>());
            Assert.False(last.ContainsKey("extra"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    private static GpuDriverInstall Make(
        FakeLauncher launcher,
        ToolsUpdateDrive[] drives,
        bool installed = false,
        string? statusPath = null) =>
        new(
            launcher,
            opticalDrives: () => drives,
            fileExists: path => path == Inf,
            isInstalled: () => installed,
            statusPath: statusPath ?? Path.Combine(Path.GetTempPath(), "no-such-veil-status.json"));

    private sealed class FakeLauncher : IElevatedLauncher
    {
        public bool IsWindows { get; init; } = true;
        public string? CurrentUserSid => "S-1-5-21-1-2-3-1001";
        public bool Approves { get; init; } = true;
        public TaskCompletionSource<string> Script { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public bool RunElevatedPowerShell(string script)
        {
            Script.TrySetResult(script);
            Release.Task.Wait(TimeSpan.FromSeconds(5));
            return Approves;
        }
    }
}
