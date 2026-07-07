using Veil.Agent;

namespace VeilAgent.Tests;

public class WindowsAppIconExtractorTests
{
    [Fact]
    public void ExtractsANonEmptyPngForNotepad()
    {
        if (!OperatingSystem.IsWindows())
        {
            // Icon.ExtractAssociatedIcon/Bitmap are Windows-only; WindowsAppIconExtractor guards on
            // OperatingSystem.IsWindows() and returns null on other platforms rather than throwing,
            // which is covered by ReturnsNullGracefullyOnNonWindowsOrUnresolvablePaths below. Real
            // icon extraction can only be verified on Windows, where notepad.exe is always present.
            return;
        }

        var base64Png = WindowsAppIconExtractor.ExtractIconPngBase64("winapp_notepad_test", ["notepad.exe"]);

        Assert.NotNull(base64Png);
        var bytes = Convert.FromBase64String(base64Png!);
        Assert.NotEmpty(bytes);
        // PNG file signature: 137 80 78 71 13 10 26 10
        Assert.Equal(0x89, bytes[0]);
        Assert.Equal((byte)'P', bytes[1]);
        Assert.Equal((byte)'N', bytes[2]);
        Assert.Equal((byte)'G', bytes[3]);
    }

    [Fact]
    public void FallsBackToAnAlternateExecutableWhenThePrimaryOneDoesNotResolve()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        // Mirrors AgentSession's call shape for packaged apps like Calculator, whose primary
        // Executable is a launcher stub and whose real window-owning process is only known via
        // AlternateExecutables. The primary candidate here is nonsense so this only passes if the
        // extractor actually falls through to the alternate.
        var base64Png = WindowsAppIconExtractor.ExtractIconPngBase64(
            "winapp_alternate_fallback_test",
            ["definitely-not-a-real-executable.exe", "notepad.exe"]
        );

        Assert.NotNull(base64Png);
        Assert.NotEmpty(Convert.FromBase64String(base64Png!));
    }

    [Fact]
    public void ExtractsAnIconForAnExecutableOnlyFoundViaPath()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        // Some inbox apps (e.g. mspaint.exe on recent Windows 11 builds) have no System32 entry --
        // only an execution-alias stub under "%LOCALAPPDATA%\Microsoft\WindowsApps", which is on
        // PATH but not in System32 or the working directory. Reproduce that shape deterministically
        // by copying a real exe under a unique name into a temp directory added to PATH, rather than
        // depending on mspaint.exe actually being installed on the test machine.
        var tempDirectory = Directory.CreateTempSubdirectory("veil-icon-path-test");
        try
        {
            var systemExePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "notepad.exe"
            );
            var aliasExeName = "veil-icon-path-alias-test.exe";
            var aliasExePath = Path.Combine(tempDirectory.FullName, aliasExeName);
            File.Copy(systemExePath, aliasExePath);

            var originalPath = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            Environment.SetEnvironmentVariable(
                "PATH",
                tempDirectory.FullName + Path.PathSeparator + originalPath
            );
            try
            {
                var base64Png = WindowsAppIconExtractor.ExtractIconPngBase64(
                    "winapp_path_alias_test",
                    [aliasExeName]
                );

                Assert.NotNull(base64Png);
                Assert.NotEmpty(Convert.FromBase64String(base64Png!));
            }
            finally
            {
                Environment.SetEnvironmentVariable("PATH", originalPath);
            }
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
    }

    [Fact]
    public void ReturnsNullGracefullyOnNonWindowsOrUnresolvablePaths()
    {
        // On non-Windows this exercises the OperatingSystem.IsWindows() guard; on Windows this
        // exercises the "could not resolve a real path" fallback when no candidate resolves.
        // Either way, this must never throw.
        var result = WindowsAppIconExtractor.ExtractIconPngBase64(
            "winapp_unresolvable_test",
            ["definitely-not-a-real-executable.exe"]
        );

        Assert.Null(result);
    }

    [Fact]
    public void CachesTheResultAcrossCalls()
    {
        // Not directly observable from the public API, but calling twice must not throw or degrade
        // -- this is the code path that would surface a caching bug (e.g. caching by reference
        // instead of value, or a race on the shared dictionary).
        var first = WindowsAppIconExtractor.ExtractIconPngBase64("winapp_cache_test", ["notepad.exe"]);
        var second = WindowsAppIconExtractor.ExtractIconPngBase64("winapp_cache_test", ["notepad.exe"]);

        Assert.Equal(first, second);
    }
}
