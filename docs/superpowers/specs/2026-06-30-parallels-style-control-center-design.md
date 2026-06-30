# Parallels-Style Control Center Design

Date: 2026-06-30

## Intent

Veil should feel less like a protocol harness and more like a desktop virtualization product. The next UI pass will move the VM Runtime screen toward a Control Center model inspired by common virtualization products: one primary Windows 11 Arm machine, obvious power actions, installation readiness, and Mac integration status.

## Product Shape

The VM Runtime tab becomes the primary VM dashboard. It should show a large "Windows 11 Arm" machine card with runtime state, architecture, boot readiness, and direct actions. Secondary panels explain setup progress, selected installer media, selected virtual disk, and why Start is disabled.

## Mac Integration Surface

Veil should make the Mac/Windows bridge visible even before full Coherence-style behavior is implemented. A Mac Integration panel will show capabilities such as app launch, window tracking, window capture, clipboard, shared folders, and Dock-style launching as status items. Items that are not implemented yet should be labeled as planned, not hidden.

## Interaction Rules

- Keep native macOS sidebar and toolbar behavior.
- Keep the UI honest: do not imply VM boot or Coherence behavior is complete when the core runtime still reports it as unavailable.
- Prefer direct verbs: Start, Refresh, Create Profile, Select Installer, Select Disk.
- Show blocked states with a clear reason close to the action.
- Avoid marketing pages; the first screen must remain operational.

## Acceptance Criteria

- VM Runtime reads as a Control Center rather than a settings form.
- Windows 11 Arm setup progress is visible without reading raw rows.
- Mac integration status is visible in the product UI.
- Existing demo/live agent fallback still compiles and tests pass.
- The change is documented and committed to `main`.
