# Single-Action Windows Setup Canvas

Date: 2026-08-04
Status: Approved for implementation

## Purpose

Make Veil's first-run screen feel like a focused product journey instead of a VM control panel. Before Windows is installed, the main window should explain the current state and offer one obvious next action. Secondary setup and diagnostic controls remain available without competing with that action.

## Scope

This iteration changes the first-run and Windows-installation presentation in the macOS host shell. It does not change VM preparation, ISO download, boot, guest-agent, or app-launch behavior. The installed Windows app launcher and live Windows display remain functionally unchanged except for the transition into those states.

## Interaction Model

The content below the persistent window header is one edge-to-edge setup canvas. The canvas has three visual regions:

1. A centered identity region with the Windows mark, a short state title, and one explanatory sentence.
2. A single primary action whose label and symbol come from the existing setup state.
3. Quiet secondary access for an existing ISO, settings, and diagnostics when those actions are valid.

The screen must not show a second card frame, modal-like panel, duplicate bottom control bar, permanent setup checklist, or multiple equally prominent buttons.

## State Presentation

The canvas renders one of these mutually exclusive states:

- **Needs installer:** explain that Veil needs Windows 11 Arm and emphasize `Download Windows 11`.
- **Needs preparation:** identify the selected installer and emphasize `Prepare Windows`.
- **Ready to install:** explain that setup will remain inside Veil and emphasize `Install Windows`.
- **Starting or installing:** keep the primary action location stable, replace the button with progress feedback, and prevent duplicate actions.
- **Windows display available:** replace the setup canvas with the live Windows display using the existing display-selection policy.
- **Needs integration:** explain the Mac-window integration step and emphasize its existing repair or connection action.
- **Recoverable failure:** replace the normal explanation with a concise error summary and make the relevant recovery action primary. Diagnostics remain secondary.

The persistent header continues to own the global status badge. The setup canvas must not repeat `Setup Required`, runtime state, or refresh controls.

## Secondary Actions

`Use Existing ISO` remains directly discoverable only while installer media is needed. Settings is always available as a quiet icon action. Diagnostics appears only when evidence exists or a failure makes it useful. Destructive runtime actions and developer proof actions stay in the existing settings or overflow surfaces.

Secondary actions use standard bordered or icon-only SwiftUI controls. They must not use the prominent button style and must not appear between the state explanation and the primary action.

## Layout and Responsiveness

The setup canvas fills the space below the header with no outer card or monitor bezel. Its centered content uses a readable maximum width and adapts vertically:

- At regular window sizes, content is vertically centered with generous spacing.
- At the supported `820 x 560` minimum, spacing and artwork scale down before text or controls are clipped.
- Long ISO names truncate in the middle or tail and expose the full value through help or accessibility text.
- Progress and error states keep the primary control area at a stable size to avoid layout jumps.

## Accessibility and Motion

The state title is the first semantic heading. The primary action has an explicit accessibility label and help text. Progress exposes an in-progress value and disables duplicate activation. Secondary icon actions have text labels for VoiceOver and tooltips for pointer users.

Animations are limited to short opacity or scale transitions between state content. The layout does not animate continuously, and it respects Reduce Motion by relying on SwiftUI's environment-driven behavior.

## Architecture

The view derives a small value-type presentation model from the existing `VMRuntimeSnapshot`, installation evidence, and current loading state. That model owns title, detail, artwork state, primary label, primary symbol, progress visibility, and secondary-action visibility. Runtime operations remain in the existing closures supplied to `WindowsSetupDisplayPanel`.

The presentation model must be independently testable and must not perform file, network, or VM operations. The SwiftUI body composes focused subviews for identity, primary action/progress, secondary actions, and error detail instead of adding more conditional branches to one large view builder.

## Error Handling

Known actionable failures use the existing recovery route and a short user-facing explanation. Raw provider, QEMU, path, or protocol details do not appear in the main canvas. They remain available through settings or diagnostics. When no safe recovery action exists, the primary action becomes `Open Settings` rather than presenting a disabled button as the main path.

## Verification

Implementation is complete when:

- Unit tests cover presentation-model output for installer, preparation, ready, progress, integration, and failure states.
- The macOS lifecycle harness confirms one prominent setup action and the absence of nested panel or duplicate control-bar structures.
- Focused Swift tests and the full non-Windows-agent regression suite pass.
- The app bundle builds, installs, replaces, uninstalls, preserves application data, reinstalls, and launches.
- The installed app is visually checked at regular and minimum supported window sizes.
- Keyboard activation, VoiceOver labels, progress feedback, and settings/ISO discoverability are checked.
- Existing downloaded ISO media remains unchanged.

## Out of Scope

- Redesigning the installed app launcher or live Windows desktop.
- Changing Windows download sources or licensing consent.
- Changing VM provider selection, disk preparation, or guest-agent behavior.
- Claiming Parallels feature parity or hiding unsupported runtime limitations.
