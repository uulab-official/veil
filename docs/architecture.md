# Architecture

## System Shape

```text
macOS Host App <---- protocol ----> Windows Guest Agent
      |
      +---- Virtualization.framework VM lifecycle
      +---- AppKit NSWindow per guest HWND
      +---- Metal or AV rendering path
      +---- macOS pasteboard, files, Dock, notifications
```

Veil has three primary responsibilities:

1. Manage the VM lifecycle enough to support app runtime behavior.
2. Mirror specific guest windows into host windows.
3. Bridge user intent: input, clipboard, files, app launch, and app state.

## macOS Host

Preferred stack:

- Swift
- SwiftUI for shell UI
- AppKit for per-app windows and responder-chain behavior
- Virtualization.framework for VM lifecycle
- Metal or AVSampleBufferDisplayLayer for frame rendering

Responsibilities:

- create, start, stop, suspend, and resume the VM,
- maintain the guest-agent connection,
- show a Windows app launcher,
- create one macOS window per tracked guest window,
- translate keyboard and pointer events,
- sync clipboard data with clear user expectations,
- expose a narrow shared folder,
- store user settings and VM profiles.

## Windows Arm Install Flow

Veil treats Windows setup as a staged runtime prerequisite rather than a generic VM wizard. The host profile tracks installer media, virtual disk, and a narrow macOS shared folder before VM boot work begins. The guest agent remains a separate pending step until Windows can boot and run an installer inside the guest.

See [Windows Arm install flow](install-flow.md) for the user-facing setup sequence and non-goals.

## UTM-Level Quality Target

UTM is the open-source benchmark for a serious Mac VM host: it has a mature VM library, device settings, guest support documentation, and recovery guidance. Veil should match that level of setup clarity and operational diagnostics while keeping a narrower product goal. Veil is not trying to become a general QEMU manager. It should instead make the Windows App Runtime path reliable enough that users know which exact prerequisite blocks boot, which file role is wrong, and what recovery step is next.

Near-term quality bars:

- distinguish installer media from boot disks before Start is enabled,
- produce structured preflight checks for every local boot prerequisite,
- make VM metadata, resource caps, and selected files visible in the host shell,
- keep fake-agent and fake-host harnesses so agent work remains testable without Windows,
- add diagnostics bundles before developer-preview distribution.

## Windows Guest Agent

MVP stack:

- C#/.NET 8
- Win32 P/Invoke
- WebSocket server
- Windows Graphics Capture spike

Possible later stack:

- Rust for high-risk capture/input/protocol modules where memory layout and performance matter.

Responsibilities:

- list installed apps,
- launch apps,
- track top-level windows and `HWND` metadata,
- capture window frames,
- receive input events,
- update and observe the Windows clipboard,
- report health and app lifecycle events.

## Protocol Package

The protocol is a product boundary. It should be easy to test without booting a real VM.

MVP transport:

```text
Host connects to ws://guest-ip:18444
JSON messages
requestId for request/response correlation
windowId represented as hwnd:<hex>
```

Later transports:

- vsock if Windows guest support is proven,
- gRPC if schema and streaming needs become stable,
- binary frame channels for capture data.

## Window Bridge

Target mapping:

```text
Windows HWND 1개 = macOS NSWindow 1개
```

The host owns macOS window chrome and focus. The guest owns app content and app semantics. The protocol must make focus, bounds, state, and close behavior explicit.

## Capture Strategy

MVP capture order:

1. MJPEG or PNG frame stream for correctness.
2. H.264 stream for lower bandwidth.
3. Dirty-region and cursor-layer optimization.
4. GPU-aware texture path if the earlier steps prove the product loop.

## Security Boundaries

- Guest messages are untrusted until parsed and validated.
- Clipboard sync must avoid invisible data surprises.
- Shared folder access must default to a narrow directory.
- Input injection must follow focused-window ownership.
- Host never accepts arbitrary guest file paths as host paths.

## Open Feasibility Questions

- Whether the chosen Virtualization.framework path can reliably boot and operate Windows 11 Arm for the project target.
- Best capture mechanism for app-window-only streaming at acceptable latency.
- Correct mapping of macOS focus, IME, keyboard layout, and accessibility behavior to Windows.
- Legal/support wording for Windows-on-Apple-Silicon distribution.
