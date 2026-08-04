# App-First Windows Home

Date: 2026-08-04
Status: Approved direction; ready for implementation planning

## Purpose

Make the installed-Windows experience feel like a native Mac app launcher instead of a VM dashboard. After setup, Veil should lead with Windows applications. The full Windows desktop remains available as an explicit secondary destination for recovery or tasks that cannot run in a mirrored app window.

## Scope

This iteration redesigns the installed launcher in the macOS host shell. It changes the default display choice, launcher hierarchy, app selection feedback, responsive layout, and installed-state source contracts. It does not change VM boot, guest-agent discovery, app-launch protocol messages, mirrored HWND windows, Windows installation, download behavior, or settings functionality.

## Product Principles

- The normal path is “open a Windows app,” not “open a VM.”
- A ready launcher shows applications before machine identity or engineering status.
- One user action has visual priority at a time.
- Status is contextual: healthy details stay quiet; waiting and failure guidance appear only when useful.
- The Windows desktop never replaces the launcher without an explicit user action.
- Veil must not imply that unsupported or unverified behavior is working.

## Default Navigation

When installed Windows is available and no mirrored Windows app window is foregrounded, the main window opens to the app home. `showsWindowsDesktop` defaults to `false` and returns to `false` after the runtime stops or the installed profile is replaced.

The user can select `Windows Desktop` from a quiet top-right action. While the desktop is visible, a single `Show Apps` action returns to the app home. Existing display-selection policy still chooses the real native or captured VM surface; the redesign only changes when that surface is requested.

Opening a Windows app keeps the current behavior: Veil starts or resumes Windows as needed, queues the app until the guest agent connects, and presents the resulting HWND in a native macOS window. It does not expose the full desktop during that transition.

## App Home Layout

The content below the persistent shell header is one edge-to-edge home canvas. It must not contain a monitor bezel, nested card, centered Windows 11 hero, permanent progress-card strip, or duplicate bottom dock.

The canvas has three regions:

1. A compact heading with `Windows Apps` and one contextual sentence.
2. An adaptive grid of installed application tiles as the primary surface.
3. Quiet top-right actions for `Windows Desktop`, settings, and overflow actions already supported by the shell.

At regular sizes, the grid is centered in a readable maximum width with generous spacing. At the supported `820 x 560` minimum, tile width and spacing compress before content clips. If the catalog exceeds available height, only the app region scrolls; the heading and global actions remain stable.

## App Tiles

Each tile uses the discovered application icon when available and a deterministic fallback symbol otherwise. It shows the product-facing app name and, only when relevant, a short secondary state such as `Opening…` or `2 windows`.

The whole tile is one button with a clear hover, pressed, keyboard-focus, and disabled state. Activating a ready tile immediately routes through the existing app-launch closure. Activating the same tile while its launch is queued must not enqueue a duplicate request.

The selected or queued tile displays local progress without blocking other launchable apps unless the runtime model already requires global serialization. Open-window counts remain visible but subdued. Technical executable paths, HWND values, provider names, and protocol state never appear on the home canvas.

## State Presentation

The home derives one of these presentation states from existing runtime and guest-agent evidence:

- **Ready:** show the app grid and a quiet `Ready` description. Do not show a success banner.
- **Runtime stopped:** keep the app grid enabled. Selecting an app starts or resumes Windows through the current queued-launch path.
- **Starting or reconnecting:** keep the grid visible, mark the queued app `Opening…`, and show one compact contextual status line.
- **Agent unavailable with recoverable runtime:** keep app identity visible, disable unsafe duplicate actions, and show one inline recovery action.
- **Catalog unavailable:** replace the grid region with a concise empty or loading state and one appropriate retry action.
- **Failure:** show a short product-facing error and one primary recovery action. Put technical detail behind diagnostics or settings.
- **Desktop visible:** replace the app home with the selected real Windows display and expose only `Show Apps` plus essential display controls.

Healthy state must not repeat the header status badge. Waiting, recovery, and failure messages are mutually exclusive so the canvas never accumulates multiple status rows.

## Presentation Architecture

Add a small, pure value-type presentation model for the installed app home. It resolves:

- home phase;
- title and detail copy;
- whether the grid is interactive;
- queued app identifier and tile status;
- recovery action visibility and label;
- desktop and settings action visibility.

The resolver consumes existing snapshot, app catalog, queued launch, open-window counts, and error evidence. It performs no file, network, VM, or agent operation and is independently unit tested.

SwiftUI composition should separate the home canvas, adaptive app grid, app tile, and contextual status. Existing closures remain responsible for launching apps, selecting the desktop, opening settings, and invoking recovery. The old bottom `WindowsQuickLaunchPanel` and installed `AppRuntimeProgressStrip` are removed after their behavior has a replacement.

## Error Handling

Known errors use concise language such as `Windows could not start` or `Windows apps are not responding`. Raw QEMU output, local paths, provider identifiers, protocol payloads, and stack details remain in diagnostics.

If app discovery has never succeeded, the canvas must not fabricate Notepad, Calculator, Paint, or readiness. A loading state may preserve the last known catalog only when existing model evidence already treats that catalog as valid. Recovery actions must call existing executable routes rather than decorative controls.

## Accessibility and Input

The home title is a semantic heading. Each tile has an accessibility label containing the app name and an accessibility value for queued or open-window state. Desktop, settings, retry, and diagnostics icon controls have explicit labels and pointer help.

Keyboard users can traverse tiles in reading order and activate them with standard button behavior. Focus remains on the activated tile while launch state changes. Motion is limited to short opacity, scale, or progress transitions and does not use infinite decorative animation.

## Verification

Implementation is complete when:

- Unit tests cover ready, stopped, queued, reconnecting, unavailable-catalog, recoverable failure, and desktop-visible presentation states.
- Tests prove the installed launcher defaults to app home and the desktop appears only after explicit selection.
- Source contracts prove the centered Windows hero, duplicate bottom app dock, and permanent progress strip are absent from the normal installed home.
- Existing app launch, queued launch, open-window count, desktop display selection, and settings routes remain executable.
- Focused Swift tests, macOS lifecycle tests, and the full Swift suite pass.
- The app bundle builds, replaces the installed copy, launches, uninstalls, reinstalls, and launches again without deleting application-support data or the existing Windows ISO.
- The installed app is visually checked at regular size and `820 x 560`, including ready, queued, error, and desktop-return states that can be reproduced safely.
- Keyboard focus, VoiceOver labels, tile hover/pressed states, scrolling, and long app names are checked.

## Out of Scope

- Claiming Parallels feature parity.
- Changing Windows ISO acquisition, installation, licensing, or guest-agent setup.
- Changing protocol message shapes or Windows agent behavior.
- Implementing new Windows applications, Start menu emulation, snapshots, USB, audio, printers, or file sharing.
- Replacing the actual native or captured Windows desktop renderer.
