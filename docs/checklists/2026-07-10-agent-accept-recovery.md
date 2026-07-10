# Guest Agent Accept Recovery Checklist

Goal: prevent a diagnostic TCP connection from taking down the long-running
Windows guest agent, and keep the real Windows App Runtime loop verifiable.

## Checklist

- [x] Reproduce a forwarded-port state where macOS could open TCP but
      `agent.health.response` timed out.
- [x] Capture the Windows guest failure: `SocketException` 10054 escaping from
      `TcpListener.AcceptTcpClientAsync` after a short-lived client reset.
- [x] Keep the listener alive for `ConnectionAborted`, `ConnectionReset`, and
      `Interrupted`, while continuing to surface non-transient failures.
- [x] Add .NET unit coverage for accepted transient errors and a non-transient
      `AccessDenied` counterexample.
- [x] Extend the Windows-agent contract harness to require the transient
      accept-recovery path.
- [x] Publish the updated win-arm64 agent bundle, rebuild local automatic
      install media, power down the existing VM, and relaunch QEMU/HVF so the
      running guest receives the new bundle.
- [x] Verify `qemu-install-agent --wait-seconds 60` reaches live
      `agent.health.response` after the restart.
- [x] Verify a real `mvp-proof --require-proved` result: Notepad HWND tracking,
      600 x 393 PNG frames, mouse input, keyboard input, and host-to-guest
      clipboard all completed.

## Evidence

- Agent unit tests: 54 passed.
- Windows-agent contract harness: 22 passed.
- Real QEMU/HVF guest: the agent reconnected and a fresh Notepad proof returned
  `status=proved`; the VM is intentionally left running for host-shell testing.

## Remaining

- Exercise the built macOS shell end to end against this running VM: start or
  reconnect, queue/repair the guest agent when necessary, and open the actual
  mirrored Notepad macOS window without terminal commands.
- Collect the guest-side installer and agent logs after the healthy runtime
  path, then compare them with the host proof evidence.
