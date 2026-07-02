namespace Veil.Agent;

public interface IWindowsDesktop
{
    Task<LaunchedWindow> LaunchNotepadAsync(CancellationToken cancellationToken);
}
