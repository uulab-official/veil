# Veil Production Release Design

Date: 2026-09-14

## Objective

Deliver Veil as a production-quality Windows app runtime for supported Apple
Silicon Macs. A user should select a Windows app, let Veil start or resume the
local Windows 11 Arm runtime, and use the app in an independent macOS window
without managing the Windows desktop during normal use.

Production-ready means more than a successful build. A feature is promoted only
when its host, guest, protocol, harness, live Windows evidence, data-safety,
and distribution gates agree. Unsupported capabilities remain explicit and
include a practical alternative when one exists.

## Scope and non-goals

In scope:

- One-click start/resume, guest-agent readiness, app launch, HWND discovery,
  first-frame presentation, and bounded recovery.
- Independent macOS windows with focus, placement, resize, minimize/restore,
  close, reconnect, multiple-app, and same-app window behavior.
- Keyboard, Unicode/IME, mouse, clipboard, drag-and-drop, shared-folder-backed
  file transfer, notifications, and documented audio readiness.
- VM setup, diagnostics, suspend/resume, snapshots where the disk format
  supports them, and safe install/replacement/uninstall behavior.
- Developer ID/notarized distribution gates and clean-Mac installation evidence.
- Repeatable live evidence for Notepad, Calculator, and Paint workloads.

Explicitly not required for this release:

- High-performance 3D or advanced DirectX/game compatibility.
- x86 Windows OS emulation, Intel Macs, or a cloud VM backend.
- USB passthrough, bridged networking, printer/scanner, or smart-card support
  where the platform prerequisite is unavailable. These must report the reason
  and working alternative rather than pretending to work.

## Product architecture

### Unified readiness contract

`WindowsRuntimeReadiness` is the product-facing projection of runtime state.
It consumes the VM snapshot, persisted install evidence, live agent health,
display evidence, and launch intent. Booting, waiting for the agent, waiting
for a first frame, stalled boot, repairable connection, and terminal failure
are distinct states with one primary action each.

The 180-second blank/unknown-console threshold is shared by the dashboard,
one-click launch coordinator, and runtime view. Before the threshold, the
product waits without reinstalling the guest agent. After it, the product
offers capture, safe stop, and retry; agent repair is not suggested until the
boot/display problem is separated from guest connectivity.

### Launch orchestration

The launch coordinator owns one idempotent operation per requested app. It
queues intent, starts or resumes Windows, waits for live health, refreshes
runtime evidence after every failed wait, launches or fulfills the app, waits
for a current first frame, and performs at most the configured recovery budget.
Cancellation reaches the owned task and prevents new guest commands after an
async boundary. Duplicate clicks coalesce without allowing a stale completion
to clear another launch's ownership.

### Host/guest boundaries

- `apps/mac-host` owns AppKit/SwiftUI presentation, VM provider lifecycle,
  launch orchestration, input routing, clipboard, and privacy-safe evidence.
- `apps/windows-agent` owns app discovery/launch, HWND lifecycle, capture,
  guest-side resize and DPI decisions, input, clipboard, notification, and
  shared-folder adapters.
- `packages/protocol` is the source of stable message names, validation, and
  compatibility rules. Shape changes update docs, fixtures, validators, and
  both language test suites together.
- `harness` validates reports and VM-free behavior. It never upgrades a fake
  result into live Windows evidence.

The host uses a durable control/event connection and an independent binary
frame connection. Commands that can fail use bounded acknowledgements or typed
errors; ordering is preserved per window and for the global clipboard lane.

### Evidence and recovery

Every runtime attempt records a stable phase, start time, outcome category,
and next action. Evidence bundles exclude Windows media, product keys,
signing secrets, clipboard contents, and user documents. Recovery is bounded,
re-checks current state before acting, and never performs destructive disk
operations automatically.

## Release tracks and exit criteria

### Track A — Runtime reliability

Exit only when a prepared or suspended VM can complete the one-click Notepad
path in a real Windows 11 Arm guest, including first frame, input, clipboard,
close, reconnect, and one recovery scenario. A failed stage must show one
safe actionable next step.

### Track B — Coherence windows

Exit only when live evidence covers independent windows for Notepad,
Calculator, and Paint, including same-app second windows, focus, minimize/
restore, resize, close, reconnect, Retina scaling, and no background focus
stealing or hidden-window frame waste.

### Track C — Daily-use bridges

Exit only when live evidence covers Korean/Unicode input, bidirectional
clipboard, shared-folder read/write, path-based file drop, notifications, and
audio readiness. Large files use the shared folder instead of base64 on the
control channel; unsupported paths are rejected with a useful explanation.

### Track D — Distribution and safety

Exit only when a Developer ID signed, notarized, stapled build passes Gatekeeper
on a separate supported Mac. Install, guarded replacement, uninstall,
reinstall, update/rollback, VM data preservation, diagnostics export, and
loopback-only service binding are recorded as release evidence.

### Track E — Performance and soak

Exit only when the reference Mac, macOS version, Windows build, VM resources,
and workload are recorded with measurements for typing, idle, scrolling, and
three concurrent windows. The release gate tracks P50/P95 first-frame and
input-to-visible-pixel latency, capture/encode bandwidth, host CPU, and memory
growth over a 30-minute soak.

## Verification ladder

1. Swift/C# unit tests cover state transitions, cancellation, bounds, input,
   rate limits, recovery budgets, and data-safety rules.
2. Protocol fixtures and validators agree across host, guest, and harness.
3. VM-free integration proves launch ordering, HWND ownership, frame routing,
   input, clipboard, reconnect, and recovery.
4. Live Windows E2E proves the applicable release track with fixed-name,
   privacy-safe evidence tied to commit and build identity.
5. A clean-Mac notarized release pass proves installation and daily use outside
   the development machine.

No UI, README, roadmap, or release note may call a feature `verified` or
`production-ready` until the corresponding live and distribution evidence
exists. Deterministic tests prove behavior; they do not substitute for a real
Windows guest.

## Delivery order

1. Finish the shared readiness projection and state/action consistency,
   including stalled-boot presentation and recovery tests.
2. Close install/update/rollback, diagnostics privacy, and signed-release
   gates without touching user VM data.
3. Move large file drops onto the shared-folder path and complete live
   clipboard, Unicode, notifications, and audio evidence.
4. Run the multi-app, suspend/resume, snapshot, and performance/soak gates on
   the reference Windows guest.
5. Publish only the notarized build whose evidence bundle and release checklist
   validate successfully.

Each delivery order item is a separate change set across the relevant
host/guest/protocol/harness boundaries. Existing working-tree changes remain
preserved; no Windows image, product key, proprietary SDK, or Parallels asset
is added.

## Known release blockers

- A long-lived local QEMU/HVF run can remain at Windows Boot Manager or a blank
  console while the forwarded agent port is open but health times out. The
  product now exposes this as stalled boot; the live fix and evidence remain
  open.
- Developer ID/notarization and a clean second-Mac run require credentials and
  hardware outside this repository.
- Shared-folder throughput, suspend/resume data preservation, DPI matching,
  audio, and multi-window soak still require real Windows evidence.

