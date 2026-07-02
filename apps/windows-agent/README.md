# Veil Windows Agent

The Windows agent is the guest-side process for the Veil Windows App Runtime.

Current scope:

- .NET 8 console application.
- WebSocket listener on `127.0.0.1:18444`.
- Protocol handling for health, app list, and Notepad launch.
- Notepad launch emits `app.launch.response`, `window.created`, and the first HWND-captured `window.frame` event through the event broadcast path.
- After the first frame, a per-window frame streamer continues broadcasting PNG `window.frame` events until the agent process stops or the window stream is replaced.

This project intentionally does not ship Windows media, licenses, product keys, or proprietary SDKs.

## Local Development

The repository test Mac may not have the .NET SDK installed. When the SDK is available on Windows:

```powershell
dotnet build apps/windows-agent/src/VeilAgent/VeilAgent.csproj
dotnet run --project apps/windows-agent/src/VeilAgent/VeilAgent.csproj
```

The executable listens at:

```text
ws://127.0.0.1:18444/
```

## Install In Windows

After Windows 11 Arm reaches the desktop and the .NET 8 SDK is installed, use the bundle that the macOS host stages in the VM shared folder:

```text
Veil Shared\Veil Guest Agent\Install Veil Agent.cmd
```

For repository development without the shared-folder bundle, run this inside the guest:

```powershell
cd C:\Path\To\veil\apps\windows-agent
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-VeilAgent.ps1
```

The installer publishes the agent to `%LOCALAPPDATA%\Veil\Agent\app`, copies the start/uninstall scripts to `%LOCALAPPDATA%\Veil\Agent\scripts`, sets user-level `VEIL_AGENT_HOST` and `VEIL_AGENT_PORT`, registers a user logon scheduled task named `VeilAgent`, and starts the agent immediately. The logon task points at the installed script copy, so agent auto-start does not depend on the original shared-folder path after installation. Pass `-NoStart` to install without starting the agent in the current session.

Start again without waiting for the next login:

```text
Veil Shared\Veil Guest Agent\Start Veil Agent.cmd
```

Or from a repository checkout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-VeilAgent.ps1
```

Remove the user task and published files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-VeilAgent.ps1
```

## Harness Contract

The repository-level contract harness validates the expected launch transcript without requiring a Windows VM:

```bash
cd harness/windows-agent-contract
npm test
```

The default frame path uses Win32/GDI capture behind `IWindowFrameCapture`. The current stream interval is 250 ms for correctness-first validation. The next capture milestone is to verify the Notepad frame inside Windows 11 Arm and then evaluate Windows Graphics Capture or a lower-latency stream.
