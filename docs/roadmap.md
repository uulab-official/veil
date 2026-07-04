# Roadmap

Veil aims for Parallels-class coherence, but the roadmap is deliberately staged around proofs that can be tested.

UTM is the quality benchmark for local VM setup depth, diagnostics, and open-source operational maturity. Veil should not clone UTM's broad QEMU device surface; it should match the reliability bar for the narrower Windows App Runtime path.

Veil does not have a cloud or server VM backend. Its VM layer is a local runtime provider boundary inside the macOS app.

## v0.1: VM Boot

- macOS host shell.
- VM profile storage.
- Windows Arm install readiness checklist.
- VM profile preflight checks.
- Installer media role validation.
- Adaptive default CPU, memory, and disk profile based on the current Mac.
- Explicit Windows Arm ISO selection with security-scoped bookmark persistence.
- Shared folder preparation.
- Local diagnostics bundle export.
- Last boot attempt report in diagnostics.
- Typed local runtime provider device summary.
- Start, stop, suspend, resume states.
- Basic VM display surface for debugging.
- Reopenable VM console action while the machine is running.
- Documented Windows installer display risk for Apple's Virtio graphics path.
- Documentation for Windows media and license boundaries.

Exit criteria:

- A contributor can see which local setup prerequisites are blocking Windows boot.
- A contributor can see which profile settings are invalid before boot.
- A contributor is warned when a disk image is selected where bootable installer media is expected.
- A contributor can prepare a VM profile whose resource caps are automatically sized for the host Mac.
- A contributor can select a Windows Arm ISO once and let Veil reuse the stored security-scoped bookmark during preparation and launch.
- A contributor can export metadata-only diagnostics for boot-readiness failures.
- A contributor can inspect the latest Start attempt result and startup error without sharing Windows media or disk contents.
- A contributor can inspect planned boot devices before starting the VM.
- A contributor can start a guest VM from the host app.
- A contributor can reopen the VM console after closing it.
- Failure states are visible and debuggable.

## v0.2: Guest Agent

- Windows service/user agent split.
- WebSocket control channel.
- Health endpoint.
- App list endpoint.
- Harness fake agent for host development.

Exit criteria:

- Host can connect to a real or fake guest agent and read capabilities.

## v0.3: App Launch

- App registry discovery.
- `notepad.exe` launch request.
- Top-level `HWND` tracking.
- `window.created`, `window.updated`, and `window.closed` events.

Exit criteria:

- Host launches Notepad and receives stable window metadata.

## v0.4: Coherence Window MVP

- Capture one `HWND`.
- Render captured frames in a macOS `NSWindow`.
- Forward mouse click and keyboard input.
- Close/focus synchronization.

Exit criteria:

- Notepad appears as its own macOS window and accepts input.

## v0.5: Clipboard and Files

- Text clipboard sync.
- Shortcut mapping for common commands.
- Shared folder setup.
- Open file in guest app from host path.
- Harness tests for clipboard loop prevention.

Exit criteria:

- A text file or spreadsheet-like workflow can cross host and guest without showing the Windows desktop.

## v1.0: Developer Preview

- Windows app launcher.
- Coherence window bridge for common desktop apps.
- Text clipboard.
- Shared folder.
- Basic Dock integration for reopening, focusing, closing, restoring, and launching Windows app windows while the main Veil window is hidden.
- Automatic VM start and suspend.
- Recovery instructions and diagnostics bundle.

Exit criteria:

- Technical users can install, configure, and use Veil for simple Windows apps with documented limitations.

## v1.5: Daily Use

- Retina scaling.
- Multiple windows per app.
- Better frame latency.
- App icons.
- Drag and drop.
- Windows notifications to macOS notifications.
- Initial printer bridge research.

## v2.0: Work App Runtime

- Snapshot management.
- App-specific resource profiles.
- Windows update handling guidance.
- Recovery mode.
- Enterprise deployment profile research.
- USB/printer/smart-card feasibility spikes.

## v3.0: Advanced Compatibility

- GPU pipeline improvements.
- DirectX compatibility research.
- Remote Windows VM mode.
- Enterprise management.
- Smart-card and certificate bridge if legally and technically viable.

## Current Next Step

Veil now has the local QEMU/HVF boot path, embedded display evidence, fake-agent harnesses, a live Windows 11 Arm guest-agent connection through QEMU host forwarding, and a proven Notepad MVP loop: app launch, HWND tracking, PNG frame capture, mouse input, keyboard input, and host-to-guest clipboard text. The next work is to close the gap between "the CLI can prove the loop" and "the app feels like a daily usable Windows App Runtime" without expanding into a generic VM manager.

1. Productize the proven path: Start VM, auto-repair/reconnect the guest agent when needed, launch Notepad, and open the mirrored macOS window from the app shell without terminal commands. The automatic recovery handoff, status command, and user-actionable Continue/Repair Agent launcher path are now wired; the remaining gate is built-app end-to-end UX validation.
2. State-gated app runtime commands: launch, focus, close, input, clipboard, restore, quiet-runtime readiness, repair guest agent, and stop actions should be available only when the VM and guest-agent state support them.
3. Coherence restore loop: after VM reconnect, restore selected Windows apps and keep the Veil launcher hidden unless recovery is needed.
4. UTM-style runtime configuration contract: expose typed system, display, sharing, storage, network, input, guest-agent readiness, and recovery command summaries in one supportable diagnostic surface.
5. Harness automation surface: keep expanding the `app-runtime-status` and `app-runtime-action` commands so launch, focus, close, restore, input, clipboard, stop, repair, and proof runs share the same host model boundaries.
6. Multi-app validation: repeat the live proof for Calculator and Paint, then tune frame latency after correctness holds across more than Notepad.
