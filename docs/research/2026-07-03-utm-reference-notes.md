# UTM Reference Notes

Date: 2026-07-03

Purpose: record the UTM/Parallels-inspired product lessons being adapted into Veil without copying UTM code or assets.

## Sources Reviewed

- UTM GitHub repository: https://github.com/utmapp/UTM
- UTM source: `Platform/macOS/UTMMenuBarExtraScene.swift`
- UTM source: `Platform/Shared/VMCommands.swift`
- UTM source: `Scripting/UTMScriptingVirtualMachineImpl.swift`
- UTM source: `Configuration/UTMQemuConfiguration.swift`
- UTM source: `Configuration/UTMQemuConfigurationDisplay.swift`
- UTM scripting reference: https://docs.getutm.app/scripting/reference/
- UTM release discussions around multiple displays/headless display windows: https://github.com/utmapp/UTM/discussions/4398

## Lessons For Veil

- UTM is organized around explicit VM lifecycle, configuration, rendering, scripting, and service boundaries. Veil should keep the same seriousness around local runtime state, but expose a narrower app-runtime surface instead of a general VM manager.
- UTM keeps QEMU configuration as typed sections for system, input, sharing, display, drive, network, serial, and sound. Veil should keep boot/runtime/provider data typed as well, but only expose the parts needed for the Windows App Runtime loop.
- UTM exposes machine status as a first-class automation concept. Veil should do the same for app-window sessions: running Windows apps should be discoverable, focusable, and closable from a stable host surface.
- UTM's menu bar extra is intentionally small: show app, list VMs, expose state-appropriate start/stop/suspend/reset commands, and quit. Veil's menu bar should stay similarly operational instead of becoming a second dashboard.
- UTM's scripting layer validates lifecycle state before actions. Veil should apply the same rule to app-window sessions: only issue guest-agent close/input/focus actions against tracked HWNDs.
- UTM supports multiple display outputs as independent host windows. Veil should map this pattern at the app level: one tracked Windows HWND becomes one macOS `NSWindow`.
- Parallels-style Coherence means the launcher should disappear once the desired Windows app is open, while a menu bar control remains available for returning to Veil or managing running Windows apps.

## Current Adaptation

- Menu bar `Running Windows Apps` lists active mirrored HWND sessions.
- Each running session can be brought to front without reopening the Veil launcher.
- Each running session can be closed through the guest-agent close protocol before the local macOS mirror window is removed.
- Running mirrored sessions can now be closed as a group from the menu bar, using the same guest-agent close path as individual windows.
