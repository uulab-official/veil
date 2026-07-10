# Host/Guest Protocol

## MVP Transport

```text
WebSocket
Default guest port: 18444
Encoding: UTF-8 JSON for control messages
Frame payloads: separate stream or base64 only for early harness spikes
```

The protocol must remain testable without a real VM. Every stable message should have a fixture in `harness/protocol-fixtures`.

Executable protocol helpers live in `packages/protocol`. Harness tools should import that package instead of duplicating message type strings or structured error shapes.

## Envelope

```json
{
  "type": "agent.health.request",
  "requestId": "req_001",
  "protocolVersion": 1
}
```

Rules:

- `type` is required.
- `requestId` is required for request/response messages.
- Events do not require `requestId`.
- Unknown message types must return a structured error.

## Health

Request:

```json
{
  "type": "agent.health.request",
  "requestId": "req_001",
  "protocolVersion": 1
}
```

Response:

```json
{
  "type": "agent.health.response",
  "requestId": "req_001",
  "protocolVersion": 1,
  "agentVersion": "0.1.0",
  "os": "windows-arm64",
  "session": {
    "interactive": true,
    "user": "veil-user"
  },
  "capabilities": {
    "appList": true,
    "appLaunch": true,
    "windowTracking": true,
    "windowCapture": true,
    "input": true,
    "clipboardText": true,
    "packageIdentity": false
  },
  "packageIdentityStatus": {
    "statusPath": "C:\\Users\\veil\\AppData\\Local\\Veil\\Agent\\package\\sparse-package-status.json",
    "stage": "packageSigned",
    "succeeded": false,
    "message": "SignTool signed the sparse identity package.",
    "updatedAt": "2026-07-10T05:40:00.0000000+09:00",
    "packagePath": "C:\\Users\\veil\\AppData\\Local\\Veil\\Agent\\package\\VeilAgent.Identity.msix",
    "certificatePath": "C:\\Users\\veil\\AppData\\Local\\Veil\\Agent\\package\\VeilAgent.Identity.cer"
  },
  "notificationListener": {
    "isSupported": true,
    "canListen": false,
    "accessStatus": "packageIdentityRequired",
    "recommendedAction": "prepare-sparse-package",
    "requiresPackageIdentity": true
  }
}
```

`capabilities.packageIdentity` is `true` only when the Windows agent is running
with Windows package identity. The agent reads this from Windows' app model
package identity API at runtime, so default unpackaged installs report `false`.
Veil uses this readiness signal before enabling package-gated Windows APIs such
as borderless Windows Graphics Capture and Windows notification listener
integration.

`packageIdentityStatus` is optional. When `%LOCALAPPDATA%\Veil\Agent\package\sparse-package-status.json`
exists in the guest, the agent includes a sanitized summary so the host can show
whether sparse package preparation has not run, failed, or reached a later
stage. The object must not include certificate passwords or PFX private-key
contents; it only carries paths, the latest stage, success state, and a human
failure/progress message.

`notificationListener` is optional for backwards compatibility. Current agents
include it so the host can distinguish the sparse-package prerequisite from the
Windows `UserNotificationListener` consent state. `canListen=true` means the
agent can start the package-gated listener and the next proof step is
`run-notification-proof`; otherwise `recommendedAction` names the specific
blocker, such as `prepare-sparse-package`,
`request-notification-listener-consent`, or
`enable-notification-listener-settings`.

## App List

Request:

```json
{
  "type": "app.list.request",
  "requestId": "req_002",
  "protocolVersion": 1
}
```

Response:

```json
{
  "type": "app.list.response",
  "requestId": "req_002",
  "apps": [
    {
      "id": "winapp_notepad",
      "name": "Notepad",
      "exePath": "C:\\Windows\\System32\\notepad.exe",
      "publisher": "Microsoft",
      "iconId": "icon_notepad",
      "iconPngBase64": "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQ...(base64 PNG)"
    },
    {
      "id": "winapp_calculator",
      "name": "Calculator",
      "exePath": "calc.exe",
      "publisher": "Microsoft",
      "iconId": "icon_calculator",
      "iconPngBase64": null
    },
    {
      "id": "winapp_paint",
      "name": "Paint",
      "exePath": "mspaint.exe",
      "publisher": "Microsoft",
      "iconId": "icon_paint",
      "iconPngBase64": null
    }
  ]
}
```

