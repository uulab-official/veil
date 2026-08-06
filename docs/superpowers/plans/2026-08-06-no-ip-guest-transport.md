# No-IP Guest Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove and, only if the proof succeeds, implement a production-safe guest-agent transport for Windows Arm VMs that have no usable guest IPv4 address.

**Architecture:** Keep WebSocket-over-QEMU-user-network as the default. Add a separately gated `virtio-serial-pci` transport consisting of a QEMU Unix-socket chardev, a host stream adapter, and a Windows `vioser` endpoint. Reuse the existing JSON message shapes, but define an explicit length-delimited frame so partial reads and binary payloads cannot corrupt protocol messages. No fallback is considered available until a real health request/response is observed inside a clean Windows VM.

**Tech Stack:** Swift 6.2 Foundation/Network, QEMU/HVF, C#/.NET 8 Windows agent, VirtIO `vioser` ARM64 driver, existing protocol and contract harnesses.

## Constraints

- Do not enable the new transport by default or silently downgrade from WebSocket.
- Do not add VirtIO driver binaries, Windows images, product keys, or proprietary VM assets to the repository.
- Do not claim guest readiness from a TCP-open port, loopback-only health, device presence, or driver installation alone.
- Preserve host, guest, protocol, and harness boundaries; update protocol fixtures whenever frame semantics change.
- Keep the first vertical slice to health. Do not implement frame streaming, input, or clipboard on the new transport until health is stable.

### Task 1: Prove the device and endpoint contract

**Files:**
- Inspect: `apps/mac-host/Sources/VeilHostCore/QEMUWindowsBootPlan.swift`
- Inspect: `apps/windows-agent/src/VeilAgent/AgentEndpoint.cs`
- Add tests: `apps/windows-agent/tests/VeilAgent.Tests/`
- Update: `docs/checklists/2026-08-05-production-readiness.md`

- [x] Confirm QEMU exposes `virtio-serial-pci` and `virtserialport` on the supported host.
- [x] Confirm the supported VirtIO ISO contains Windows 11 Arm64 `vioser`.
- [x] Confirm the Windows user-mode contract from the upstream source: enumerate the VirtIO serial port interface, identify the named port, then use file I/O.
- [x] Add a guest diagnostic that reports discovered VirtIO serial port names and host-connected state without starting the fallback transport.
- [ ] Run that diagnostic on a clean Windows Arm VM with a named `org.veil.agent` QEMU port and preserve the output as evidence.

### Task 2: Add an opt-in host chardev and framing layer

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/QEMUWindowsBootPlan.swift`
- Add: `apps/mac-host/Sources/VeilHostCore/VirtioSerialTransport.swift`
- Add tests: `apps/mac-host/Tests/VeilHostCoreTests/`
- Update: `packages/protocol/` and protocol fixtures only if the frame is externally observable

- [x] Add an explicit opt-in `virtio-serial-probe` setting and keep the default WebSocket plan unchanged.
- [ ] Make the launch path create a private Unix socket endpoint before QEMU starts and close it on every boot failure, stop, and reconnect.
- [ ] Add a bounded length-prefixed frame codec with maximum frame size, cancellation, timeout, and partial read/write tests.
- [ ] Return an actionable diagnostic when QEMU connects no client or the guest does not open the named port.
- [ ] Verify concurrent request/reply and passive event behavior matches `HostTransport`/`HostEventSource` semantics.

### Task 3: Add the guest vioser endpoint

**Files:**
- Add: `apps/windows-agent/src/VeilAgent/VirtioSerialAgentEndpoint.cs`
- Modify: `apps/windows-agent/src/VeilAgent/Program.cs`
- Add tests: `apps/windows-agent/tests/VeilAgent.Tests/`
- Update: `apps/windows-agent/scripts/` and support-media fixtures as needed

- [ ] Enumerate the upstream VirtIO serial device interface instead of hard-coding a symbolic path.
- [ ] Open only the configured named port and report host-connected state before accepting requests.
- [ ] Use bounded overlapped file I/O with cancellation and deterministic close behavior.
- [ ] Feed the existing `AgentSession` request/reply and event paths only after the transport handshake succeeds.
- [ ] Keep WebSocket startup and single-instance behavior unchanged when the feature flag is absent.

### Task 4: Prove the first vertical slice

- [ ] Record host socket connection, guest port discovery, health request, and health response in both logs.
- [ ] Launch Notepad over the new transport and verify an HWND-backed frame.
- [ ] Verify keyboard input and host-to-guest clipboard over the new transport.
- [ ] Force a disconnect and prove retry/cleanup does not leave a stale QEMU socket or agent handle.
- [ ] Run the full regression gate, production-readiness gate, and a fresh VM install/repair/reboot cycle.
- [ ] Check the no-IP P0 items only after all live evidence exists; otherwise leave `releaseReady=false`.

## Exit criteria

The transport is production-eligible only when the clean-VM health round trip and the Notepad/input/clipboard vertical slice pass with bounded failure recovery. Until then, the supported product state remains WebSocket with an explicit guest-network blocker, not a partially wired serial fallback.

## Live probe result — 2026-08-06

The first opt-in QEMU probe created the named chardev socket and booted QEMU, but the managed Windows disk stayed at `Start boot option` (`800×600`). A baseline launch without the VirtIO serial device reached the Windows desktop (`1024×768`) on the same disk. The probe is therefore useful as a bounded compatibility test, but it is not a working transport and must not be enabled for users until the boot incompatibility is resolved or a different transport architecture is proven.
