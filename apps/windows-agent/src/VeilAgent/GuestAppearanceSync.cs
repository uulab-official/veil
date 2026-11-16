using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using Microsoft.Win32;

namespace Veil.Agent;

/// <summary>
/// The per-user theme values behind a seam, so the reported state can be tested without touching
/// a real registry.
/// </summary>
public interface IWindowsThemeStore
{
    bool IsWindows { get; }

    /// <summary>Reads <c>AppsUseLightTheme</c> and <c>SystemUsesLightTheme</c>; null when absent.</summary>
    (bool? AppsUseLightTheme, bool? SystemUsesLightTheme) Read();

    void Write(bool useLightTheme);

    /// <summary>Broadcasts <c>WM_SETTINGCHANGE</c> "ImmersiveColorSet". False if the broadcast failed.</summary>
    bool BroadcastThemeChange();
}

/// <summary>
/// Handles <c>appearance.set.request</c>, making Windows follow the Mac's light/dark appearance.
/// </summary>
public sealed class GuestAppearanceSync
{
    private readonly IWindowsThemeStore store;

    public GuestAppearanceSync(IWindowsThemeStore? store = null)
    {
        this.store = store ?? new WindowsRegistryThemeStore();
    }

    /// <summary>Returns the appearance status, or null when <paramref name="theme"/> is not light/dark.</summary>
    public JsonObject? Apply(string? theme)
    {
        if (theme is not ("light" or "dark"))
        {
            return null;
        }

        var light = theme == "light";
        if (!store.IsWindows)
        {
            return Status(false, theme, light, light, changed: false, broadcast: false, "This agent is not running on Windows.");
        }

        var before = store.Read();
        var changed = before.AppsUseLightTheme != light || before.SystemUsesLightTheme != light;
        var broadcast = false;
        if (changed)
        {
            store.Write(light);
            // Only announce a change that happened: the broadcast makes every listening window repaint.
            broadcast = store.BroadcastThemeChange();
        }

        // Report what is actually in the registry, not what was intended.
        var after = store.Read();
        var apps = after.AppsUseLightTheme ?? !light;
        var system = after.SystemUsesLightTheme ?? !light;
        if (apps != light || system != light)
        {
            throw new InvalidOperationException(
                $"Theme values did not take effect (AppsUseLightTheme={apps}, SystemUsesLightTheme={system})."
            );
        }

        return Status(
            true,
            theme,
            apps,
            system,
            changed,
            broadcast,
            changed && !broadcast ? "Theme values were written, but the WM_SETTINGCHANGE broadcast failed; running apps may repaint late." : null
        );
    }

    private static JsonObject Status(
        bool isSupported,
        string theme,
        bool appsUseLightTheme,
        bool systemUsesLightTheme,
        bool changed,
        bool broadcast,
        string? message
    ) => new()
    {
        ["isSupported"] = isSupported,
        ["theme"] = theme,
        ["appsUseLightTheme"] = appsUseLightTheme,
        ["systemUsesLightTheme"] = systemUsesLightTheme,
        ["changed"] = changed,
        ["broadcast"] = broadcast,
        ["message"] = message
    };
}

public sealed class WindowsRegistryThemeStore : IWindowsThemeStore
{
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private static readonly IntPtr HwndBroadcast = new(0xFFFF);
    private const uint WmSettingChange = 0x001A;
    private const uint SmtoAbortIfHung = 0x0002;

    public bool IsWindows => OperatingSystem.IsWindows();

    public (bool? AppsUseLightTheme, bool? SystemUsesLightTheme) Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return (null, null);
        }

        using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
        return (ReadFlag(key, "AppsUseLightTheme"), ReadFlag(key, "SystemUsesLightTheme"));
    }

    public void Write(bool useLightTheme)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException();
        }

        using var key = Registry.CurrentUser.CreateSubKey(PersonalizeKey, writable: true);
        var value = useLightTheme ? 1 : 0;
        key.SetValue("AppsUseLightTheme", value, RegistryValueKind.DWord);
        key.SetValue("SystemUsesLightTheme", value, RegistryValueKind.DWord);
    }

    public bool BroadcastThemeChange()
    {
        // SMTO_ABORTIFHUNG plus a timeout so one hung top-level window cannot stall the agent.
        var result = SendMessageTimeout(
            HwndBroadcast,
            WmSettingChange,
            IntPtr.Zero,
            "ImmersiveColorSet",
            SmtoAbortIfHung,
            5000,
            out _
        );
        return result != IntPtr.Zero;
    }

    private static bool? ReadFlag(RegistryKey? key, string name)
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }

        return key?.GetValue(name) is int value ? value != 0 : null;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint msg,
        IntPtr wParam,
        string lParam,
        uint flags,
        uint timeout,
        out IntPtr result
    );
}
