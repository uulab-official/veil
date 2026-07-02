# Veil Windows Agent

The Windows agent is the guest-side process for the Veil Windows App Runtime.

Current scope:

- .NET 8 console application.
- WebSocket listener on `127.0.0.1:18444`.
- Protocol handling for health, app list, and Notepad launch.
- Notepad launch emits `app.launch.response`, `window.created`, and the first HWND-captured `window.frame` event through the event broadcast path.

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

## Harness Contract

The repository-level contract harness validates the expected launch transcript without requiring a Windows VM:

```bash
cd harness/windows-agent-contract
npm test
```

The default frame path uses Win32/GDI capture behind `IWindowFrameCapture`. The next capture milestone is to verify the Notepad frame inside Windows 11 Arm and then evaluate Windows Graphics Capture or a lower-latency stream for continuing frames.
