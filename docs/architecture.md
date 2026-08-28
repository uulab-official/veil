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
- mount the live shared folder the guest publishes,
- store user settings and VM profiles.

## Serverless Local Runtime

Veil should not require a cloud service or remote VM backend to run Windows apps. The host app owns a local runtime provider boundary that can be implemented by Apple Virtualization, QEMU/HVF, or another local engine if the project proves it is needed. This is the UTM-like part of the architecture: VM execution remains a local Mac concern, while Veil's product layer focuses on app-window coherence instead of generic VM management.

Current provider status:

- QEMU/HVF: active local compatibility provider for the visible Windows installer console path. The macOS host prefers this provider when `qemu-system-aarch64` and Arm EDK2 firmware are installed and the profile passes readiness checks.
- Apple Virtualization: fallback feasibility provider for profile, disk, EFI, console, and boot attempts. It remains important, but it is not currently the leading path for Windows installer visibility.

The provider probe is intentionally read-only. `veil-vmctl providers --json` reports candidate providers for diagnostics and harness validation, but it must not start, stop, create, or mutate a VM.

The QEMU boot plan remains inspectable before execution. `veil-vmctl qemu-plan --json` converts the stored Windows Arm VM profile into a dry-run QEMU/HVF command plan and reports whether `qemu-system-aarch64` is locally available. `veil-vmctl qemu-start` is the guarded local execution spike for that plan: it checks QEMU doctor readiness first, starts QEMU with `-display none` plus a loopback VNC endpoint, forwards the Windows guest agent port to `127.0.0.1:18444`, attaches a QEMU HMP monitor socket for compatibility screenshots plus a QMP socket for structured input/recovery control, sends boot-prompt key input during the initial wait window, and writes process/serial logs under `~/Library/Application Support/Veil/Diagnostics`. App-launched QEMU sessions share the same monitor/QMP/VNC evidence shape. The host renders that RFB surface in one reusable, resizable, full-screen-capable macOS desktop window; the app launcher and per-HWND app windows remain separate surfaces. Screen-gated recovery reads the active VNC framebuffer, uses local OCR and pixel metrics to distinguish blank, desktop, Run, UAC, modal, and command states, and records stable latest screenshots instead of blindly sending timed input. HMP `screendump` is fallback evidence because it can target an inactive display head after Windows switches graphics devices. `veil-vmctl qemu-start --native-display` and `VEIL_USE_NATIVE_QEMU_DISPLAY=1` keep the temporary Cocoa display as explicit recovery fallbacks. A lower-latency accelerated renderer and dynamic guest-resolution renegotiation remain roadmap work.

## Session Persistence Boundary

Stopping a VM and suspending a Windows session are different products. Stop shuts Windows down; suspend keeps the user's open apps. Veil implements suspend inside the local runtime provider boundary: `VMRuntimeBooting.suspend(profile:)`/`resume(profile:)` pause the guest, stream RAM and device state through QEMU's migration path to a local file next to the virtual disk, and later relaunch QEMU with `-incoming` before unpausing. Providers that cannot persist a session throw `suspendNotSupported` instead of silently falling back to stop and start, because that fallback would destroy the user's open work.

That memory-state file is guest data, not diagnostics. It lives beside the virtual disk as `.vmsave`, while the metadata-only record (paths, machine fingerprint, migration status) lives with the other diagnostics records. The stream is single-use: Veil deletes it once the guest runs again, discards it on a cold boot, and refuses to load one whose recorded machine fingerprint no longer matches the rebuilt boot plan, since a migration stream is only valid against an identically configured machine and an advanced disk.

Snapshots are a separate capability with a separate prerequisite. QEMU internal snapshots store guest state inside the disk image, which requires `qcow2`, while Veil's default system disk is raw. Veil reports that difference through an explicit capability rather than offering a snapshot action that cannot succeed, and points at the `qemu-img convert` path plus the suspend alternative that does work on the shipping format.

## Windows Arm Install Flow

Veil treats Windows setup as a staged runtime prerequisite rather than a generic VM wizard. Before installation, the host profile tracks installer media, virtual disk, and a narrow macOS shared folder. After Windows is installed on the virtual disk, the installer ISO is no longer part of the normal boot path; it remains only user-owned reinstall/recovery media. The guest agent remains a separate pending step until Windows can boot and run an installer inside the guest.

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
- publish the shared folder over Windows' in-box SMB server,
- report health and app lifecycle events.

## File Sharing

Two separate paths, kept separate because they answer different questions.

`file.open.request` copies one file over the control channel, writes it into a temporary guest
directory, and launches an app with that path. It is the drag-and-drop-to-open interaction, where a copy
is what the user means, and it is capped at 50 MB.

The **live shared folder** is a real, writable, uncapped share. It runs in the direction that needs
nothing installed: Windows publishes `C:\VeilShared` over its in-box SMB server, and macOS mounts it
through a loopback-scoped QEMU port forward appended to the existing user network.

```text
Finder  ->  smb://127.0.0.1:18445/VeilShared
             |
             QEMU usermode NAT, hostfwd=tcp:127.0.0.1:18445-:445
             |
Windows  ->  \\<guest>\VeilShared  ->  C:\VeilShared
```

