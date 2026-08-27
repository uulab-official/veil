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

    Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken);

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
}
