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

    Task SetClipboardTextAsync(string text, CancellationToken cancellationToken);

    Task<string?> GetClipboardTextAsync(CancellationToken cancellationToken);

    bool TryConsumeHostClipboardEcho(string text);
}