The inverted direction is forced by what exists rather than chosen: virtio-9p has no Windows guest
driver, virtio-fs has no macOS host daemon for QEMU, and QEMU's built-in `smb=` depends on a Samba build
that will not run as the non-root user QEMU invokes it as. Sharing a *Mac* folder into Windows needs an
SMB server on the host, so it is modelled as a distinct `host-smb` transport and reported as unavailable
with its prerequisite instead of being quietly conflated with the one that works.

Both host forwards name `127.0.0.1` explicitly. An empty host address in a `hostfwd` clause binds every
interface, which would publish the guest agent's unauthenticated control channel — app launch,
synthesized input, clipboard read and write — and the guest's SMB server to the local network.

## The Privilege Boundary

Veil runs QEMU as the logged-in user. That is a deliberate architectural choice, and it is why Veil
needs no admin password to install or run.

It is also the single reason for the two largest remaining gaps against Parallels:

| Capability | Blocker |
|---|---|
| USB device passthrough | macOS binds most USB devices to a kernel driver; libusb cannot take exclusive access without root. QEMU upstream tracks this as unusable on Apple Silicon. |
| Bridged / host-only networking | Both are macOS `vmnet` modes, which require root or the `com.apple.vm.networking` entitlement Apple grants case by case. |

Parallels closes both by shipping a signed system extension and a privileged helper. Veil has three
options and has not chosen one:

1. A privileged helper installed with `SMAppService`, which QEMU is launched through. Costs an admin
   prompt at install and makes Veil responsible for a root-privileged process.
2. Apple-granted entitlements, which need a distribution relationship an open-source project does not
   have.
3. Running QEMU under `sudo`. **Refused outright** — it would put a user-controlled command line and a
   network-reachable guest behind root.

Until that decision is made, both capabilities are reported as unavailable with their prerequisite by
`veil-vmctl device-passthrough-status` rather than silently missing. The live shared folder covers the
file-transfer reason people usually want USB for, and loopback port forwards cover the private
host-to-guest access people usually want host-only networking for. Neither substitutes for a security
key or a licence dongle, and the report says so.

Current scaffold status:

- `apps/windows-agent` contains the first C#/.NET 8 agent project.
- The agent exposes a WebSocket listener intended for `0.0.0.0:18444` inside the Windows guest. The macOS host still uses `ws://127.0.0.1:18444` because QEMU host forwarding maps that loopback endpoint to the guest listener.
- It handles health, app list, and selected app launch messages.
- The first app catalog covers Notepad, Calculator, and Paint; launches are structured to emit direct launch/window replies and broadcast a first `window.frame` event to event-subscriber sockets.
- After launch, a per-window stream loop continues broadcasting PNG `window.frame` events using monotonically increasing sequence numbers.
- A notification streamer boundary is wired into the WebSocket broadcast loop and emits `notification.received` events after validation/deduplication. The agent now includes a Windows `UserNotificationListener` adapter behind the package-identity gate; it syncs toast notifications only after the signed sparse package and user consent are available, and otherwise stays disabled rather than claiming notification readiness.
- The default frame implementation uses Win32/GDI HWND capture behind `IWindowFrameCapture`; the deterministic bootstrap PNG implementation remains only as a fallback/test seam until Windows-side capture evidence is recorded.
- The host-side `veil-vmctl guest-agent-wait --json` command is the post-install readiness gate: it waits for the installed agent's health response on the forwarded loopback endpoint before automation proceeds to app-runtime status or Notepad frame validation.
- The host-side `veil-vmctl app-window-proof --json --app-id winapp_notepad` command records the first app-window bridge proof after the agent connects: app launch response, matching `window.created` HWND, frame-stream subscription, first PNG frame metadata, and first-frame latency against the same 1 second fresh / 5 second stale budget used by app-runtime status. Pass `--output /path/to/proof.json` to save the same proof JSON as a durable diagnostics artifact for harness validation and bug reports.
- The host-side `veil-vmctl coherence-proof --json --app-id winapp_notepad` command records the stronger MVP proof after the app-window proof: initial HWND frame, posted mouse click, posted key input, host clipboard text send, a newer post-input HWND frame, and both initial/post-input frame latency evidence. This is the preferred pre-release proof for the Notepad loop because it covers launch, mirror freshness, input, clipboard send evidence, and responsiveness without committing Windows media or screenshots.
- The host-side `veil-vmctl multi-app-proof --json --require-complete` command turns that proof into a Daily Use coverage gate: it runs Coherence proof for Notepad, Calculator, and Paint, saves per-app diagnostics, and writes an aggregate `windowsMultiAppProof` report so app-runtime status can show whether the core inbox app set is missing, partial, or complete.
- The host-side `veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved` command is the single release gate for the first success demo: it waits for the guest agent and then runs the Coherence proof. Connected reports must include `guestAgentWait` plus `windowsAppCoherenceProof`; unavailable reports keep recovery guidance but exit non-zero in `--require-proved` mode and do not count as release proof. The harness also supports `node harness/mvp-proof/src/validate-mvp-proof.mjs --require-proved` for release gates and omits that flag only when validating recovery-report shape.

## Protocol Package

The protocol is a product boundary. It should be easy to test without booting a real VM.

MVP transport:

```text
Host connects to ws://127.0.0.1:18444 through QEMU `hostfwd=tcp:127.0.0.1:18444-:18444`
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
