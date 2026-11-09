namespace Veil.Agent;

public interface IWindowsDesktop
{
    Task<LaunchedWindow> LaunchAppAsync(WindowsAppDescriptor app, CancellationToken cancellationToken);

    Task<LaunchedWindow> LaunchAppWithFileAsync(WindowsAppDescriptor app, string filePath, CancellationToken cancellationToken);

    Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken);

    IReadOnlyList<LaunchedWindow> DiscoverAdditionalWindows(WindowsAppDescriptor app, IReadOnlySet<string> knownWindowIds);

    bool IsWindowStillOpen(string windowId);

    Task<bool> FocusWindowAsync(string windowId, CancellationToken cancellationToken);

    Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken);

    /// <summary>
    /// Resizes a tracked HWND using logical dimensions. The Windows implementation converts them to
    /// physical pixels using the window's current per-monitor DPI and returns the bounds actually applied.
    /// </summary>
    Task<WindowRect?> ResizeWindowAsync(WindowResizeInput input, CancellationToken cancellationToken) =>
        Task.FromResult<WindowRect?>(null);

    /// <summary>
    /// Changes the active Windows desktop display mode. Older test doubles and agents can keep the
    /// default refusal, allowing the host to retain its aspect-fit RFB fallback.
    /// </summary>
    Task<DisplayResizeResult?> ResizeDisplayAsync(DisplayResizeInput input, CancellationToken cancellationToken) =>
        Task.FromResult<DisplayResizeResult?>(null);

    Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken);

    /// <summary>
    /// Where the last applied mouse event put the cursor, in the absolute tablet range the host's virtual
    /// pointer uses. Null for desktops that do not inject real input, including test doubles.
    /// </summary>
    GuestPointerPosition? LastInjectedPointer => null;

    Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken);

    /// <summary>
    /// Posts committed Unicode text to a tracked window.
    /// </summary>
    /// <remarks>
    /// Declared with a default implementation so existing desktop test doubles keep compiling. The
    /// default throws rather than returning <c>false</c>: a silent no-op would look like typed Korean
    /// simply vanishing, which is the exact failure class the agent silent-failure audit covered.
    /// </remarks>
    Task<bool> SendTextInputAsync(WindowTextInput input, CancellationToken cancellationToken) =>
        throw new NotSupportedException("This desktop implementation cannot post committed text input.");

    Task SetClipboardTextAsync(string text, CancellationToken cancellationToken);

    Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken);

    bool TryConsumeHostClipboardEcho(string text);

    // The image and file clipboard members below have defaults so existing desktop test doubles keep
    // compiling. Writers throw rather than no-op: an acknowledged write that changed nothing would let the
    // host send Ctrl+V and paste stale content, which is the exact failure operation.ack exists to stop.

    /// <summary>
    /// Windows' clipboard sequence number, which changes on every clipboard write. Zero means unknown, and
    /// the streamer then reads the image on every tick and relies on the hash to skip repeats.
    /// </summary>
    uint GetClipboardSequenceNumber() => 0;

    /// <summary>
    /// The clipboard image as PNG bytes: the registered <c>PNG</c> format when present, otherwise
    /// <c>CF_DIB</c> converted to PNG. Null when the clipboard holds no image.
    /// </summary>
    Task<byte[]?> GetClipboardImagePngAsync(CancellationToken cancellationToken) =>
        Task.FromResult<byte[]?>(null);

    /// <summary>Places a verified host PNG on the clipboard as both <c>PNG</c> and <c>CF_DIB</c>.</summary>
    Task SetClipboardImagePngAsync(byte[] png, string sha256, CancellationToken cancellationToken) =>
        throw new NotSupportedException("This desktop implementation cannot write clipboard images.");

    /// <summary>
    /// True once for the hash of an image this agent just wrote for the host, so the watcher does not
    /// broadcast it back as a guest copy.
    /// </summary>
    bool TryConsumeHostClipboardImageEcho(string sha256) => false;

    /// <summary>Places shared-folder files on the clipboard as <c>CF_HDROP</c> with a copy drop effect.</summary>
    Task SetClipboardFilesAsync(IReadOnlyList<string> fullPaths, CancellationToken cancellationToken) =>
        throw new NotSupportedException("This desktop implementation cannot write clipboard files.");

    /// <summary>
    /// True for an existing regular file that is not a reparse point. A junction or symlink inside the
    /// share could otherwise point a host-named path at any file in the guest.
    /// </summary>
    bool IsRegularSharedFile(string fullPath)
    {
        var info = new FileInfo(fullPath);
        return info.Exists && (info.Attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory)) == 0;
    }
}
