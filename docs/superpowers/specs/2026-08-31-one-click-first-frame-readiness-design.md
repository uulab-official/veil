# One-Click First-Frame Readiness Design

Date: 2026-08-31

## Intent

Veil must not report a Windows app as opened merely because the guest accepted the launch and returned an HWND. The one-click path succeeds only when the host has received a frame it can render and is ready to present the Windows app as a macOS window.

This change closes the gap between the current launch coordinator and the P0 product contract:

```text
Select app
-> start or resume Windows
-> connect or repair the guest agent
-> launch the app and observe its HWND
-> receive a renderable first frame
-> present one macOS window
```

## Scope

This slice changes only the macOS host shell and its deterministic tests. It does not change protocol messages, the Windows agent, harness fixtures, VM boot behavior, or the user's in-progress protocol acknowledgement work.

The implementation extends the existing `OneClickAppLaunchCoordinator`; it does not introduce a second launch state machine or broadly refactor `VeilHostShellApp`.

## Current Gap

`OneClickAppLaunchCoordinator` currently returns `.opened` as soon as `launchSelectedApp` or `fulfillPendingLaunch` returns a `WindowsAppLaunchResult`. `VeilHostShellApp` then presents an `NSWindow` immediately. Frame delivery is asynchronous, so a successful guest launch can produce a blank host window whose first frame never arrives.

The model already tracks frame subscription time, frame timing, composited frame generation, and the eight-second first-frame timeout. The missing boundary is the launch coordinator treating that evidence as part of launch completion.

## Architecture

The existing one-click coordinator remains the sole owner of the user-initiated launch sequence:

```text
request launch intent
-> start or resume runtime when needed
-> wait for the guest agent
-> recover the stalled runtime at most once
-> repair the guest agent at most twice
-> fulfill the queued app launch
-> wait for a renderable first frame
-> restart the frame subscription at most once
-> wait for a renderable frame again
-> return opened or a typed failure
```

`OneClickAppLaunchDriver` gains host-shell closures for first-frame readiness, frame-stream recovery, and stage reporting. The coordinator remains generic over the launch result; the driver knows how to resolve that result to a window ID and how to inspect the active mirror session.

`VeilHostShellApp` does not call `showWindowsAppWindow` until the coordinator returns `.opened`. During frame waiting or recovery, the main launcher remains visible.

## First-Frame Readiness

A first frame is ready only when the active mirror session contains displayable evidence:

- A legacy full-frame PNG must contain payload data that AppKit can decode as an image.
- A binary/composited frame must have a compositor surface available for the window.
- A session whose capture state is unavailable is not ready.
- Timing metadata or an unchanged-frame heartbeat alone does not satisfy readiness.

The readiness check belongs in a small host-shell policy with pure, testable decisions. Pixel ownership remains in `HostDashboardModel` and `WindowFrameCompositor`; the policy only determines whether the existing evidence is renderable.

The first wait uses the existing eight-second first-frame threshold. If no renderable frame arrives, Veil restarts that window's frame subscription once and waits for one more bounded interval. The launch path never performs an unbounded frame retry.

## Progress Reporting

The coordinator reports typed stages to the shell:

- preparing the selected app,
- starting or resuming Windows,
- connecting the Windows app bridge,
- recovering the runtime connection,
- repairing the guest agent,
- opening the Windows app,
- waiting for the app screen,
- restarting the app screen,
- ready.

The shell converts stages to product-facing copy using the selected app name. It exposes the current message on the existing launcher surface rather than adding a new navigation path or a diagnostic panel.

## Error Handling

Existing launch failures remain distinct: unavailable endpoint, incomplete runtime setup, runtime start failure, exhausted agent recovery, guest launch rejection, and transition-budget exhaustion.

The coordinator adds first-frame failures:

- `captureUnavailable`: the guest connection cannot provide a mirrored app screen.
- `firstFrameRecoveryFailed`: the initial frame timed out and the subscription could not be restarted.
- `firstFrameRecoveryExhausted`: no renderable frame arrived after the one allowed restart.

These failures do not present a blank macOS window and do not hide the launcher. The existing mirror session remains available to the frame-liveness status machinery, which can expose `restart-frame-subscription`, `recover-window-capture`, or `reopen-windows-app` as the next action. No VM stop, disk mutation, or destructive recovery occurs.

If a renderable frame arrives while recovery is being evaluated, the coordinator rechecks readiness before acting so delayed success does not trigger a duplicate restart.

## Concurrency And Idempotency

`OneClickAppLaunchTaskGate` continues to coalesce repeated clicks into the active launch task. The first-frame wait and recovery are inside that gated task, so a second click cannot create another VM start, guest launch, frame subscription, or macOS window.

Automatic background frame maintenance must not race the active first-frame gate for the same window. The shell marks the launch window as actively awaiting readiness and excludes it from automatic maintenance until the gated launch completes. Manual recovery remains available after a typed launch failure.

## Testing

Host-shell tests cover:

1. A stopped VM queues the app, starts Windows, connects the agent, launches the app, receives a frame, and opens once.
2. An already connected guest still waits for its first renderable frame.
3. An initial timeout restarts the frame subscription once, receives a frame, and succeeds.
4. A restart failure returns `firstFrameRecoveryFailed` without reporting success.
5. A second timeout returns `firstFrameRecoveryExhausted` without presenting a window.
6. Capture-unavailable sessions return `captureUnavailable`.
7. A delayed frame that arrives before recovery is rechecked prevents an unnecessary restart.
8. Duplicate clicks join the same gated launch through first-frame readiness.
9. Reported stages follow the actual launch and recovery order.
10. Existing runtime, agent-repair, transition-budget, and route tests remain green.

Verification commands:

```sh
swift test --package-path apps/mac-host --filter OneClickAppLaunchCoordinatorTests
swift test --package-path apps/mac-host
swift build --package-path apps/mac-host --product veil-host-shell
git diff --check
```

## Acceptance Criteria

- A one-click launch does not present a macOS app window before a renderable first frame exists.
- A first-frame timeout performs no more than one subscription restart.
- A failed frame path leaves the launcher visible with a specific recovery outcome.
- Repeated clicks do not duplicate runtime, guest launch, frame recovery, or window presentation work.
- The launcher communicates the active stage without exposing QEMU, HWND, or protocol terminology in its primary copy.
- The implementation does not modify protocol shapes or overwrite the user's existing working-tree changes.
