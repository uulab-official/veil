using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using Microsoft.Win32;

namespace Veil.Agent;

/// <summary>The three per-user settings Veil turns down; null where Windows did not say.</summary>
public sealed record VisualEffectsState(bool? Transparency, bool? WindowAnimation, bool? ClientAnimation);

/// <summary>
/// The settings and the saved copy of them behind a seam, so every outcome can be tested without changing
/// a real Windows.
/// </summary>
public interface IVisualEffectsStore
{
    bool IsWindows { get; }

    VisualEffectsState Read();

    /// <summary>Writes the values that are not null.</summary>
    void Write(VisualEffectsState state);

    /// <summary>What the user had before Veil turned the effects down, or null when nothing is saved.</summary>
    VisualEffectsState? ReadBackup();

    void WriteBackup(VisualEffectsState state);

    void ClearBackup();

    /// <summary>Tells running programs the transparency setting changed. False if the broadcast failed.</summary>
    bool BroadcastChange();
}

/// <summary>
/// Handles <c>visual.effects.set.request</c>: turns Windows' transparency and animations off, or puts
/// back what the user had.
/// </summary>
/// <remarks>
/// A Veil guest has no graphics acceleration, so the Desktop Window Manager draws every frame on the CPU.
/// The translucent materials of Windows 11 and its window animations are the costly part of that, and
/// Microsoft lists turning visual effects down among the ways to make a slow PC faster
/// (<see href="https://support.microsoft.com/windows/tips-to-improve-pc-performance-in-windows-b3b3ef5b-5953-fb6a-2528-4bbed82fba96"/>).
/// An opening window's fade also shows the desktop behind it for a moment, which a Mac window cropped
/// from the display then shows too.
///
/// What the user had is saved the first time the effects are turned down and restored from there, so
/// turning them down twice does not save the turned-down values over the user's own.
/// </remarks>
public sealed class GuestVisualEffects
{
    private static readonly VisualEffectsState Reduced = new(false, false, false);
    private readonly IVisualEffectsStore store;

    public GuestVisualEffects(IVisualEffectsStore? store = null)
    {
        this.store = store ?? new WindowsVisualEffectsStore();
    }

    public JsonObject Apply(bool reduced)
    {
        if (!store.IsWindows)
        {
            return Status(false, reduced, new VisualEffectsState(null, null, null), changed: false, "This agent is not running on Windows.");
        }

        var before = store.Read();
        if (reduced)
        {
            if (store.ReadBackup() is null)
            {
                store.WriteBackup(before);
            }
            // Each write announces a settings change to every window, so none is made for nothing.
            if (before != Reduced)
            {
                store.Write(Reduced);
            }
        }
        else if (store.ReadBackup() is { } saved)
        {
            // A value Windows did not have set was at its default, which is on for all three.
            store.Write(new VisualEffectsState(
                saved.Transparency ?? true, saved.WindowAnimation ?? true, saved.ClientAnimation ?? true));
            store.ClearBackup();
        }

        var after = store.Read();
        var changed = after != before;
        string? message = null;
        if (changed && after.Transparency != before.Transparency && !store.BroadcastChange())
        {
            message = "The transparency setting was written, but the WM_SETTINGCHANGE broadcast failed; running apps may repaint late.";
        }

        return Status(true, reduced, after, changed, message);
    }

    private static JsonObject Status(bool isSupported, bool reduced, VisualEffectsState state, bool changed, string? message) => new()
    {
        ["isSupported"] = isSupported,
        ["reduced"] = reduced,
        ["transparency"] = state.Transparency,
        ["windowAnimation"] = state.WindowAnimation,
        ["clientAnimation"] = state.ClientAnimation,
        ["changed"] = changed,
        ["message"] = message
    };
}

/// <summary>
/// The real settings. Animations are read and set with <c>SystemParametersInfo</c>
/// (<see href="https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-systemparametersinfow"/>):
/// <c>SPI_SETANIMATION</c> for minimizing and maximizing, <c>SPI_SETCLIENTAREAANIMATION</c> for the rest.
/// Transparency is the <c>EnableTransparency</c> value the Settings app's "Transparency effects" switch
/// writes; Microsoft documents the switch, not the value.
/// </summary>
public sealed class WindowsVisualEffectsStore : IVisualEffectsStore
{
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private const string BackupKey = @"Software\UULab\Veil\VisualEffectsBackup";
    private const string TransparencyValue = "EnableTransparency";

