namespace Veil.Agent;

public interface IWindowsDesktop
{
    Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken);

    Task<bool> CloseWindowAsync(string windowId, CancellationToken cancellationToken);

    Task<bool> SendMouseInputAsync(WindowMouseInput input, CancellationToken cancellationToken);

    Task<bool> SendKeyInputAsync(WindowKeyInput input, CancellationToken cancellationToken);
}
