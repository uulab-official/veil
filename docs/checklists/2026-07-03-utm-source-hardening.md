# UTM Source Hardening Checklist

Date: 2026-07-03

Goal: adapt concrete UTM source patterns into Veil while keeping Veil focused on a Windows App Runtime for macOS, not a broad VM manager clone.

## UTM Source Reviewed

- [x] `Platform/macOS/UTMMenuBarExtraScene.swift`: small menu bar surface with show, status-scoped VM actions, and quit.
- [x] `Platform/Shared/VMCommands.swift`: app-wide commands route into lifecycle and support surfaces instead of duplicating dashboards.
- [x] `Scripting/UTMScriptingVirtualMachineImpl.swift`: lifecycle automation validates VM state before start, suspend, stop, delete, clone, or export.
- [x] `Configuration/UTMQemuConfiguration.swift`: QEMU runtime settings are typed into system, QEMU, input, sharing, display, drive, network, serial, and sound sections.
- [x] `Configuration/UTMQemuConfigurationDisplay.swift`: display settings are explicit about dynamic resolution, scaling, native resolution, and target-specific defaults.

## Applied To Veil

- [x] Keep menu bar operations status-first and compact rather than adding another full control dashboard.
- [x] Treat running Windows app HWND sessions as the first-class lifecycle unit after the VM is running.
- [x] Add menu-bar `Close All` for mirrored Windows app windows using the same guest-agent close path as individual windows.
- [x] Add model-level test coverage for closing multiple mirrored Windows app sessions and unsubscribing frame streams.
- [x] Record UTM source-file lessons in `docs/research/2026-07-03-utm-reference-notes.md`.
- [x] Create an implementation roadmap plan for the next UTM-source hardening slices.
- [x] Add state-gated host command checks for app launch, focus, close, input, clipboard, and restore.
- [x] Bind menu bar Windows app commands to model-level availability checks.
- [x] Add a menu bar restore action for restorable Windows apps after guest-agent reconnect.
- [x] Add `veil-vmctl app-runtime-status --json` plus a Node harness validator for app-runtime status/actions.
- [x] Add `veil-vmctl qemu-install-status --json` plus a Node harness validator for persistent Windows install evidence.
- [x] Extend display evidence with planned resolution, aspect-fit scaling, Retina rendering policy, and live VNC validation guidance.
- [x] Add install-status recovery guidance for blocked installs that still have a running QEMU process attached to the configured disk.
- [x] Surface install-status recovery steps inside the main Windows setup screen, not only in CLI JSON.
- [x] Expose running QEMU process evidence in install-status JSON so recovery guidance can name the exact PID and monitor/QMP sockets.
- [x] Add `veil-vmctl guest-agent-wait --json` plus a Node harness validator for the post-install guest-agent readiness gate.
- [x] Add `veil-vmctl app-window-proof --json` plus a Node harness validator for launch, HWND tracking, and first frame evidence.
- [x] Add `veil-vmctl app-window-proof --output /path/proof.json` so app launch/HWND/frame proof can be saved and revalidated as a diagnostics artifact.
- [x] Add `veil-vmctl coherence-proof --json --output /path/proof.json` plus a Node harness validator for launch, HWND tracking, first frame, post-input frame, mouse/key input, and host clipboard send evidence.
- [x] Add `veil-vmctl mvp-proof --json --output /path/proof.json` plus a Node harness validator that chains guest-agent wait with the Coherence proof.
- [x] Add `harness/mvp-proof --require-proved` release mode so unavailable recovery JSON cannot pass as an MVP release proof.
- [x] Add `veil-vmctl mvp-proof --require-proved` so the CLI exits non-zero when the MVP loop is unavailable.

## Next Hardening Pass

- [x] Add a typed runtime configuration summary that separates system, display, sharing, storage, network, input, and guest-agent readiness without exposing a full UTM-style settings editor.
- [x] Add state-gated host commands for app-window focus, close, input, clipboard, and launch so disabled UI mirrors actual guest-agent capability.
- [x] Add a menu bar restore action for the last restorable Windows apps after VM reconnect, matching the current restore-intent store.
- [x] Add an automation-facing command surface for app launch/close/status so harnesses can drive the same path as the UI.
- [x] Add `veil-vmctl app-runtime-action` plus a validator so launch/focus/close/restore can be exercised without clicking the UI.
- [x] Extend `veil-vmctl app-runtime-action` to cover clipboard and bounded text input through the same guest-agent protocol path.
- [x] Extend `veil-vmctl app-runtime-action` to cover left-click input through the same guest-agent `input.mouse` path.
- [x] Add an install-status command surface so persistent Windows setup evidence can be checked without manually inspecting raw launch records.
- [x] Extend display evidence with dynamic resolution/scaling decisions for the embedded runtime surface.
- [x] Add a guest-agent wait gate so automation can move from Windows desktop proof to app-window launch proof only after the forwarded agent endpoint is reachable.
- [x] Add an app-window proof gate so automation can verify a real Windows app launch reaches first-frame mirror evidence before manual UI testing.
- [x] Add saved app-window proof artifacts so CLI automation can attach the same evidence the harness validates.
- [x] Add a Coherence-style proof gate so automation can verify launch, frame freshness after input, keyboard input, mouse input, and host clipboard send in one Notepad MVP loop.
- [x] Add a one-command MVP proof gate so release checks can wait for the guest agent and then validate the Notepad Coherence loop.
- [x] Split MVP proof validation into recovery-report validation and release-proof validation with `--require-proved`.
- [x] Make the CLI and harness both enforce proved status in release mode.
- [x] Reject untracked HWND close, focus, frame-subscribe, mouse, and key actions in both the real Windows agent boundary and the fake-agent harness.
- [x] Add Dock-level Windows app runtime actions so hidden coherence sessions can be focused, closed, restored, or launched without reopening the full VM console.
- [x] Add Dock integration state to `app-runtime-status` JSON and harness validation so Dock regressions are visible in automation.