`iconPngBase64` is the app's real Windows icon (extracted from the executable,
`WindowsAppIconExtractor` on the guest), base64-encoded PNG. It is `null` when
the guest could not resolve the executable's real path or extraction failed
for any reason (e.g. running in demo mode, or the executable is missing) --
host clients must fall back to a generic icon in that case, not treat a
missing icon as an error. Icons are extracted once per app id and cached on
the guest, since they never change at runtime; expect this field on every
`app.list.response`, not on a separate per-app request. Packaged apps whose
primary executable is only a launcher stub (e.g. Calculator) resolve the icon
from the app's alternate executable names before falling back to no icon.

## App Launch

Request:

```json
{
  "type": "app.launch.request",
  "requestId": "req_003",
  "appId": "winapp_calculator",
  "args": []
}
```

Response:

```json
{
  "type": "app.launch.response",
  "requestId": "req_003",
  "accepted": true,
  "processId": 4912
}
```

Rules:

- `appId` must be one of the IDs returned by the latest `app.list.response`.
- `app.launch.response.processId` must match the subsequent `window.created.processId`.
- `window.created.appId` identifies the launched app; the launch/window acceptance contract is not Notepad-specific.

## File Open (Drag and Drop)

Request:

```json
{
  "type": "file.open.request",
  "requestId": "req_006",
  "appId": "winapp_notepad",
  "fileName": "hello.txt",
  "contentBase64": "SGVsbG8gZnJvbSBtYWNPUw=="
}
```

Response:

```json
{
  "type": "file.open.response",
  "requestId": "req_006",
  "accepted": true,
  "processId": 4931
}
```

Rules:

- `appId` must be one of the IDs returned by the latest `app.list.response`.
- `fileName` must be a bare file name with no path separators, no `.`/`..` traversal, and not a
  reserved Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1`-`COM9`, `LPT1`-`LPT9`, with or
  without an extension) -- the host never gets to choose where inside the guest filesystem this
  ends up, only what it's named. The guest writes it into a fixed, agent-controlled temp directory
  under a fresh random subfolder per request (so concurrent drops with the same file name never
  collide), and deletes that subfolder a few minutes later regardless of whether the launch
  succeeded, so repeated drops don't accumulate on the guest disk indefinitely.
- `contentBase64` is the full file content, base64-encoded, sent directly over the existing
  WebSocket control channel rather than through a separate shared folder or filesystem mount --
  there is no live/writable host-guest filesystem share (the `Veil Guest Agent` install media is a
  one-time read-only ISO snapshot baked at `veil-vmctl prepare` time, not a runtime mount), so this
  is the only channel available without adding new QEMU-level infrastructure (virtio-9p or an SMB
  share). The guest rejects decoded content over 50 MB.
- On success, `file.open.response` is followed by a `window.created` event the same way
  `app.launch.response` is -- the app is launched with the written file path as its command-line
  argument, so it opens the dropped file's content directly rather than starting blank.
- On failure the guest returns a structured `error` instead, with no `window.created`: `app_not_found`
  (unknown `appId`), `invalid_file_name` (unsafe or reserved `fileName`), `file_decode_failed`
  (`contentBase64` isn't valid base64, or decodes to empty content), `file_too_large` (over 50 MB),
  `file_write_failed`, or `file_open_failed` (the launch itself failed).

## Window Created

Event:

```json
{
  "type": "window.created",
  "windowId": "hwnd:0003029A",
  "processId": 4912,
  "appId": "winapp_notepad",
  "title": "Untitled - Notepad",
  "bounds": {
    "x": 10,
    "y": 10,
    "width": 1280,
    "height": 800
  },
  "state": "normal",
  "focused": true
}
```

Rules:

- `window.created` can arrive as part of a host launch response or as an async guest lifecycle event.
- The host tracks the HWND, opens a macOS mirror window, persists the app for reconnect restore, and subscribes to frame capture when the connected agent advertises `windowCapture`.

## Window Updated

Event:

```json
{
  "type": "window.updated",
  "windowId": "hwnd:0003029A",
  "processId": 4912,
  "appId": "winapp_notepad",
  "title": "Notes.txt - Notepad",
  "bounds": {
    "x": 20,
    "y": 24,
    "width": 1360,
    "height": 860
  },
  "state": "normal",
  "focused": true
}
```

Rules:

- `window.updated` must refer to a tracked HWND.
- The host updates title, bounds, state, and focus metadata without resetting the current frame stream or timing evidence.

## Window Frame

Early harness event from guest to host:

```json
{
  "type": "window.frame",
  "windowId": "hwnd:0003029A",
  "frameId": "frame_000001",
  "sequence": 1,
  "format": "png",
  "width": 1,
  "height": 1,
  "scale": 1,
  "encodedData": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB..."
}
```

Rules:

- `windowId` must match a tracked `window.created` event.
- `sequence` is monotonically increasing per window.
- `format` is `png` for the first correctness harness.
- `encodedData` is base64 only for early harness spikes; production capture should move to a separate binary or media stream.
- `scale` is the window's real Windows DPI scale (`1` for 100%, `2` for 200%, etc), read via
  `GetDpiForWindow` once the guest process declares itself Per-Monitor-V2 DPI aware
  (`ProcessDpiAwareness.EnablePerMonitorV2`, called once at agent startup). This makes `width`/
  `height` reflect the window's true pixel resolution instead of a virtualized-96-DPI, blurry
  upscale of it -- host clients that render the frame at 1:1 pixel-to-point (as the current
  `resizable().scaledToFit()` mirror surface does) already benefit from the sharper source bitmap
  without needing to read `scale` themselves; it's exposed for future consumers that want to size
  a view precisely rather than let it stretch to fit.

## Window Frame Stream Control

Host request to start a frame stream for one tracked HWND:

```json
{
  "type": "window.frame.subscribe",
  "requestId": "req_frame_subscribe_notepad",
  "windowId": "hwnd:0003029A",
  "format": "png"
}
```

Host request to stop that HWND frame stream:

```json
{
  "type": "window.frame.unsubscribe",
  "requestId": "req_frame_unsubscribe_notepad",
  "windowId": "hwnd:0003029A"
}
```

Rules:

- `windowId` must reference a tracked `window.created` event.
- `format` is `png` for the first stream control implementation.
- These requests do not require a success response. Invalid requests may still return structured errors.
- The macOS host subscribes after launching a capture-capable app window and unsubscribes before closing the mirrored window.
- Host-side app-runtime status records frame stream recovery evidence per HWND:
  `frameStreamRequestedAt`, `frameStreamWaitingAgeMilliseconds`,
  `frameStreamRestartCount`, `latestFrameStreamRestartedAt`, and
  `frameStreamRecoveryEscalated`/`frameStreamReopenEscalated`. Aggregate
  `macWindowIntegration` status also reports `frameLatencyHealth`, the 1 second
  fresh-frame budget, the 5 second stale-frame timeout, the slowest app-screen
  window, and the next aggregate latency action. A restart is an unsubscribe
  followed by a new subscribe. If no frame arrives within 8 seconds of
  `frameStreamRequestedAt`, the host treats the still-pending stream as `stale`
  and routes it through the same maintenance path as an old latest frame. After
  two restart attempts on the same HWND still lead to a stale stream, the host reports
  `frameStreamRecommendedAction=recover-window-capture` instead of repeatedly
  recommending another subscription restart. The host-side
  `recover-window-capture` action focuses the HWND through the guest agent, then
  performs a fresh unsubscribe/subscribe cycle and records the recovered HWND in
  `recoveredFrameWindowIds`. If that recovered HWND stalls again, the host
  reports `frameStreamRecommendedAction=reopen-windows-app` and exposes
  `reopen-window`; accepted reports record the stale HWND in
  `reopenRequestedWindowIds`, remove it from `mirrorSessions[]`, and record the
  newly opened app window in `reopenedWindows`. The combined
  `maintain-frame-streams` action runs the same priority order in one handoff:
  reopen any reopen-escalated app windows, recover any recovery-escalated
  streams, then restart ordinary stale subscriptions. The host shell also uses
  that combined action path for automatic app-screen maintenance while mirrored
  Windows app windows are open.
- Host-side proof artifacts reuse the same latency budget. `app-window-proof`
  includes `firstFrameLatency`; `coherence-proof` and embedded MVP coherence
  evidence include `initialFrameLatency` and `postInputFrameLatency`. Each
  latency object records `elapsedMilliseconds`, `freshFrameBudgetMilliseconds`,
  `staleFrameTimeoutMilliseconds`, freshness booleans, and the derived
  `recommendedAction` (`none`, `measure-again`, or `tune-frame-latency`).
  `app-runtime-status.proofArtifacts` parses the latest saved proof JSON and
  promotes the slowest proof latency as `latestProofLatencyHealth`,
  `latestProofSlowestLatencyMeasurement`,
  `latestProofSlowestLatencyMilliseconds`, the shared budget/timeout, and the
  matching recommended action. It also reports `latestProofsByApp` plus
  `multiAppProofTargetAppIds`, `multiAppProofCoverageCount`, and
  `multiAppProofCoverageHealth` so Notepad, Calculator, and Paint coverage is
  visible before claiming Daily Use quality. `veil-vmctl multi-app-proof`
  writes one saved Coherence proof per target app and an aggregate
  `windowsMultiAppProof` diagnostics report; it does not add a new guest
  protocol message, but it standardizes how automation fills the saved
  artifacts that status and review surfaces already consume.
- `app-runtime-status.proofPlan` exposes that coverage gate separately from the
  selected-app proof recommendation. `recommendedProofCommand` remains the
  strongest proof for the selected app, while
  `recommendedMultiAppProofCommand=veil-vmctl multi-app-proof --json --require-complete`
  is present only when the live agent can launch all Daily Use target apps and
  supports window capture, input, and clipboard.
- `app-runtime-action --action proof-multi-app` is the in-app/automation handoff
  for that same Daily Use gate. Its action report keeps the single-app `proof`
  field reserved for `proof-recommended` and returns the aggregate
  `windowsMultiAppProof` as `multiAppProof`.

## Window Focus

Host request:

```json
{
  "type": "window.focus.request",
  "requestId": "req_focus_notepad",
  "windowId": "hwnd:0003029A"
}
```

Guest response:

```json
{
  "type": "window.focus.response",
  "requestId": "req_focus_notepad",
  "windowId": "hwnd:0003029A",
  "accepted": true
}
```

Rules:

- `windowId` must match the HWND-shaped id from a tracked `window.created` event.
- On Windows, the first implementation restores the window and asks the OS to foreground/focus the target HWND.
- `accepted: true` means the focus request reached a tracked HWND and the platform focus call was accepted.
- `accepted: false` means the HWND is no longer tracked or the OS rejected the focus request; the host should still be able to bring the macOS mirror window forward for recovery.

## Window Close

Host request:

```json
{
  "type": "window.close.request",
  "requestId": "req_close_notepad",
  "windowId": "hwnd:0003029A"
}
```

Guest response:

```json
{
  "type": "window.close.response",
  "requestId": "req_close_notepad",
  "windowId": "hwnd:0003029A",
  "accepted": true
}
```

Guest lifecycle event:

```json
{
  "type": "window.closed",
  "windowId": "hwnd:0003029A"
}
```

Rules:

- `windowId` must match the HWND-shaped id from a tracked `window.created` event.
- On Windows, the first implementation maps this to `WM_CLOSE` for the target HWND.
- `accepted: true` means the close message was posted to the window.
- `accepted: false` means the HWND is no longer tracked or the OS rejected the close request; the host must not emit a synthetic `window.closed` event.
- `window.closed` tells the host to remove the tracked HWND, close the macOS mirror window without sending another close request, and forget the persisted restore intent for that app.

## Input Mouse

Event from host to guest:

```json
{
  "type": "input.mouse",
  "windowId": "hwnd:0003029A",
  "event": "leftDown",
  "x": 240,
  "y": 130,
  "modifiers": []
}
```

Allowed mouse events:

- `leftDown`
- `leftUp`
- `rightDown`
- `rightUp`
- `move`
- `scroll`

Implementation note: the first Windows agent implementation maps these host events to HWND `PostMessage` calls with client-area coordinates.

Rules:

- `windowId` must match the HWND-shaped id from a tracked `window.created` event.
- If the HWND is not tracked, the guest rejects the input with `window_not_tracked` and must not post mouse messages.

## Input Key

Event from host to guest:

```json
{
  "type": "input.key",
  "windowId": "hwnd:0003029A",
  "event": "keyDown",
  "key": "c",
  "windowsVirtualKey": 67,
  "modifiers": ["ctrl"]
}
```

The host maps macOS command shortcuts to Windows control shortcuts for app windows.

Implementation note: the first Windows agent implementation maps `input.key` to HWND `WM_KEYDOWN` and `WM_KEYUP` messages. Modifier entries such as `ctrl`, `shift`, and `alt` are posted around the key event.

Rules:

- `windowId` must match the HWND-shaped id from a tracked `window.created` event.
- If the HWND is not tracked, the guest rejects the input with `window_not_tracked` and must not post key messages.

## Clipboard Text

Host to guest:

```json
{
  "type": "clipboard.text.set",
  "requestId": "req_004",
  "origin": "host",
  "sequence": 42,
  "text": "hello from macOS"
}
```

Guest to host uses the same shape with `"origin": "guest"`.

Loop prevention rule:

- Receivers remember the latest `(origin, sequence)` pair.
- A clipboard update caused by a remote message must not be echoed back as a new local change.

Implementation note: the host syncs macOS text to the Windows guest before forwarded paste shortcuts. The Windows agent also observes text clipboard changes and broadcasts `clipboard.text.set` with `origin=guest`. The macOS host accepts only increasing guest sequences and writes them to the macOS pasteboard. Host-origin updates are consumed by the agent once so they are not echoed back as guest updates.

## Windows Notifications

Guest to host:

```json
{
  "type": "notification.received",
  "notificationId": "toast:winapp_notepad:0001",
  "appId": "winapp_notepad",
  "appName": "Notepad",
  "title": "Notepad",
  "body": "Autosaved Notes.txt",
  "receivedAt": "2026-07-10T12:15:00Z",
  "sourceAumid": "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"
}
```

Rules:

- `notificationId`, `title`, and `receivedAt` are required.
- `receivedAt` must be an ISO timestamp generated by the guest when it observes the Windows notification.
- `appId`, `appName`, `body`, and `sourceAumid` are optional because Windows notifications can come from apps Veil did not launch directly.
- The macOS host keeps only a short recent-notification window in app-runtime status and ignores duplicate `notificationId` values.
- The Windows agent notification streamer also drops duplicate `notificationId` values and notifications missing a non-empty title before broadcasting to host clients.
- Real guest emission requires the signed sparse package identity and Windows `UserNotificationListener` consent gate described by `dailyUseReadiness.notificationBridgeRecommendedAction`. The first agent adapter syncs current toast notifications and re-syncs on Windows notification changes; live proof still has to show that this path runs inside the signed package on the real guest.

## Error

```json
{
  "type": "error",
  "requestId": "req_003",
  "code": "app_not_found",
  "message": "No app exists for id winapp_unknown"
}
```
