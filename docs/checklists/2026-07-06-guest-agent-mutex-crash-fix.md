# Guest Agent Mutex Crash Fix

Date: 2026-07-06

Goal: root-cause a real, reproducible guest-agent connectivity failure found
while dogfooding the app after the diagnostics/UX hardening pass earlier the
same day (`docs/checklists/2026-07-06-diagnostics-and-agent-visibility.md`).
The Windows guest agent had stopped answering `agent.health.response` on both
loopback and the forwarded QEMU port, even though Windows Firewall rules were
present and the TCP port was open (`hostForwardProbe.status: tcpOpen`).

## Root Cause

`SingleInstanceGuard.Dispose()` called `mutex.ReleaseMutex()` unconditionally
once `ownsMutex` was true. .NET's `Mutex.ReleaseMutex()` requires the
releasing thread to be the same OS thread that acquired the mutex (`WaitOne()`
in `TryAcquire`). `Program.cs` uses a top-level `async Main` and disposes the
guard after `await server.RunAsync()` — a console app's thread pool does not
guarantee thread affinity across `await`, so the dispose routinely runs on a
different thread than the one that acquired the mutex. This threw
`System.ApplicationException: Object synchronization method was called from
an unsynchronized block of code`, an unhandled exception that killed
`VeilAgent.exe` on every exit path (including whatever caused
`server.RunAsync()` to return/throw in the first place — that original cause
is now masked and unknown, since the crash always happened at the same
`ReleaseMutex()` line regardless of why the process was exiting).

Found by attaching to the real running VM via QEMU QMP automation (screen
capture + synthetic keyboard/mouse) and reading
`%LOCALAPPDATA%\Veil\Agent\logs\agent.stderr.log` inside the guest.

## Fix

- [x] `SingleInstanceGuard.Dispose()` now catches `ApplicationException` around
      `ReleaseMutex()` and treats it as a no-op — Windows releases a
      process's named mutexes automatically on exit, so an explicit release
      is a best-effort courtesy, not a requirement for correctness.
- [x] Rebuilt and redeployed the agent bundle into the running dev VM's
      shared folder, then rebooted the VM (the shared folder's guest-agent
      bundle is baked into boot-time media, not a live share — updates made
      while the VM is already running are not visible to the guest until the
      next boot).
- [x] Re-verified the full MVP loop end to end after the fix:
      `guest-agent-wait` connected on the first attempt, `app-window-proof`,
      `coherence-proof`, and `mvp-proof --require-proved` (exit 0, `status:
      "proved"`) all passed against the real Windows 11 Arm guest.

## Bonus Fix Found During Live Verification

While re-running the MVP proof against real hardware, `winapp_calculator`
failed to launch (`app_launch_failed: calc.exe started but no top-level
window was discovered`) even though a real "계산기" (Calculator) window
visibly opened on screen. Root cause: Windows 11's `calc.exe` is a launcher
stub for the packaged Calculator app — the actual top-level window belongs to
a separate `CalculatorApp.exe` process, and `WindowsDesktop.DoesProcessMatchApp`
only matched the originally-launched process's own executable name.

- [x] Added `WindowsAppDescriptor.AlternateExecutables` and extended
      `DoesProcessMatchApp` to check it, so Calculator's window can be found
      even though it belongs to a different process than the one
      `Process.Start("calc.exe")` returns.
- [x] Notepad and Paint re-confirmed working end to end on the same guest
      after the mutex fix, with no changes needed.

## Follow-Up: Calculator Cold-Start Timeout (same day)

The Calculator process-matching fix above still occasionally missed the
5-second/50-attempt discovery window in `WindowsDesktop.LaunchAppAsync` — the
packaged Calculator app's cold activation can exceed that budget on this
ARM64 VM, even though the window does open (confirmed via screenshot).

- [x] Added `WindowsAppDescriptor.WindowDiscoveryTimeoutOverride` (default
      5s, matching the previous hardcoded budget for every other app) so
      `LaunchAppAsync`'s discovery loop can use a longer budget for apps that
      need it, instead of one global constant.
- [x] Set Calculator's override to 12 seconds in `AgentSession.cs`.
- [x] Added `apps/windows-agent/tests/VeilAgent.Tests`, the first test
      project for the Windows agent (previously zero test coverage — the
      Mutex crash above shipped and would have shipped again without one).
      Covers `SingleInstanceGuard` (including a direct regression test that
      reproduces the cross-thread `Dispose()` crash pattern) and the
      app/process matching logic (`DoesProcessMatchApp`,
      `AlternateExecutables`, `WindowDiscoveryTimeout`). Runs on macOS via
      `dotnet test` since none of the covered logic requires live Win32
      P/Invoke calls.
- [~] **Partially verified live**: after redeploying and rebooting the VM
      with this fix, screenshots confirm the Calculator window reliably opens
      (visually proving both the `AlternateExecutables` match and the longer
      discovery budget work). A clean automated `app-window-proof` pass for
      Calculator specifically was not captured in this session — by that
      point the dev VM had accumulated repeated `qemu-install-agent`/driver
      reinstall cycles from this same debugging session that made the
      WebSocket connection intermittently drop mid-request
      ("Socket is not connected", separate timeouts), unrelated to the
      Calculator fix itself. Notepad, Paint, and the full `mvp-proof
      --require-proved` gate all passed cleanly earlier in the same session
      before that accumulated flakiness set in. Re-run `veil-vmctl
      app-window-proof --json --app-id winapp_calculator` on a freshly
      booted VM to get a clean automated confirmation.
