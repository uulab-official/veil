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

Control-event stream:

- The host keeps a separate long-lived WebSocket for guest lifecycle, clipboard, notification, and JSON
  frame events. Request/response sockets remain short-lived so a large frame cannot become the reply to an
  input operation.
- The host bounds the undelivered control-event queue at 1,024 messages. If that queue overflows, the host
  ends the event stream with a reconnectable transport error instead of silently dropping a `window.closed`,
  clipboard, or notification event. Reconnection lets the normal liveness and discovery paths repair the
  remaining state; the binary frame channel has its own per-HWND overflow recovery.

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
    "windowResize": true,
    "displayResize": true,
    "virtioGpuDisplay": true,
    "systemShutdown": true,
    "binaryFrameChannel": true,
    "sharedFolder": true,
    "clipboardImage": true,
    "clipboardFiles": true,
    "packageIdentity": false
  },
  "sharedFolder": {
    "isSupported": true,
    "shareName": "VeilShared",
    "guestDirectoryPath": "C:\\VeilShared",
    "directoryExists": true,
    "isShared": false,
    "isWritable": false,
    "serverListening": true,
    "requiresElevation": true,
    "requiresCredentials": true,
    "shareCommand": "New-SmbShare -Name VeilShared -Path C:\\VeilShared -FullAccess $env:USERNAME",
    "recommendedAction": "create-share-elevated"
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

`agentVersion` is the agent's informational version. A bundle built for the Mac app carries a build
id after `+`, such as `0.1.0+3f9c2a1b7d04`; the same string is written to
`app\veil-agent-version.txt` in the bundle. The host treats a connected agent whose `agentVersion`
differs from the bundled one as outdated tools and offers to update them; an agent from before build
ids reports plain `0.1.0` and is outdated too. When the app carries no stamped bundle (a development
build made without the .NET SDK), Veil never calls the tools outdated.

`capabilities.windowResize` is optional for backwards compatibility. The host only enables the
mirrored-window resize affordance when it is explicitly `true`; an absent value means the connected
agent predates `window.resize.request`.

`capabilities.displayResize` is also optional. When `true`, the agent can apply a requested Windows
desktop monitor mode through the Win32 display API. Veil uses it only as a fallback after QEMU's
RFB `ExtendedDesktopSize` request is rejected or forwarded to the guest (QEMU result code 4); an absent
or false value keeps the confirmed guest framebuffer aspect-fit without stretching.

`capabilities.virtioGpuDisplay` is optional. `true` means Windows has the virtio-win VirtIO GPU DOD
display driver (`viogpudo`) installed for the VM's `virtio-gpu-pci` device, so the next cold boot can
attach `virtio-gpu-pci` alone instead of `ramfb` plus `virtio-gpu-pci`. `false` means it is not
installed, and an absent value means the agent predates the field; both keep the `ramfb` display.
The host applies a changed value only at the next cold boot, never to a suspended session, because
the device list is part of the machine a saved memory state belongs to. See
[docs/install-flow.md](install-flow.md) for why the two displays cannot stay attached together.

`capabilities.systemShutdown` is optional. `true` means the agent accepts `system.shutdown.request`;
an absent value means it predates the message, and the host uses the ACPI power button instead.

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
When present, `packageIdentityStatus.succeeded` must agree with
`capabilities.packageIdentity`: Veil must not present package identity as ready
while the latest sparse-package evidence says preparation is incomplete, or
present successful sparse-package evidence while the live agent is still running
without package identity.

`notificationListener` is optional for backwards compatibility. Current agents
include it so the host can distinguish the sparse-package prerequisite from the
Windows `UserNotificationListener` consent state. `canListen=true` means the
agent can start the package-gated listener and the next proof step is
`run-notification-proof`; it also requires live package identity. Otherwise
`recommendedAction` names the specific blocker, such as `prepare-sparse-package`,
`request-notification-listener-consent`, or
`enable-notification-listener-settings`.

`capabilities.sharedFolder` and the `sharedFolder` object are both optional, for
the same backwards-compatibility reason as `binaryFrameChannel`. The distinction
matters: an agent that predates the shared folder omits the capability, and the
host then reports that it **cannot confirm** the share rather than reporting that
the share is missing. Those are different problems with different fixes.

Reading `sharedFolder` from health is deliberately side-effect free. Health is
polled, so it must never create a folder or publish a share; `shared.folder.request`
is the message that prepares anything. See [Shared Folder](#shared-folder).

`frameCapture` is optional and diagnostic. It reports how long each step of a mirrored frame capture
took in the guest, so the host can see where frame time goes without reading guest logs:

```json
"frameCapture": {
  "strategy": "auto",
  "phases": {
    "capture": { "meanMilliseconds": 4.1, "maxMilliseconds": 31.0, "count": 812 },
    "copy": { "meanMilliseconds": 1.2, "maxMilliseconds": 6.4, "count": 812 },
    "diff": { "meanMilliseconds": 0.9, "maxMilliseconds": 3.3, "count": 812 },
    "encode": { "meanMilliseconds": 2.0, "maxMilliseconds": 9.8, "count": 344 },
    "changedTotal": { "meanMilliseconds": 8.3, "maxMilliseconds": 40.2, "count": 344 },
    "unchangedTotal": { "meanMilliseconds": 6.2, "maxMilliseconds": 35.1, "count": 468 }
  },
  "methods": { "screen": 790, "printWindow": 22 }
}
```

Means are exponentially weighted (factor 0.1), so they follow the current workload. `methods` counts
captures by method: `duplication` reads the desktop DWM already composed through DXGI Desktop
Duplication, `screen` copies the screen with GDI, `printWindow` asks the app to render itself. `strategy` is the method in force; see [Frame Capture Strategy](#frame-capture-strategy).
Hosts must not depend on the phase names, which may change with the capture code.

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
  "args": [],
  "reuseExistingWindow": true
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
- `reuseExistingWindow` defaults to `false` for backwards compatibility. Veil's
  first-party app-first launch and reconnect paths set it to `true`, so an ordinary
  open action reuses a matching visible guest HWND before creating a process.
  `false` is reserved for a future explicit new-window action and is not exposed by
  the pre-alpha shell.
- The guest serializes launch/reuse decisions per app. Concurrent requests for the
  same app re-check visible HWNDs after the first request completes, preventing a
  launch race from creating duplicate Windows processes.
- The guest silently tracks all matching pre-existing windows during reuse lookup,
  so its later discovery stream cannot surface them as duplicate macOS mirrors.
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
  WebSocket control channel. This is a one-shot copy, not a share: the file is written into a
  temporary guest directory and the app is launched with that path. It exists for the
  drag-and-drop-to-open interaction, where a copy is what the user means. The guest rejects decoded
  content over 50 MB.
- For anything larger, or for a folder both sides can read and write continuously, use the live
  shared folder instead (see [Shared Folder](#shared-folder)). It has no size cap. `file.open.request`
  was the only channel available before that existed, and the two are kept separate rather than one
  replacing the other, because opening a dropped file and sharing a folder are different actions.
- On success, `file.open.response` is followed by a `window.created` event the same way
  `app.launch.response` is -- the app is launched with the written file path as its command-line
  argument, so it opens the dropped file's content directly rather than starting blank.
- On failure the guest returns a structured `error` instead, with no `window.created`: `app_not_found`
  (unknown `appId`), `invalid_file_name` (unsafe or reserved `fileName`), `file_decode_failed`
  (`contentBase64` isn't valid base64, or decodes to empty content), `file_too_large` (over 50 MB),
  `file_write_failed`, or `file_open_failed` (the launch itself failed).
- `fileName` should be at most 160 UTF-16 code units. The guest writes
  `%TEMP%\VeilDroppedFiles\<32-char GUID>\<fileName>` against Windows' classic 259-usable-code-unit path
  limit, and the agent manifest declares no `longPathAware`, so the prefix leaves roughly 160 units for the
  name once a 20-character user name is allowed for. This matters because the two platforms disagree: macOS
  permits 255 bytes per path component, so a name that is legal on the Mac can exceed what the guest can
  write. The host shortens over-long names on character boundaries and keeps the extension rather than
  refusing them, since the guest copy is temporary. A host that skips that will get `file_write_failed`.
- The host also rewrites characters that are legal on macOS and forbidden on Windows (`< > : " \ | ? *` and
  control characters) and suffixes reserved device base names. This is a usability rewrite, not a security
  measure: the guest validates independently and remains the boundary. It exists because Finder stores a
  name it *displays* with `/` using `:` on disk, so an everyday name like `2026/08/12 report.txt` would
  otherwise be rejected for a reason invisible on the user's own machine.

### Shared-folder file open

`file.open.shared.request` opens a file that the host has already copied into the live guest-served share:

```json
{
  "type": "file.open.shared.request",
  "requestId": "req_open_shared_007",
  "appId": "winapp_notepad",
  "fileName": "large-report.txt",
  "guestPath": "C:\\VeilShared\\large-report.txt"
}
```

This is the large-file companion to `file.open.request`. It carries no file bytes on the control channel,
so the 50 MB drag-and-drop limit does not apply. The guest independently requires an absolute path below
the fixed `C:\\VeilShared` root and requires its final component to equal `fileName`; traversal, a different
share, and a mismatched name return `invalid_shared_file_path`. A missing file returns
`shared_file_missing`. Successful requests use the same `file.open.response` followed by `window.created`
contract as an ordinary drop.

## Window Geometry

Window `bounds`, frame surfaces, `input.mouse` coordinates, and `window.resize.request` sizes all describe
a window's visible frame (`DWMWA_EXTENDED_FRAME_BOUNDS`), not the outer rectangle `GetWindowRect`
returns. On Windows 10 and 11 the outer rectangle includes invisible resize borders, about 7 px at 100%
on the left, right, and bottom, that show whatever is behind the window; mirroring them put slivers of
other windows along a mirrored window's edges. The agent adds those borders back when it resizes.

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
- Several apps can be mirrored at once, each as its own macOS window, cascaded so a new window does not land exactly on top of an existing one. One macOS window per HWND is the invariant: frame events, window updates, and reconnect races all re-present the same session repeatedly and must never duplicate a window.
- Multiple windows of the **same** app are mirrored too, which is how a second document window appears. Since a second window of one app can only arrive from the async discovery stream, the host distinguishes two kinds of window it did not launch:
  - A window whose `appId` **already has a tracked window** in this session is adopted. The user opened the app, so the app opening another document window is it doing what they asked.
  - A window whose `appId` was **never opened** in this session is ignored. That is a leftover process or something Windows started on its own, and an unrequested window appearing on screen is worse than a missing one. The guest enumerates every tracked process after a reconnect, so this rule is what keeps discovery from materializing windows nobody asked for.
- An adopted window must have a non-empty title and non-zero bounds; an untitled or zero-sized top-level window is far more likely a tooltip, splash, or transient shell window than a document. The number of windows adopted per app is bounded, which limits guest-driven creation the host does not control rather than expressing a preference about how many windows a user may have.
- The host tracks explicit-launch HWNDs, persists its restore targets per app, and subscribes to frame capture when the connected agent advertises `windowCapture`. Restore issues one launch per app rather than replaying a window count, because a launch for an app that already owns a window reuses that HWND.

Popups carry two optional fields:

```json
{
  "type": "window.created",
  "windowId": "hwnd:000F0300",
  "processId": 4912,
  "appId": "winapp_paint",
  "title": "Popup Host",
  "bounds": { "x": 140, "y": 120, "width": 942, "height": 84 },
  "state": "normal",
  "focused": false,
  "popup": true,
  "ownerWindowId": "hwnd:000F0254"
}
```

- `popup: true` marks a window that another window owns and that has no title bar, such as Paint's text formatting bar, a menu, or a tooltip. Owned windows with a title bar, like a Save As dialog, and unowned windows that draw their own title bar, like Paint's main window, are not popups. Ordinary windows omit both fields.
- `ownerWindowId` names the owning window when Windows reports one.
- The host shows a popup as a borderless, transparent overlay at the same offset from its owner's top-left as in Windows, attached so it moves with the owner and never taking key focus from it. Popup windows are often larger than what they draw, and capture records the transparent part as black, so the host clears black that reaches the frame's edge and keeps black content enclosed by the popup.

Fixture: `harness/protocol-fixtures/window.created.popup.json`.

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

Example production-sized frame event from guest to host:

```json
{
  "type": "window.frame",
  "windowId": "hwnd:0003029A",
  "frameId": "frame_000001",
  "sequence": 1,
  "format": "png",
  "width": 600,
  "height": 393,
  "scale": 1,
  "encodedData": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB..."
}
```

Rules:

- `windowId` must match a tracked `window.created` event.
- `sequence` is monotonically increasing per window.
- `format` is `png` for the first correctness harness.
- `encodedData` is base64 only for early harness spikes; production capture should move to a separate binary or media stream.
- The guest must never substitute a synthetic 1x1 or placeholder image when HWND capture fails. It may emit `window.created` without an initial frame, then keep the live stream active. The host will mark a stream with no real frame as stale after its documented timeout and run restart, capture recovery, or app reopen actions.
- `scale` is the window's real Windows DPI scale (`1` for 100%, `2` for 200%, etc), read via
  `GetDpiForWindow` once the guest process declares itself Per-Monitor-V2 DPI aware
  (`ProcessDpiAwareness.EnablePerMonitorV2`, called once at agent startup). This makes `width`/
  `height` reflect the window's true pixel resolution instead of a virtualized-96-DPI, blurry
  upscale of it -- host clients that render the frame at 1:1 pixel-to-point (as the current
  `resizable().scaledToFit()` mirror surface does) already benefit from the sharper source bitmap
  without needing to read `scale` themselves; it's exposed for future consumers that want to size
  a view precisely rather than let it stretch to fit.

## Binary Frame Channel

Frames may be delivered as raw binary on a dedicated connection instead of as base64 inside JSON on the
control connection.

Why: base64 inflates every PNG by 33% before it leaves the guest, embedding it in JSON forces the host to
parse a multi-hundred-kilobyte document per frame to reach the image bytes, and sharing the control
connection puts a large frame in front of the next `input.key` on the same TCP stream. That last one is
the delay a user perceives as sluggish.

Negotiation:

- The agent advertises `agent.health.response.capabilities.binaryFrameChannel`. The field is optional; an
  agent that predates the channel omits it and the host keeps using the JSON frame path.
- A host that wants frames opens a second WebSocket to the same host and port with the path `/frames`.
  The guest routes by request path, so every existing connection keeps its current behavior.
- The frame channel is send-only. The guest reads from it solely to observe a close, so frames on it can
  never be confused with replies to a request.
- Control-channel clients keep receiving `window.frame` as JSON. Both paths can be active at once.

Message layout, network byte order throughout. Version 2 (`VFR2`) adds a dirty rectangle and a key-frame
flag; version 1 (`VFR1`) omits the flags byte and the rectangle fields and is read as a full-surface key
frame, so an agent caught mid-upgrade degrades to full frames rather than failing:

```text
offset  size  field                                 VFR1  VFR2
0       4     magic ("VFR1" or "VFR2")                y     y
4       1     payload format (1 = png, 2 = bgra-deflate)  y     y
-       1     flags (bit 0 = key frame)               -     y
-       2     window id byte count (uint16)           y     y
-       n     window id, UTF-8                        y     y
-       4     sequence (uint32)                       y     y
-       4     surface width in pixels (uint32)        y     y
-       4     surface height in pixels (uint32)       y     y
-       4     DPI scale in thousandths (uint32)       y     y
-       2     tile x (uint16)                         -     y
-       2     tile y (uint16)                         -     y
-       2     tile width (uint16)                     -     y
-       2     tile height (uint16)                    -     y
-       4     payload byte count (uint32)             y     y
-       m     payload                                 y     y
```

Tiles exist because a changed window otherwise re-encodes every pixel. Typing one character in a
1920x1080 window re-encodes 2 million pixels to deliver a caret and a glyph. The guest computes the
bounding rectangle of changed pixels and encodes only that region; the host keeps the authoritative
full-window surface and composites tiles into it.

Rules:

- Coordinates use a **top-left** origin, matching what Windows reports. A host rendering on a bottom-left
  origin must flip.
- The payload covers exactly the declared rectangle. A payload whose real dimensions disagree must be
  rejected, not scaled to fit, because scaling silently distorts the window.
- Payload format 1 is a PNG. Format 2, `bgra-deflate`, is the rectangle's pixels as 32-bit BGRA rows, top
  to bottom with no padding, compressed with raw deflate (RFC 1951); the alpha byte is ignored. It costs
  the guest a fraction of a PNG encode, which matters at 60 tiles a second, and is sent only for windows a
  host subscribed to with `"tileFormat": "bgra-deflate"`. A payload that does not inflate to exactly
  `width * height * 4` bytes is rejected like a mis-sized PNG.
- A **key frame's rectangle must cover the whole surface.** The host has nothing to composite onto until
  one arrives, so a partial key frame would leave undefined pixels with no way to detect it.
- The guest sends a key frame on the first capture of a stream, on any surface size change, and when the
  changed region covers most of the surface. That last case is both cheaper than a tile and resynchronizes
  a host that dropped an earlier tile.
- A tile that arrives before a key frame, or after a surface size change that has not been re-keyed, must
  be dropped and a key frame awaited. Compositing onto a mismatched or absent surface produces a
  plausible-looking but wrong window, which is much harder to diagnose than a window that visibly waits.
- A delta must have the next sequence number for that window. If a sequence is skipped or repeated, the
  host must discard that window's compositor base and wait for a key frame; applying a later delta would
  preserve the missing pixels as if they were current. Key frames reset the sequence base and may use any
  monotonically increasing stream sequence. A binary-channel host should restart only that window's
  subscription immediately, because a guest that keeps producing small dirty regions may never naturally
  emit the key frame needed to repair a missing delta.
- A dropped tile is **not** a received frame. Frame timing and the latency budget must not advance for an
  update that did not reach the screen, or a stalled surface would look healthy.
- Rejecting a decoded tile's image payload invalidates that window's compositor base. Further deltas
  cannot repair unknown missing pixels; a valid full-surface key frame is required. While awaiting that
  key frame, unchanged heartbeats do not advance host liveness, allowing stale-stream recovery to run.
  Other windows retain their independent surfaces and liveness.
- A valid JSON full-surface image can also restore a rejected binary stream's base. Its payload must
  decode and match the declared dimensions before clearing the recovery reason or advancing liveness;
  metadata alone is not recovery evidence.
- If a host cannot keep up with the binary channel and its bounded receive buffer overflows, it must not
  silently continue with a missing incremental tile. The host should reset that window's subscription so
  the guest's next stream begins with a fresh key frame; other mirrored windows remain independent.
- A host must coalesce concurrent recovery requests for the same window. An unsubscribe/subscribe pair has
  one owner per HWND; a second recovery request should wait for or yield to that owner rather than allowing
  an older completion to retire a newer stream.
- Legacy JSON `window.frame` subscribers always receive a self-contained full-surface frame. Tiles are
  only meaningful to a client that composites them. The guest pays for that extra full-surface encode only
  while a control-channel subscriber actually exists.
- The window id length is a **byte** count, not a character count. A multi-byte id would otherwise
  misplace every field after it.
- DPI scale travels as an integer thousandth rather than a float, so the format carries no floating point
  representation or endianness ambiguity. A scale of `0` is read as 100%, matching what a DPI-unaware
  guest reports.
- `frameId` is absent. It is `frame_%06d` derived from `sequence`, so a frame that arrives over this
  channel is indistinguishable downstream from one that arrived as JSON.
- Receivers must reject bad magic, an unsupported format byte, a truncated buffer, an empty payload, an
  implausible surface size, and a declared payload length that does not exactly match the remaining
  bytes. A declared length shorter than the buffer means the two sides disagree about framing, and
  ignoring the tail would hide that.
- One undecodable message must not freeze a mirrored window, but a persistent framing disagreement has to
  surface. The host tolerates a bounded number of consecutive decode failures before failing the channel
  and falling back to reconnecting.
- Frames delivered on this channel go through the host's ordinary frame path, so frame timing, staleness,
  latency budgets, proof artifacts, and rendering are all unaffected by which transport delivered them.

## Window Frame Unchanged

Guest to host:

```json
{
  "type": "window.frame.unchanged",
  "windowId": "hwnd:0003029A",
  "sequence": 42,
  "capturedAt": "2026-07-31T09:14:02Z"
}
```

Why this exists: the host derives frame-stream freshness from when the last frame arrived. A guest that
simply stopped re-sending identical pixels for a static window would therefore be marked `delayed`
after 1 second and `stale` after 5, escalating into `restart-frame-subscription`, then
`recover-window-capture`, then `reopen-windows-app`. **The host could not tell "nothing changed" apart
from "capture is broken",** so the guest was forced to encode and base64 a full-window PNG several
times a second forever just to prove it was alive.

Rules:

- `windowId` must reference a tracked `window.created` event.
- Carries no image payload. A heartbeat that includes `encodedData` is invalid.
- The host advances a separate `latestActivityAt` clock from this event and leaves
  `latestFrameReceivedAt` untouched. `frameStreamStatus` is derived from activity, while
  `latestFrameAgeMilliseconds` keeps meaning how old the displayed picture is, so the frame-latency
  budget and saved proof artifacts are unaffected.
- Ignored before the first real frame. A stream that has never produced an image stays
  `waitingForFirstFrame`; a heartbeat must never stand in for the first frame, or capture that never
  started would look healthy.
- App-runtime status reports `unchangedHeartbeatCount` and `latestActivityAgeMilliseconds` per mirrored
  window. A high heartbeat count beside a low `receivedFrameCount` is a healthy idle window.
- Absence of heartbeats still escalates. Heartbeats are the liveness signal, so a silent guest goes
  stale exactly as before.
- Guests that never send this event are unaffected: the host defaults `latestActivityAt` to the frame
  time, which reproduces the previous behavior exactly.

Implementation note: the guest compares the freshly captured pixel buffer against the previous one with
an exact byte comparison before encoding anything, and skips the PNG encode entirely when they match.
A hash is deliberately not used, because a collision would silently drop a real frame. A window resize
changes the buffer length and therefore always produces a full frame. Sampling cadence is adaptive:
fast while content changes, backing off while it is static, with the idle interval kept well inside the
host's stale threshold so backing off cannot itself trip recovery.

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
- `tileFormat` is optional. `bgra-deflate` asks for format 2 tiles on the binary frame channel for this
  window; omitted or unknown values keep PNG tiles, and agents that predate it ignore the field.
- Legacy agents do not require a success response. Agents advertising
  `operationAcks` return a matching positive acknowledgement after applying the
  stream-control operation, or a structured error (see Operation Acknowledgements).
- The macOS host subscribes after launching a capture-capable app window and unsubscribes before closing the mirrored window.
- Frames travel independently from request replies and may reach the host before
  it observes the subscription acknowledgement. The host resets frame readiness
  and discards the previous compositor surface **before** sending a new subscribe.
  A reply must never clear a newer frame. Binary delivery needs a fresh key frame;
  it cannot use a previous subscription's retained pixels as the base for a delta.
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

## Window Resize

Host request:

```json
{
  "type": "window.resize.request",
  "requestId": "req_resize_notepad",
  "windowId": "hwnd:0003029A",
  "width": 1440,
  "height": 900
}
```

Guest response:

```json
{
  "type": "window.resize.response",
  "requestId": "req_resize_notepad",
  "windowId": "hwnd:0003029A",
  "accepted": true,
  "bounds": {
    "x": 10,
    "y": 10,
    "width": 1440,
    "height": 900
  }
}
```

Rules:

- `width` and `height` are logical 96-DPI-equivalent units, matching the bounds in
  `window.created` and `window.updated`. Both must be between 320 and 8192, and their product must not
  exceed 32000000 pixels.
- The guest converts the logical size to physical pixels using the tracked HWND's current per-monitor DPI,
  then calls `SetWindowPos` without moving, activating, or reordering the window. This keeps a Retina Mac
  from requesting twice the intended Windows size.
- `accepted: true` includes the bounds that Windows actually applied. An app or Windows may clamp the size,
  so the host treats the following `window.updated` event as authoritative rather than assuming the request
  was exact.
- `accepted: false` means the HWND was no longer tracked or the platform rejected the resize; the response
  omits `bounds` and the host keeps the existing mirror geometry.
- The macOS host sends one request after `windowDidEndLiveResize`, not one per intermediate drag event.
  During the gesture the mirror remains aspect-correct; after the guest applies the size, its capture buffer
  changes and the next key frame resynchronizes the host compositor.

## Desktop Display Resize Fallback

Host request:

```json
{
  "type": "display.resize.request",
  "requestId": "req_display_resize_1920x1080",
  "width": 1920,
  "height": 1080
}
```

Guest response:

```json
{
  "type": "display.resize.response",
  "requestId": "req_display_resize_1920x1080",
  "accepted": true,
  "width": 1920,
  "height": 1080
}
```

Rules:

- Dimensions are physical desktop pixels, bounded to 640...3840 per axis and 8,294,400 total pixels.
- The guest calls `ChangeDisplaySettingsEx` for the active Windows desktop mode. A false response includes
  a short `reason` and does not change the host's current framebuffer geometry.
- When the active display adapter is the VirtIO GPU DOD driver and the size is not one of its listed modes,
  the guest sets the driver's custom mode through the driver's own `D3DKMTEscape` request (the one
  virtio-win's `viogpures.exe` uses) and calls `ChangeDisplaySettingsEx` again, stepping through a listed
  mode when Windows is already on the custom one. The driver pads the scanout width up to a multiple of 16,
  so the host requests 16-aligned widths.
- The RFB display path invokes this fallback after a QEMU `ExtendedDesktopSize` rejection, and after QEMU
  answers result code 4 ("request forwarded"): QEMU passed the size to `virtio-gpu`, and the VirtIO GPU
  driver lists it as a mode but does not switch to it on its own. A later successful RFB desktop-size response becomes authoritative
  and returns the display to normal dynamic mode.

## Guest Shutdown

Host request:

```json
{
  "type": "system.shutdown.request",
  "requestId": "req_system_shutdown_1"
}
```

Guest response:

```json
{
  "type": "system.shutdown.response",
  "requestId": "req_system_shutdown_1",
  "accepted": true
}
```

Rules:

- The host sends this when the user stops Windows and the agent reports `capabilities.systemShutdown`.
  Windows can leave the ACPI power button unanswered (observed on November 6, 2026 with a Korean
  Windows 11 Arm 26300 guest), and killing QEMU instead loses unsaved work and can interrupt updates
  Windows installs while shutting down.
- The agent starts `shutdown.exe /s /t 0` in the user's session and answers once it has started; a
  false response carries a short `reason`. Windows then closes apps and may install updates first, so
  the host waits for QEMU to exit rather than for a further message.
- The request carries no arguments, so it cannot run anything but a normal shutdown. The host already
  controls the VM's power, so the message gives it no new authority over the guest.

## Frame Capture Strategy

Diagnostic host request:

```json
{
  "type": "frame.capture.strategy.set",
  "requestId": "req_capture_strategy_1",
  "strategy": "screen"
}
```

`strategy` is `auto` (the default: read a fully visible, on-top window from DXGI Desktop Duplication,
falling back to a GDI screen copy if duplication is unavailable, and use `PrintWindow` otherwise),
`duplication`, `screen`, or `printWindow`. The agent answers with an `operation.ack`, or an
`error` with code `invalid_message` for any other value, and clears the `frameCapture` times in health so
they describe only the new method.

Rules:

- This exists to compare capture methods on a running guest. Normal hosts never send it, and the
  setting lasts only until the agent restarts.
- Forcing `screen` mirrors whatever covers the window on the guest screen, which is why `auto` uses it
  only for a fully visible window. Nothing beyond the guest's own screen is read, so it does not widen
  what the host can see.

## Operation Acknowledgements

For negotiated input delivery, the host adds a fresh `requestId` to each mouse,
key, or committed-text envelope. The guest echoes it in the acknowledgement.
Legacy input events may still omit it; see
`harness/protocol-fixtures/input.text.acknowledged.json` for the negotiated form.

An agent may advertise `capabilities.operationAcks: true` in its health response.
After this negotiation, `input.mouse`, `input.key`, `input.text`,
`clipboard.text.set`, `clipboard.image.set`, `clipboard.files.set`, `window.frame.subscribe`, and
`window.frame.unsubscribe` receive one success acknowledgement or a structured `error` reply:

```json
{
  "type": "operation.ack",
  "requestId": "req_clipboard_42",
  "accepted": true
}
```

The host must match `requestId`, require `accepted: true`, and bound its reply
wait. A timeout, malformed reply, unrelated request ID, or negative acknowledgement
does not prove delivery. In particular, the host must not send a paste shortcut
after an unconfirmed clipboard write, since that could paste stale guest text.
It must not automatically retry an uncertain input operation, which could apply
the operation twice. The host serializes negotiated operations per window on its short-lived
control sockets so a key-down/key-up pair cannot overtake itself, while a slow acknowledgement
in one mirrored app does not stall input to another. Clipboard and other operations without a
window identity use their own global ordering lane. A guest `error` retains its original code
and message.

Agents that omit the capability or advertise `false` retain the existing
fire-and-forget path without an acknowledgement wait. This compatibility path
is selected from health, not inferred from a negotiated agent's silence.

Fixture: `harness/protocol-fixtures/operation.ack.json`.

An `input.mouse` acknowledgement may also carry `pointer`, where the event left the guest cursor, in
the 0...32767 absolute range QEMU's USB tablet uses on both axes across the guest's virtual desktop:

```json
{
  "type": "operation.ack",
  "requestId": "req_mouse_42",
  "accepted": true,
  "pointer": { "x": 16384, "y": 8192 }
}
```

The host moves QEMU's tablet to that position without pressing buttons. The tablet keeps reporting
the last absolute position QEMU gave it, so without this it snapped the cursor back from wherever
the agent's injected input put it, and a drag in a mirrored window jumped to the stale position
between events. `pointer` is optional: older agents omit it, and hosts without a QEMU tablet ignore
it.

Fixture: `harness/protocol-fixtures/operation.ack.mouse-pointer.json`.

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

A `scroll` event may carry `deltaX` and `deltaY`, wheel units with 120 per notch, positive scrolling
right and up as Windows counts them. Hosts send trackpad gestures as many small amounts, which Windows
scrolls smoothly; an event with neither field is one notch up. Other events omit both.

Implementation note: `x` and `y` are pixels in the window's frame bitmap, measured from the top-left of the window's visible frame. The Windows agent brings the window to the foreground, moves it fully onto its monitor's work area when it fits, and delivers each event as real input with `SendInput` at the matching absolute screen position. Posting window messages to the HWND did not reach XAML and DirectComposition content such as Paint's canvas, and posted moves carried no button state, so drags could not work.

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

## Input Text

Event from host to guest:

```json
{
  "type": "input.text",
  "windowId": "hwnd:0003029A",
  "text": "안녕하세요"
}
```

Why this exists separately from `input.key`: `input.key` carries a Windows *virtual key*, and the
virtual key map has no entry for a Hangul syllable, a kana character, a Han character, or even a space
or punctuation mark. Before `input.text`, the host's mapper returned nothing for all of those and the
keystroke was silently dropped, so a Korean user could not type their own language into a mirrored
Windows app.

Composition rule: **macOS owns the IME.** The host composes with the user's existing macOS input
source, shows the in-progress composition in its own overlay, and sends only the committed result
here. There is deliberately no marked or in-progress text on the wire. The alternative -- forwarding
raw keystrokes so the Windows IME composes -- would need a per-keystroke round trip plus a guest
candidate window rendered over a mirrored bitmap.

Rules:

- `windowId` must match the HWND-shaped id from a tracked `window.created` event. An untracked HWND is
  rejected with `window_not_tracked` and no messages are posted, exactly like `input.key`.
- `text` must be non-empty and at most 4096 UTF-16 code units. One message becomes a key-down and key-up
  pair per code unit on the guest, so an unbounded payload would flood the guest's input queue.
  Oversized payloads are rejected with `text_too_long`.
- `text` must not contain newlines, carriage returns, or tabs. Enter and Tab have guest semantics that
  a character cannot reproduce (Enter submits, Tab moves focus), so they stay on the `input.key` path
  and are rejected here with `invalid_message`.
- The guest types each UTF-16 code unit as a `KEYEVENTF_UNICODE` key event through `SendInput`.
  Surrogate pairs arrive as two consecutive code units, which is what Windows expects; sending a code
  point above U+FFFF as a single unit would truncate it.
- Arrow keys, function keys, Escape, Backspace, and Command/Control chords never travel here. They
  keep the `input.key` path, and while an IME composition is open they are consumed by the macOS input
  method instead of being sent at all.
- Failures inside the guest are reported as `input_text_failed`.

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

## Clipboard Image

Host to guest, and guest to host with `"origin": "guest"`:

```json
{
  "type": "clipboard.image.set",
  "requestId": "req_clipboard_7",
  "origin": "host",
  "sequence": 7,
  "format": "png",
  "width": 2,
  "height": 2,
  "byteLength": 74,
  "sha256": "d28c139bba718d60154960eaca75535a5cc5b59fe2153e998a29251e8e5f4667",
  "pngBase64": "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII="
}
```

An agent advertises `capabilities.clipboardImage: true`. The field is optional: an older agent decodes as
absent and the host keeps image clipboards on the Mac instead of sending a message the agent cannot route.

Rules:

- `format` is always `png`. PNG is the one lossless format both pasteboards carry natively (macOS
  `public.png`, the Windows registered `PNG` format), so neither side has to guess a colour space or quality.
  The bytes must start with the PNG signature; anything else is rejected rather than handed to an image decoder.
- `byteLength` is the decoded PNG size, 1...8,388,608 bytes (8 MiB), and must equal the decoded length of
  `pngBase64`. Base64 makes the frame about 11.2 MB, so the host raises its WebSocket receive limit to
  32 MiB; the URLSession default of 1 MiB would otherwise end the event stream on the first large copy.
- `width` and `height` are 1...16,384 pixels and `width * height` is at most 33,554,432. A small PNG can
  decode to an enormous bitmap, so the receiver checks the dimensions in the IHDR chunk against these fields
  and against the bound before decoding.
- `sha256` is the lowercase hex SHA-256 of the decoded PNG bytes. A mismatch is rejected. The hash is what
  stops repeats: a receiver that applies a remote image remembers its hash, and its own clipboard watcher
  treats an image with that hash as already seen instead of echoing it back. The guest also skips a
  broadcast whose hash equals the last one it sent, because Windows bumps the clipboard sequence number
  when an app re-sets identical content.
- Text and image updates share one `sequence` space per origin. They are two kinds of one clipboard, so a
  receiver that accepted guest image 9 must reject a later guest text 8.
- When the Windows clipboard holds both text and an image (a spreadsheet range, a rich-text selection), the
  guest sends only the text. That matches what the user most often means and keeps one copy from replacing
  the Mac clipboard with a picture of a table. The host instead follows the order the source app listed its
  pasteboard types in, because macOS apps list their richest representation first: Finder puts file URLs
  before the names it also writes as text, and a browser's Copy Image puts the bitmap before the address.
- On the guest, a host image is placed as both `PNG` and `CF_DIB`, so apps that only understand device
  independent bitmaps (Paint, most Win32 apps) can paste it. The guest reads `PNG` first and converts
  `CF_DIBV5`/`CF_DIB` to PNG otherwise.
- Host-origin writes receive `operation.ack` under negotiated acknowledgements, exactly like
  `clipboard.text.set`, and the host must not send the paste shortcut after an unconfirmed write.
- Failures are `clipboard_image_failed` (the Windows clipboard could not be taken or written) and
  `clipboard_image_too_large` (a bound above was exceeded). A malformed field is `invalid_message`.

Fixtures: `harness/protocol-fixtures/clipboard.image.set.host.json`,
`harness/protocol-fixtures/clipboard.image.set.guest.json`.

## Clipboard Files

Host to guest only:

```json
{
  "type": "clipboard.files.set",
  "requestId": "req_clipboard_8",
  "origin": "host",
  "sequence": 8,
  "shareName": "VeilShared",
  "relativePaths": [
    "Veil Clipboard\\20261105-140102-1A2B3C\\report.pdf"
  ]
}
```

An agent advertises `capabilities.clipboardFiles: true`.

### Why files travel through the shared folder

File bytes never ride this message. When the user copies files in Finder and presses ⌘V in a mirrored
Windows window, the host copies exactly those files into a fresh batch folder inside the guest-served shared
folder (`/Volumes/VeilShared/Veil Clipboard/<batch>/` on the Mac, `C:\VeilShared\Veil Clipboard\<batch>\` in
Windows), then names them here. The guest places them on its clipboard as `CF_HDROP` with a copy drop effect
and the host sends Ctrl+V, so Explorer or the target app copies them out like any local paste.

The alternatives were rejected on trust-boundary grounds:

- **Bytes over the control channel**, like `file.open.request`, would put gigabytes through a JSON socket
  and the host's 50 MB drop bound exists precisely to avoid that.
- **Sending host paths** and letting the guest read them needs a Mac folder visible to Windows. The only way
  to get one is macOS File Sharing, which publishes on every interface (see Shared Folder), and it would
  expose more than the copied files.
- **Guest-to-host files** (Explorer copy, Finder paste) are deliberately not synchronised. The guest would
  choose which paths the Mac pasteboard points at, and a guest-chosen file URL is the one clipboard payload
  that can make Finder act on host files. A user moves guest files to the Mac through the shared folder,
  which they can see and choose from.

### Rules

- Only `origin: "host"` exists. A guest-origin `clipboard.files.set` is rejected with `invalid_message`.
- `shareName` must equal the share the guest publishes. The guest resolves paths against its own
  `guestDirectoryPath`; the host never sends an absolute guest path.
- `relativePaths` holds 1...64 entries. Each is at most 240 characters, uses `\` separators, starts
  with `Veil Clipboard\`, and contains no empty, `.` or `..` component, no drive letter or root, no `:`
  (alternate data streams), and no characters Windows forbids in file names. After resolution the full path
  must still be inside `<guestDirectoryPath>\Veil Clipboard\`, must exist, must be a regular file and must
  not be a reparse point. One bad entry rejects the whole message, so a partial paste never happens.
- The host copies regular files only: no folders, no symbolic links, at most 64 files and 512 MiB in total.
  It refuses the paste with a message rather than copying part of the selection. Folder copy is left out of
  v1 because a recursive copy is where symlinks and package bundles would carry more than the user picked.
- Each paste gets a new batch folder named `yyyyMMdd-HHmmss-<6 hex>`. The host keeps the three newest batches
  and deletes older ones it created, and only folders matching that pattern inside `Veil Clipboard`.
- Requires the shared folder to be mounted on the Mac. Without it the host shows why and sends no paste
  shortcut, rather than pasting the file names as text.
- Failures are `clipboard_files_failed` (the clipboard could not be written) and
  `invalid_shared_file_path` (an entry failed the checks above).

Fixture: `harness/protocol-fixtures/clipboard.files.set.host.json`.

### Host controls

Clipboard sharing is on by default, matching the text behaviour Veil already shipped, and can be turned off
from the Apps menu (**Share Clipboard with Windows**). Off means no clipboard message is sent or accepted in
either direction; ⌘V still forwards Ctrl+V, so Windows pastes its own clipboard. **Copy Files into Windows on
Paste** is a separate switch, also on by default, because it writes into the shared folder.

Guest-to-host updates are applied to the Mac pasteboard only while Veil is the active app. A Windows app
that sets the clipboard in the background would otherwise replace what the user just copied in a Mac app
with no warning. A background update is dropped, not queued.

## Windows Notifications

Host request:

```json
{
  "type": "notification.listener.request",
  "requestId": "req_notification_listener",
  "protocolVersion": 1
}
```

Guest response:

```json
{
  "type": "notification.listener.response",
  "requestId": "req_notification_listener",
  "protocolVersion": 1,
  "accepted": false,
  "notificationListener": {
    "isSupported": true,
    "canListen": false,
    "accessStatus": "unspecified",
    "recommendedAction": "request-notification-listener-consent",
    "requiresPackageIdentity": true
  }
}
```

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

- `notification.listener.request` asks the packaged Windows agent to call
  Windows `UserNotificationListener.RequestAccessAsync()` and return the latest
  listener status. It must not be treated as proof that notifications are
  flowing; it only moves the consent gate forward.
- `notification.listener.response.accepted` must match
  `notificationListener.canListen`. When `accepted=true`, the next release
  evidence is still `veil-vmctl notification-proof --json --require-proved`.
- `notificationId`, `title`, and `receivedAt` are required.
- `receivedAt` must be an ISO timestamp generated by the guest when it observes the Windows notification.
- `appId`, `appName`, `body`, and `sourceAumid` are optional because Windows notifications can come from apps Veil did not launch directly.
- The macOS host keeps only a short recent-notification window in app-runtime status and ignores duplicate `notificationId` values.
- The Windows agent notification streamer also drops duplicate `notificationId` values and notifications missing a non-empty title before broadcasting to host clients.
- Real guest emission requires the signed sparse package identity and Windows `UserNotificationListener` consent gate described by `dailyUseReadiness.notificationBridgeRecommendedAction`. The first agent adapter syncs current toast notifications and re-syncs on Windows notification changes; live proof still has to show that this path runs inside the signed package on the real guest.
- `notification.received` is registered in `packages/protocol` (`MessageType.NotificationReceived` plus `validateNotificationReceived`) and has a fixture at `harness/protocol-fixtures/notification.received.json`. It was previously documented and implemented on both ends but missing from the executable package, so `parseMessage()` rejected a real guest notification as `unknown_message_type`.
- Because it is a guest-initiated event, host transports that multiplex events onto a request/response connection must skip it while awaiting a reply. `notification.listener.response` is not in that set, because it *is* a reply.

## Error

```json
{
  "type": "error",
  "requestId": "req_003",
  "code": "app_not_found",
  "message": "No app exists for id winapp_unknown"
}
```

### Codes

Codes documented alongside the message that produces them: `app_not_found`, `invalid_file_name`,
`invalid_shared_file_path`, `shared_file_missing`, `file_decode_failed`, `file_too_large`, `file_write_failed`, `file_open_failed`, `window_not_tracked`,
`text_too_long`, `invalid_message`, `input_text_failed`, `window_resize_failed`.

The guest also emits the following. They were undocumented, which meant a host could neither explain them
to a user nor pre-empt them:

| Code | Raised when |
|---|---|
| `handler_failed` | A message handler threw before producing any reply. The catch-all. |
| `app_launch_failed` | `app.launch.request` reached the guest but starting the process failed. |
| `window_focus_failed` | `window.focus.request` threw. Distinct from an accepted-but-refused focus, which returns `accepted: false` rather than an error. |
| `window_close_failed` | `window.close.request` threw, same distinction. |
| `window_resize_failed` | `window.resize.request` threw while applying the size to the tracked HWND. |
| `input_mouse_failed` | Posting a mouse message threw or Windows declined to apply it. |
| `input_key_failed` | Posting a key message threw or Windows declined to apply it. |
| `input_text_failed` | Posting committed text threw or Windows declined to apply it. |
| `clipboard_image_failed` | The guest could not read, convert, or write an image on the Windows clipboard. |
| `clipboard_image_too_large` | A `clipboard.image.set` exceeded the byte or pixel bounds in Clipboard Image. |
| `clipboard_files_failed` | The guest could not place the shared-folder files on the Windows clipboard. |
| `clipboard_text_failed` | The guest could not take the Windows clipboard. Routine rather than exotic: the guest retries `OpenClipboard` for 250 ms and any clipboard manager or Office instance can hold it longer. |

The fire-and-forget observation and silent `false`-return gaps recorded in
`docs/checklists/2026-08-13-host-guest-contract-audit.md` are addressed for negotiated
agents: the host reads the acknowledgement/error and the agent converts declined
input to a structured failure. Legacy agents retain unacknowledged delivery, so
socket submission alone cannot prove that Windows consumed their input.

## Shared Folder

A live, writable folder both macOS and Windows can read and write continuously. The
`file.open.shared.request` companion uses this folder for opening large files without copying their
bytes through the control channel, and the folder itself has no size cap.

Host request:

```json
{
  "type": "shared.folder.request",
  "requestId": "req_shared_folder",
  "protocolVersion": 1,
  "shareName": "VeilShared",
  "guestDirectoryPath": "C:\\VeilShared"
}
```

Guest response:

```json
{
  "type": "shared.folder.response",
  "requestId": "req_shared_folder",
  "protocolVersion": 1,
  "sharedFolder": {
    "isSupported": true,
    "shareName": "VeilShared",
    "guestDirectoryPath": "C:\\VeilShared",
    "directoryExists": true,
    "isShared": false,
    "isWritable": false,
    "serverListening": true,
    "requiresElevation": true,
    "requiresCredentials": false,
    "shareCommand": "New-SmbShare -Name VeilShared -Path C:\\VeilShared -FullAccess $env:USERNAME",
    "recommendedAction": "create-share-elevated",
    "message": "The agent created C:\\VeilShared but cannot publish an SMB share without administrator rights."
  }
}
```

### Which Direction Shares, and Why

The folder lives **in the guest** and is mounted on the Mac. That is the opposite of the naive
expectation, and it is the only direction that works with nothing installed on either side. The
alternatives were ruled out by what actually exists, not by preference:

- **virtio-9p / virtfs** has no Windows guest driver. The 9p client inside WSL is not a mountable
  filesystem driver for ordinary Windows.
- **virtio-fs** has a good Windows guest driver (WinFsp-based, from the virtio-win project), but its host
  half, `virtiofsd`, has no macOS port for QEMU.
- **QEMU's built-in usermode SMB** (`-netdev user,smb=...`) shells out to `/usr/sbin/smbd`, which on macOS
  is Apple's SIP-protected binary rather than Samba's; Homebrew installs Samba's as
  `samba-dot-org-smbd`; and current Samba refuses to run as the non-root user QEMU invokes it as.

What is left: Windows ships an SMB *server*, macOS ships an SMB *client*, and QEMU usermode networking
already forwards a host port into the guest for the guest agent. Veil adds one more forward,
`hostfwd=tcp:127.0.0.1:18445-:445`, appended to the existing `-netdev` rather than a second one so the
guest keeps a single NIC. The Mac mounts `smb://127.0.0.1:18445/VeilShared`.

The other direction -- a Mac folder appearing inside Windows -- needs an SMB server on the host. It is
modelled as the separate `host-smb` transport and reported as unavailable with its prerequisite, rather
than quietly conflated with the one that works. Turning on macOS File Sharing publishes the share on
every network interface, not only to the guest, so Veil never enables it silently.

### Rules

- `shareName` must be 1-64 characters of letters, digits, dot, dash, or underscore. It reaches an SMB
  share name and an elevated PowerShell command line, so it is validated on both ends rather than trusted.
- `guestDirectoryPath` must be an absolute Windows path with no `..` traversal and no shell
  metacharacters.
- The host sends both names rather than letting the guest choose. A disagreement between what the Mac
  mounts and what Windows published is exactly the silent failure this pair exists to prevent, so the
  guest echoes back what it actually used and the host compares.
- `shared.folder.request` prepares as far as the guest can without elevation: it creates
  `guestDirectoryPath` (the default ACL on a drive root already permits this for a standard user) and, only
  if the agent is already running elevated, publishes the share. Otherwise it reports what is left to do.
- `requiresElevation` describes the remaining work, not the agent's current token, so it stays `true`
  until the share exists. `shareCommand` is required whenever elevation is what is blocking the share, so
  the host never has to invent the command.
- `serverListening` is separate from `isShared` on purpose. A share that exists behind a closed Windows
  firewall looks identical to no share at all from macOS, so it must not read as healthy. The fix is
  `Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"`, which only exposes SMB on the guest's
  isolated usermode NAT network that nothing but this Mac can reach.
- `isShared` is never reported without `directoryExists`, and `isWritable` is never reported without
  `isShared`. Both combinations indicate a guest bug and would otherwise be diagnosed as a mount problem.
- Writability is tested *through* the share, not against the local folder. Local write access says nothing
  about the share permissions macOS will be subject to.
- **No credentials cross this protocol.** `requiresCredentials` is a standing requirement, not a
  detection: Windows refuses a network sign-in for a blank-password account, and the guest does not inspect
  password state. The password is supplied to macOS at mount time.
- `recommendedAction` is one of `unsupported-on-this-host`, `invalid-request`, `enable-smb-firewall`,
  `create-guest-directory`, `create-share-elevated`, `grant-share-write-access`, or `mount-on-mac`.
- An unsupported guest must not also report a share or a listening server. That combination would let a
  stub agent look like a real one.

### Host Reporting

`veil-vmctl shared-folder-status [--json] [--prepare] [--require-ready]` reports the whole path. Three
things have to agree and any one of them can be the problem, so all three are reported separately rather
than collapsed into one boolean: the boot plan carries the port forward, the guest is publishing the
share, and macOS has it mounted. Readiness is one of `ready`, `awaitingVM`, `awaitingGuestAgent`,
`awaitingGuestShare`, `awaitingHostMount`, or `unavailable`.

Without `--prepare` the command is read-only, taking the guest state from health. `--require-ready` is the
hard gate for automation; by default a folder that is simply not set up yet is a normal state to report,
not a command failure. `harness/shared-folder` validates the report shape.

Turning the shared folder on or off does **not** invalidate a suspended Windows session. Host port
forwarding is excluded from the suspend/resume machine fingerprint, because a `hostfwd` rule is slirp-side
plumbing: the guest sees an identical NIC with an identical MAC and address either way, and QEMU migration
does not serialize forwarding rules. Device topology is a different question and stays fingerprinted.
