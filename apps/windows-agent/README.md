# Veil Windows Agent

The Windows agent is the guest-side process for the Veil Windows App Runtime.

Current scope:

- .NET 8 console application.
- WebSocket listener on `0.0.0.0:18444` inside Windows so QEMU host forwarding can expose it to macOS as `ws://127.0.0.1:18444/`.
- Protocol handling for health, app list, and selected Windows app launch.
- The first app catalog includes Notepad, Calculator, and Paint as Windows inbox app targets.
- App launch emits `app.launch.response`, `window.created`, and the first HWND-captured `window.frame` event through the event broadcast path.
- After the first frame, a per-window frame streamer continues broadcasting PNG `window.frame` events until the agent process stops or the window stream is replaced.
- HWND discovery is localization-tolerant: before launching an app the agent snapshots matching existing process windows, then prefers newly created windows matching the launched process id, executable process name, or title. This avoids depending on English window titles for Windows 11 Arm images.
- HWND discovery also tolerates packaged (MSIX/UWP) apps whose launcher process differs from the process that owns the eventual top-level window, and whose cold-activation time can exceed a native Win32 app's discovery budget. `WindowsAppDescriptor.AlternateExecutables` and `WindowDiscoveryTimeoutOverride` cover this; Windows 11's Calculator (`calc.exe` launches `CalculatorApp.exe`) is configured this way in `AgentSession.cs`.

This project intentionally does not ship Windows media, licenses, product keys, or proprietary SDKs.

## Local Development

The repository test Mac may not have the .NET SDK installed. When the SDK is available on Windows:

```powershell
dotnet build apps/windows-agent/src/VeilAgent/VeilAgent.csproj
dotnet run --project apps/windows-agent/src/VeilAgent/VeilAgent.csproj
```

By default the executable listens inside the Windows guest at:

```text
ws://0.0.0.0:18444/
```

The macOS host still connects to `ws://127.0.0.1:18444/`; QEMU maps that loopback endpoint to the guest listener with `hostfwd=tcp::18444-:18444`.

The agent also takes a named mutex per configured port, so duplicate launches
for the same forwarded WebSocket endpoint exit instead of racing for the
listener.

## Install In Windows

After Windows 11 Arm reaches the desktop, use the bundle that the macOS host stages on the `VEIL_AUTO` media or in the VM shared folder:

```text
Veil Shared\Veil Guest Agent\Install Veil Agent.cmd
```

For the smoothest first-run path, publish a win-arm64 app bundle before building the install media.
On macOS or Linux:

```bash
apps/windows-agent/scripts/publish-veil-agent-bundle.sh
```

On Windows or PowerShell:

```powershell
apps\windows-agent\scripts\Publish-VeilAgentBundle.ps1
```

That creates `apps\windows-agent\app\VeilAgent.exe` and its runtime payload. The installer prefers that packaged `app` folder and does not need the .NET SDK inside Windows. If no packaged `app` folder exists, the installer falls back to `dotnet publish`, which requires the .NET 8 SDK in the guest. The `app` folder is a local build artifact and is intentionally ignored by Git.

For repository development without the shared-folder bundle, run this inside the guest:

```powershell
cd C:\Path\To\veil\apps\windows-agent
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-VeilAgent.ps1
```

The installer copies or publishes the agent to `%LOCALAPPDATA%\Veil\Agent\app`, copies the start/repair/uninstall scripts to `%LOCALAPPDATA%\Veil\Agent\scripts`, sets user-level `VEIL_AGENT_HOST=0.0.0.0` and `VEIL_AGENT_PORT`, registers a user logon scheduled task named `VeilAgent` when Windows allows it, and starts the agent immediately. The logon task points at the installed script copy, so agent auto-start does not depend on the original shared-folder path after installation. The start script is idempotent: it reuses an already-running installed `VeilAgent.exe`, waits briefly for a guest-local `ws://127.0.0.1:18444/` probe to succeed, and writes agent stdout/stderr logs for diagnosis. The agent process itself also enforces one instance per configured port. Pass `-NoStart` to install without starting the agent in the current session.

