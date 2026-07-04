# MVP

## Goal

Prove that Veil can run one Windows desktop app as a macOS-like window without making the user interact with the Windows desktop.

## Milestone v0.1: VM Boot Spike

Acceptance criteria:

- A macOS host app can create or load a VM profile.
- The host can prepare the default profile, shared folder, automatic install media, and virtual disk in one action.
- The default profile applies an adaptive CPU, memory, and disk resource plan from the current Mac before boot.
- Default profile creation prepares the macOS shared folder.
- The host can create a blank default virtual disk file for the profile.
- The host reports Windows installer, virtual disk, shared folder, automatic install media, and guest-agent setup steps.
- The host reports preflight checks for Windows Arm, CPU, memory, and disk settings.
- The VM can be started from the host app through Virtualization.framework.
- The active VM can be stopped from the host app.
- The host opens a visible VM console for the boot spike.
- The host can show basic VM status: stopped, starting, running, suspended, failed.
- VM configuration is stored locally.
- Legal/support notes clearly state that Windows media and licenses are user-provided.

## Milestone v0.2: Guest Agent Connection

Acceptance criteria:

- The Windows guest agent starts automatically after login.
- The host can connect to the agent over WebSocket.
- The host can request agent health.
- The agent returns version, OS, session, and capability data.
- A local harness can simulate the agent response without a VM.

Live status:

- Proved on July 4, 2026 with Windows 11 Arm running under QEMU/HVF, `virtio-net-pci`, user-provided virtio-win driver media, and host access through `ws://127.0.0.1:18444`.

## Milestone v0.3: App Launch and HWND Tracking

Acceptance criteria:

- The host can request installed app list.
- The host can request `notepad.exe` launch.
- The agent emits a `window.created` event for Notepad.
- The event includes window id, process id, title, bounds, and state.
- The host stores the active window session.

Live status:

- Proved on July 4, 2026 with `winapp_notepad`, `window.created` for `hwnd:000200B0`, localized Korean Notepad title handling, and launch metadata from the real guest agent.

## Milestone v0.4: Window Mirroring

Acceptance criteria:

- The agent captures one Notepad window.
- The host displays that capture stream in a separate macOS window.
- Closing the macOS window sends a guest close request.
- The host does not require the user to interact with the full Windows desktop.

Live status:

- First-frame proof passed on July 4, 2026 with a real 600 x 393 PNG frame captured from the Notepad HWND. The next product step is making this proof path open from the default app shell without terminal commands.

## Milestone v0.5: Input and Clipboard

Acceptance criteria:

- Mouse click coordinates map to the guest window.
- Keyboard input reaches Notepad.
- `Cmd+C`, `Cmd+V`, `Cmd+X`, `Cmd+A`, and `Cmd+S` map to Windows control shortcuts.
- Text clipboard sync works in both directions.
- Clipboard sync loop prevention is tested in the harness.

Live status:

- `veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved` passed on July 4, 2026 with guest-agent health, Notepad HWND tracking, initial frame, post-input frame, mouse input, keyboard input, and host-to-guest clipboard text.

## MVP Non-Goals

- a fully polished installer,
- claiming fully unattended Windows installation before a real boot reaches Windows Setup,
- multi-monitor support,
- DirectX/game performance,
- USB passthrough,
- printer/scanner bridge,
- app menu extraction,
- enterprise management.
