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

## Next Hardening Pass

- [x] Add a typed runtime configuration summary that separates system, display, sharing, storage, network, input, and guest-agent readiness without exposing a full UTM-style settings editor.
- [x] Add state-gated host commands for app-window focus, close, input, clipboard, and launch so disabled UI mirrors actual guest-agent capability.
- [ ] Add a menu bar restore action for the last restorable Windows apps after VM reconnect, matching the current restore-intent store.
- [ ] Add an automation-facing command surface for app launch/close/status so harnesses can drive the same path as the UI.
- [ ] Extend display evidence with dynamic resolution/scaling decisions for the embedded runtime surface.