    public bool IsWindows => OperatingSystem.IsWindows();

    public VisualEffectsState Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return new VisualEffectsState(null, null, null);
        }

        using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
        bool? windowAnimation = null;
        var info = new AnimationInfo { Size = (uint)Marshal.SizeOf<AnimationInfo>() };
        if (SystemParametersInfo(SPI_GETANIMATION, info.Size, ref info, 0))
        {
            windowAnimation = info.MinAnimate != 0;
        }

        bool? clientAnimation = null;
        if (SystemParametersInfo(SPI_GETCLIENTAREAANIMATION, 0, out int client, 0))
        {
            clientAnimation = client != 0;
        }

        return new VisualEffectsState(ReadFlag(key, TransparencyValue), windowAnimation, clientAnimation);
    }

    public void Write(VisualEffectsState state)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException();
        }

        if (state.Transparency is { } transparency)
        {
            using var key = Registry.CurrentUser.CreateSubKey(PersonalizeKey, writable: true);
            key.SetValue(TransparencyValue, transparency ? 1 : 0, RegistryValueKind.DWord);
        }

        if (state.WindowAnimation is { } windowAnimation)
        {
            var info = new AnimationInfo { Size = (uint)Marshal.SizeOf<AnimationInfo>(), MinAnimate = windowAnimation ? 1 : 0 };
            _ = SystemParametersInfo(SPI_SETANIMATION, info.Size, ref info, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
        }

        if (state.ClientAnimation is { } clientAnimation)
        {
            // For this action the value itself travels in the pointer parameter.
            _ = SystemParametersInfo(
                SPI_SETCLIENTAREAANIMATION, 0, clientAnimation ? 1 : 0, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
        }
    }

    public VisualEffectsState? ReadBackup()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        using var key = Registry.CurrentUser.OpenSubKey(BackupKey);
        return key is null
            ? null
            : new VisualEffectsState(
                ReadFlag(key, nameof(VisualEffectsState.Transparency)),
                ReadFlag(key, nameof(VisualEffectsState.WindowAnimation)),
                ReadFlag(key, nameof(VisualEffectsState.ClientAnimation)));
    }

    public void WriteBackup(VisualEffectsState state)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException();
        }

        using var key = Registry.CurrentUser.CreateSubKey(BackupKey, writable: true);
        WriteFlag(key, nameof(VisualEffectsState.Transparency), state.Transparency);
        WriteFlag(key, nameof(VisualEffectsState.WindowAnimation), state.WindowAnimation);
        WriteFlag(key, nameof(VisualEffectsState.ClientAnimation), state.ClientAnimation);
    }

    public void ClearBackup()
    {
        if (OperatingSystem.IsWindows())
        {
            Registry.CurrentUser.DeleteSubKeyTree(BackupKey, throwOnMissingSubKey: false);
        }
    }

    public bool BroadcastChange()
    {
        // SMTO_ABORTIFHUNG plus a timeout so one hung top-level window cannot stall the agent.
        var result = SendMessageTimeout(
            new IntPtr(0xFFFF), WM_SETTINGCHANGE, IntPtr.Zero, "ImmersiveColorSet", SMTO_ABORTIFHUNG, 1000, out _);
        return result != IntPtr.Zero;
    }

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static bool? ReadFlag(RegistryKey? key, string name) =>
        key?.GetValue(name) is int value ? value != 0 : null;

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static void WriteFlag(RegistryKey key, string name, bool? value)
    {
        if (value is { } flag)
        {
            key.SetValue(name, flag ? 1 : 0, RegistryValueKind.DWord);
        }
    }

    private const uint SPI_GETANIMATION = 0x0048;
    private const uint SPI_SETANIMATION = 0x0049;
    private const uint SPI_GETCLIENTAREAANIMATION = 0x1042;
    private const uint SPI_SETCLIENTAREAANIMATION = 0x1043;
    private const uint SPIF_UPDATEINIFILE = 0x01;
    private const uint SPIF_SENDCHANGE = 0x02;
    private const uint WM_SETTINGCHANGE = 0x001A;
    private const uint SMTO_ABORTIFHUNG = 0x0002;

    [StructLayout(LayoutKind.Sequential)]
    private struct AnimationInfo
    {
        public uint Size;
        public int MinAnimate;
    }

    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint parameter, ref AnimationInfo info, uint flags);

    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint parameter, out int value, uint flags);

    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint parameter, nint value, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint message, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);
}
