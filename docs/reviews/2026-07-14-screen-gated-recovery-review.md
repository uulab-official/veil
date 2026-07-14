# Screen-Gated Recovery Review

Date: 2026-07-14

Scope: automatic Windows guest-agent recovery on the local QEMU/HVF provider.
Review method: gstack CEO, design, and engineering criteria with automatic
decisions favoring completeness, explicit behavior, existing boundaries, and
action over deferred discussion.

## CEO Review

Rating: 8/10 for this slice, 4/10 against the full Parallels-class objective.

The product premise remains sound: Veil should make a Windows app appear and
behave like a Mac app, while the VM and Windows desktop remain implementation
details. Screen-gated repair advances that premise because a healthy runtime now
does nothing, a sleeping display is recovered quietly, and raw Run/UAC input is
sent only when the corresponding screen state is observed.

The slice is not the product. A technical user can still prove more through the
CLI than through the built app. The next highest-leverage product gate is one
default app flow that starts or wakes Windows, reconnects support, opens the last
Windows app, and presents only its macOS window without requiring a terminal or
full desktop.

Decision: hold the narrow Windows App Runtime scope. Do not expand into a generic
UTM device editor. Match UTM's operational reliability and Parallels' app-first
experience within the existing local-runtime boundary.

## Design Review

Rating: 7/10 for recovery behavior, 5/10 for end-to-end product coherence.

Healthy recovery must remain invisible. When it takes longer than two seconds,
the app should show one calm status in the existing primary surface: waking
Windows, reconnecting Windows apps, or opening the selected app. Run, QMP, VNC,
UAC, sockets, OCR, and retry counts belong in diagnostics, not the normal UI.

The full Windows desktop should appear only for installation or explicit
recovery. A mirrored Windows app window remains the primary surface after setup.
There must never be a launcher window plus an app window plus a recovery console
competing for attention.

Decision: reuse the existing one-screen launcher and mirrored AppKit window
model. Add no new sidebar or diagnostic dashboard. Map the new readiness states
to the current single progress/status area and keep detailed evidence behind the
existing diagnostics action.

## Engineering Review

Rating: 7/10.

Strengths:

- The active VNC framebuffer is now authoritative; HMP capture is a fallback.
- Blank-frame, desktop, Run, UAC, centered-modal, and command-shell states have
  explicit JSON evidence.
- OCR is local to macOS and pixel metrics remain available when text recognition
  is weak or localized.
- Recovery has bounded wake, Run retry, and UAC gates.
- Connected preflight sends zero input and creates no redundant recovery image.
- Readiness PNGs use stable latest names instead of growing without bound.

Open risks:

- The orchestration still lives in the large `VeilVMControl/main.swift` command
  implementation. Move it behind an injected coordinator before adding more
  recovery states.
- Frame analysis and sequence builders have unit tests, but the complete
  desktop-to-Run-to-UAC coordinator needs deterministic fake capture, health,
  and input tests.
- Vision OCR can add seconds on its first invocation. Keep desktop checks
  pixel-only, measure Run/UAC recognition latency, and move recognition off the
  UI path before host-shell integration.
- The live pass proved black-frame detection, wake-to-desktop, and connected
  zero-input behavior. A forced live UAC recovery report is still missing.

Decision: accept the current slice after full tests, then make coordinator
extraction and forced UAC proof the next engineering work before presenting this
as fully automatic repair.

## Ordered Follow-Up

- [ ] Extract a `QEMUConsoleRecoveryCoordinator` with injected capture, OCR,
  input, pointer, and health dependencies.
- [ ] Add deterministic coordinator tests for blank wake, already-connected
  skip, Run first-pass success, Run retry, UAC recognition, UAC timeout, and
  capture failure.
- [ ] Record one forced live UAC recovery JSON report against Windows 11 Arm.
- [ ] Route screen-gated recovery through the built app's one primary action.
- [ ] Run built-app end-to-end validation without launching a second host window.
- [ ] Resume frame-latency and package-identity work only after the default app
  flow is reliable.