Bootstrap, install, and start logs are written under:

```text
%LOCALAPPDATA%\Veil\Agent\logs
```

The same directory also contains `agent.stdout.log` and `agent.stderr.log` from
the installed process. Check those files when the host cannot connect even
though the scheduled task exists.

Repair Windows Firewall and restart the agent when macOS can open the forwarded
QEMU port but `agent.health.response` still times out:

```text
Veil Shared\Veil Guest Agent\Repair Veil Agent Connectivity.cmd
```

The repair command requests Windows administrator approval through UAC when
needed, refreshes the VeilAgent program rule plus a TCP port rule for 18444, and
then starts the installed agent again. It writes
`%LOCALAPPDATA%\Veil\Agent\logs\repair-status.json`, and the final success state
requires in-guest `agent.health.response` over both `ws://127.0.0.1:18444/` and
a non-loopback Windows guest IPv4 address. This keeps a local-only agent from
looking ready when QEMU host forwarding still cannot reach the guest.

The same repair path refreshes installed support scripts and, when the current
media contains a packaged `app/VeilAgent.exe` bundle, replaces the installed app
bundle before restarting the agent. This keeps repeated `qemu-install-agent`
attempts aligned with the latest staged guest-agent code without requiring a
full uninstall.

If a virtio-win driver ISO is attached, the repair command searches attached
drives for `NetKVM\w11\ARM64` and installs matching INF files with `pnputil`
before restarting the agent. Non-zero `pnputil` exits are logged but do not stop
the firewall and agent health checks, because the driver may already be installed
or pending Windows device state. Veil does not ship those drivers; the ISO
remains a user-provided local file.

The media also contains `V.cmd`, a short automation entrypoint used by the macOS
host when sending QMP keyboard input. It runs the repair command when available
and falls back to the installer command for older staged media. `V.cmd` keeps
its console visible briefly after the command returns so host-side
`postAttemptConsole` screenshots can capture the final success or failure text.

Collect install/start diagnostics without copying Windows user data:

```text
Veil Shared\Veil Guest Agent\Collect Veil Agent Diagnostics.cmd
```

The collector writes `veil-agent-diagnostics-<timestamp>.zip` to the Windows desktop. It includes VeilAgent logs, scheduled-task metadata, process status, and a short summary; it does not copy Windows media, product keys, virtual disk contents, or user documents.

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

## Unit Tests

`apps/windows-agent/tests/VeilAgent.Tests` covers logic that does not require a
live Windows desktop — `SingleInstanceGuard`'s mutex handling (including a
regression test for a real crash where `Dispose()` released the mutex from a
different thread than the one that acquired it) and the app/process matching
logic behind HWND discovery. These run on macOS and Linux as well as Windows:

```bash
dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj
```

One test (single-instance mutual exclusion across two `SingleInstanceGuard`
instances for the same port) only asserts on Windows, since named-Mutex
cross-instance semantics are a Windows-specific OS feature that .NET's
non-Windows Mutex support does not reliably reproduce.

## Harness Contract

The repository-level contract harness validates the expected launch transcript without requiring a Windows VM:

```bash
cd harness/windows-agent-contract
npm test
```

The default frame path uses Win32/GDI capture behind `IWindowFrameCapture`. The current stream interval is 250 ms for correctness-first validation. The next capture milestone is to verify Notepad, Calculator, and Paint frames inside Windows 11 Arm and then evaluate Windows Graphics Capture or a lower-latency stream.

On July 4, 2026, the live Notepad MVP proof passed on Windows 11 Arm with QEMU/HVF, `virtio-net-pci`, user-provided virtio-win media, guest-agent health over `ws://127.0.0.1:18444`, HWND tracking, PNG frame capture, mouse input, keyboard input, and host-to-guest clipboard text. Keep this as the minimum live release gate while expanding beyond Notepad.
