# Architecture

## System Shape

```text
macOS Host App <---- protocol ----> Windows Guest Agent
      |
      +---- local VM runtime provider
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
- local VM runtime provider for VM lifecycle
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

## Serverless Local Runtime

Veil should not require a cloud service or remote VM backend to run Windows apps. The host app owns a local runtime provider boundary that can be implemented by Apple Virtualization, QEMU/HVF, or another local engine if the project proves it is needed. This is the UTM-like part of the architecture: VM execution remains a local Mac concern, while Veil's product layer focuses on app-window coherence instead of generic VM management.

Current provider status:

- QEMU/HVF: active local compatibility provider for the visible Windows installer console path. The macOS host prefers this provider when `qemu-system-aarch64` and Arm EDK2 firmware are installed and the profile passes readiness checks.
- Apple Virtualization: fallback feasibility provider for profile, disk, EFI, console, and boot attempts. It remains important, but it is not currently the leading path for Windows installer visibility.

The provider probe is intentionally read-only. `veil-vmctl providers --json` reports candidate providers for diagnostics and harness validation, but it must not start, stop, create, or mutate a VM.

The QEMU boot plan remains inspectable before execution. `veil-vmctl qemu-plan --json` converts the stored Windows Arm VM profile into a dry-run QEMU/HVF command plan and reports whether `qemu-system-aarch64` is locally available. `veil-vmctl qemu-start` is the guarded local execution spike for that plan: it checks QEMU doctor readiness first, launches the local Cocoa QEMU display, and writes process logs under Downloads diagnostics. The main macOS app now uses the same QEMU/HVF boot boundary when QEMU is ready, so the primary Start button opens the real local console instead of a separate simulation surface.

## Windows Arm Install Flow

Veil treats Windows setup as a staged runtime prerequisite rather than a generic VM wizard. The host profile tracks installer media, virtual disk, and a narrow macOS shared folder before VM boot work begins. The guest agent remains a separate pending step until Windows can boot and run an installer inside the guest.

See [Windows Arm install flow](install-flow.md) for the user-facing setup sequence and non-goals.

## UTM-Level Quality Target

UTM is the open-source benchmark for a serious Mac VM host: it has a mature VM library, device settings, guest support documentation, and recovery guidance. Veil should match that level of setup clarity and operational diagnostics while keeping a narrower product goal. Veil is not trying to become a general QEMU manager. It should instead make the Windows App Runtime path reliable enough that users know which exact prerequisite blocks boot, which file role is wrong, and what recovery step is next.

References:

- UTM Documentation: [What is UTM?](https://docs.getutm.app/)
- UTM GitHub: [utmapp/UTM](https://github.com/utmapp/UTM)

The UTM source separates virtualization settings into typed configuration sections such as system, virtualization, shared directories, displays, drives, networks, and serial devices. Veil should follow that structural lesson without adopting UTM's full generic VM surface: every boot-facing device should have a typed summary that can be shown in the shell, written to diagnostics, and compared against the actual local provider configuration.

Near-term quality bars:

- distinguish installer media from boot disks before Start is enabled,
- produce structured preflight checks for every local boot prerequisite,
- expose the planned local runtime devices before Start is enabled,
- expose QEMU/HVF command plans before executing QEMU,
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

- Whether Apple Virtualization can reliably boot and operate Windows 11 Arm for the project target, or whether Veil needs a local QEMU/HVF provider.
- Best capture mechanism for app-window-only streaming at acceptable latency.
- Correct mapping of macOS focus, IME, keyboard layout, and accessibility behavior to Windows.
- Legal/support wording for Windows-on-Apple-Silicon distribution.
