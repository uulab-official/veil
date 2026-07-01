# Roadmap

Veil aims for Parallels-class coherence, but the roadmap is deliberately staged around proofs that can be tested.

UTM is the quality benchmark for VM setup depth, diagnostics, and open-source operational maturity. Veil should not clone UTM's broad QEMU device surface; it should match the reliability bar for the narrower Windows App Runtime path.

## v0.1: VM Boot

- macOS host shell.
- VM profile storage.
- Windows Arm install readiness checklist.
- VM profile preflight checks.
- Installer media role validation.
- Adaptive default CPU, memory, and disk profile based on the current Mac.
- Shared folder preparation.
- Local diagnostics bundle export.
- Typed Virtualization.framework device summary.
- Start, stop, suspend, resume states.
- Basic VM display surface for debugging.
- Documentation for Windows media and license boundaries.

Exit criteria:

- A contributor can see which local setup prerequisites are blocking Windows boot.
- A contributor can see which profile settings are invalid before boot.
- A contributor is warned when a disk image is selected where bootable installer media is expected.
- A contributor can prepare a VM profile whose resource caps are automatically sized for the host Mac.
- A contributor can export metadata-only diagnostics for boot-readiness failures.
- A contributor can inspect planned boot devices before starting the VM.
- A contributor can start a guest VM from the host app.
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
- Basic Dock integration.
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

The protocol harness is now executable from JavaScript, the Swift host probe, and the SwiftUI host shell. The shell also has a VM Runtime status boundary, one-click VM preparation, adaptive host-sized resource caps, local boot-path checks, installer media role validation, shared-folder preparation, default sparse-disk creation, a setup-step checklist, profile preflight checks, metadata-only diagnostics export, a typed Virtualization.framework device summary, and a Virtualization.framework boot spike that opens and stops a VM console. The next implementation step is the v0.1/v0.2 overlap:

1. Harden the Virtualization.framework boot spike against real Windows 11 Arm installer variants.
2. Add deeper validation for selected installer media and virtual disk paths, including file format and bootability checks proven by the spike.
3. Keep the fake-agent path available so UI and protocol work stay testable without Windows.
4. Validate the actual Windows 11 Arm VM path separately.
