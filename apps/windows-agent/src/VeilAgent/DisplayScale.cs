using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>What <c>display.scale.request</c> asks for: a scale step, or the user's own scale back.</summary>
public sealed record DisplayScaleInput(int? ScalePercent, bool RestoresUserScale);

/// <summary>The outcome of a scale request. <see cref="ScalePercent"/> is what Windows reports afterwards.</summary>
public sealed record DisplayScaleResult(bool Accepted, int? ScalePercent, string? Reason)
{
    public const string Unavailable = "display_scale_unavailable";
    public const string Refused = "display_scale_refused";
}

/// <summary>
/// The primary display's scale as Windows reports it: steps relative to the recommended one, so 0 is the
/// recommended step and <see cref="MinRelative"/> is 100%.
/// </summary>
public sealed record DisplayScaleState(int MinRelative, int CurrentRelative, int MaxRelative);

/// <summary>Reads and sets the primary display's scale. See <see cref="WindowsDisplayScaleBackend"/>.</summary>
public interface IDisplayScaleBackend
{
    DisplayScaleState? Read();

    bool Write(int relative);
}

/// <summary>Where the agent keeps the scale the user had before Veil changed it.</summary>
public interface IUserDisplayScaleRecord
{
    int? Load();

    void Save(int scalePercent);

    void Clear();
}

/// <summary>Windows' display scale steps, from Settings > System > Display > Scale.</summary>
public static class DisplayScaleSteps
{
    public static readonly IReadOnlyList<int> Percents = [100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500];

    public static bool IsStep(int percent) => Percents.Contains(percent);

    /// <summary>The percent for a relative step, or null when the step is outside the table.</summary>
    public static int? PercentFor(int relative, int minRelative)
    {
        var index = relative - minRelative;
        return index >= 0 && index < Percents.Count ? Percents[index] : null;
    }

    /// <summary>
    /// The relative step for a percent, lowered to <paramref name="maxRelative"/> when Windows does not
    /// offer it on this display. Null for a percent that is not a step.
    /// </summary>
    public static int? RelativeFor(int percent, int minRelative, int maxRelative)
    {
        var index = IndexOf(percent);
        if (index < 0)
        {
            return null;
        }

        return Math.Max(minRelative, Math.Min(minRelative + index, maxRelative));
    }

    private static int IndexOf(int percent)
    {
        for (var index = 0; index < Percents.Count; index++)
        {
            if (Percents[index] == percent)
            {
                return index;
            }
        }

        return -1;
    }
}

/// <summary>
/// Applies <c>display.scale.request</c>: records the user's scale before the first change, sets a step,
/// and gives the recorded scale back. Every answer is read back from Windows, not assumed.
/// </summary>
public sealed class DisplayScaleManager
{
    private readonly IDisplayScaleBackend backend;
    private readonly IUserDisplayScaleRecord record;
    private readonly object gate = new();

    public DisplayScaleManager(IDisplayScaleBackend backend, IUserDisplayScaleRecord record)
    {
        this.backend = backend;
        this.record = record;
    }

    public DisplayScaleResult Apply(DisplayScaleInput input)
    {
        lock (gate)
        {
            var state = backend.Read();
            var current = state is null ? null : DisplayScaleSteps.PercentFor(state.CurrentRelative, state.MinRelative);
            if (state is null || current is null)
            {
                return new DisplayScaleResult(false, null, DisplayScaleResult.Unavailable);
            }

            int target;
            if (input.RestoresUserScale)
            {
                if (record.Load() is not { } userPercent)
                {
                    return new DisplayScaleResult(true, current, null);
                }

                target = userPercent;
            }
            else if (input.ScalePercent is { } percent)
            {
                // Only the first change is the user's own scale; later ones are Veil's.
                if (record.Load() is null)
                {
                    record.Save(current.Value);
                }

                target = percent;
            }
            else
            {
                return new DisplayScaleResult(false, current, DisplayScaleResult.Refused);
            }

            var relative = DisplayScaleSteps.RelativeFor(target, state.MinRelative, state.MaxRelative);
            if (relative is null)
            {
                return new DisplayScaleResult(false, current, DisplayScaleResult.Refused);
            }

            if (relative != state.CurrentRelative && !backend.Write(relative.Value))
            {
                return new DisplayScaleResult(false, current, DisplayScaleResult.Refused);
            }

            var after = backend.Read();
            var applied = after is null ? null : DisplayScaleSteps.PercentFor(after.CurrentRelative, after.MinRelative);
            if (input.RestoresUserScale && applied == target)
            {
                record.Clear();
            }

            return new DisplayScaleResult(true, applied ?? current, null);
        }
    }
}

/// <summary><c>%LOCALAPPDATA%\Veil\Agent\display-scale.json</c>, so a restart does not forget the user's scale.</summary>
public sealed class UserDisplayScaleFile : IUserDisplayScaleRecord
{
    private readonly string path;

    public UserDisplayScaleFile(string? path = null)
    {
        this.path = path ?? System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Veil",
            "Agent",
            "display-scale.json"
        );
    }

    public int? Load()
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }

            using var document = JsonDocument.Parse(File.ReadAllText(path));
            return document.RootElement.TryGetProperty("userScalePercent", out var value)
                && value.TryGetInt32(out var percent)
                && DisplayScaleSteps.IsStep(percent)
                    ? percent
                    : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }

    public void Save(int scalePercent)
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
            File.WriteAllText(path, new JsonObject { ["userScalePercent"] = scalePercent }.ToJsonString());
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"DisplayScale: could not record the user's scale: {error.Message}");
        }
    }

    public void Clear()
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"DisplayScale: could not clear the recorded scale: {error.Message}");
        }
    }
}

/// <summary>
/// The primary display's scale through <c>DisplayConfigGetDeviceInfo</c> and <c>DisplayConfigSetDeviceInfo</c>
/// (https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-displayconfigsetdeviceinfo).
/// The two functions are documented; the device info types used here (-3 get, -4 set) are not part of
/// <c>DISPLAYCONFIG_DEVICE_INFO_TYPE</c>. Windows has no documented way to set the display scale, which is
/// why <see cref="DisplayScaleManager"/> reads every change back and the host checks the answer.
/// </summary>
public sealed class WindowsDisplayScaleBackend : IDisplayScaleBackend
{
    private const int DeviceInfoGetDpiScale = -3;
    private const int DeviceInfoSetDpiScale = -4;
    private const uint QdcOnlyActivePaths = 0x2;
    private const uint InvalidModeIndex = 0xFFFFFFFF;
    private const int ModeInfoTypeSource = 1;

    public DisplayScaleState? Read()
    {
        if (!OperatingSystem.IsWindows() || PrimarySource() is not { } source)
        {
            return null;
        }

        var request = new DpiScaleGet
        {
            Header = new DeviceInfoHeader
            {
                Type = DeviceInfoGetDpiScale,
                Size = (uint)Marshal.SizeOf<DpiScaleGet>(),
                AdapterId = source.AdapterId,
                Id = source.Id
            }
        };
        if (DisplayConfigGetDeviceInfo(ref request) != 0 || request.MinScaleRelative > 0 || request.MaxScaleRelative < request.MinScaleRelative)
        {
            return null;
        }

        return new DisplayScaleState(request.MinScaleRelative, request.CurrentScaleRelative, request.MaxScaleRelative);
    }

    public bool Write(int relative)
    {
        if (!OperatingSystem.IsWindows() || PrimarySource() is not { } source)
        {
            return false;
        }

        var request = new DpiScaleSet
        {
            Header = new DeviceInfoHeader
            {
                Type = DeviceInfoSetDpiScale,
                Size = (uint)Marshal.SizeOf<DpiScaleSet>(),
                AdapterId = source.AdapterId,
                Id = source.Id
            },
            ScaleRelative = relative
        };
        return DisplayConfigSetDeviceInfo(ref request) == 0;
    }

    /// <summary>The active source whose desktop starts at (0, 0), which is the primary display.</summary>
    private static PathSourceInfo? PrimarySource()
    {
        if (GetDisplayConfigBufferSizes(QdcOnlyActivePaths, out var pathCount, out var modeCount) != 0 || pathCount == 0)
        {
            return null;
        }

        var paths = new PathInfo[pathCount];
        var modes = new ModeInfo[modeCount];
        if (QueryDisplayConfig(QdcOnlyActivePaths, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero) != 0 || pathCount == 0)
        {
            return null;
        }

        for (var index = 0; index < pathCount; index++)
        {
            var modeIndex = paths[index].SourceInfo.ModeInfoIndex;
            if (modeIndex != InvalidModeIndex
                && modeIndex < modeCount
                && modes[modeIndex].InfoType == ModeInfoTypeSource
                && modes[modeIndex].PositionX == 0
                && modes[modeIndex].PositionY == 0)
            {
                return paths[index].SourceInfo;
            }
        }

        return paths[0].SourceInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathSourceInfo
    {
        public Luid AdapterId;
        public uint Id;
        public uint ModeInfoIndex;
        public uint StatusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathTargetInfo
    {
        public Luid AdapterId;
        public uint Id;
        public uint ModeInfoIndex;
        public int OutputTechnology;
        public int Rotation;
        public int Scaling;
        public uint RefreshRateNumerator;
        public uint RefreshRateDenominator;
        public int ScanLineOrdering;
        public int TargetAvailable;
        public uint StatusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathInfo
    {
        public PathSourceInfo SourceInfo;
        public PathTargetInfo TargetInfo;
        public uint Flags;
    }

    /// <summary><c>DISPLAYCONFIG_MODE_INFO</c>, with the union read as a source mode.</summary>
    [StructLayout(LayoutKind.Explicit, Size = 64)]
    private struct ModeInfo
    {
        [FieldOffset(0)] public int InfoType;
        [FieldOffset(4)] public uint Id;
        [FieldOffset(8)] public Luid AdapterId;
        [FieldOffset(16)] public uint Width;
        [FieldOffset(20)] public uint Height;
        [FieldOffset(24)] public int PixelFormat;
        [FieldOffset(28)] public int PositionX;
        [FieldOffset(32)] public int PositionY;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DeviceInfoHeader
    {
        public int Type;
        public uint Size;
        public Luid AdapterId;
        public uint Id;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DpiScaleGet
    {
        public DeviceInfoHeader Header;
        public int MinScaleRelative;
        public int CurrentScaleRelative;
        public int MaxScaleRelative;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DpiScaleSet
    {
        public DeviceInfoHeader Header;
        public int ScaleRelative;
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(
        uint flags,
        ref uint pathCount,
        [Out] PathInfo[] paths,
        ref uint modeCount,
        [Out] ModeInfo[] modes,
        IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigGetDeviceInfo(ref DpiScaleGet request);

    [DllImport("user32.dll")]
    private static extern int DisplayConfigSetDeviceInfo(ref DpiScaleSet request);
}
