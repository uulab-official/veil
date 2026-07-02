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
    "windowCapture": false,
    "input": true,
    "clipboardText": true
  }
}
```

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
      "iconId": "icon_notepad"
    }
  ]
}
```

## App Launch

Request:

```json
{
  "type": "app.launch.request",
  "requestId": "req_003",
  "appId": "winapp_notepad",
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

Rules:

- `windowId` must match the HWND-shaped id from a tracked `window.created` event.
- On Windows, the first implementation maps this to `WM_CLOSE` for the target HWND.
- `accepted: true` means the close message was posted to the window. The guest may later emit a dedicated `window.closed` event once window lifecycle tracking is added.

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

## Error

```json
{
  "type": "error",
  "requestId": "req_003",
  "code": "app_not_found",
  "message": "No app exists for id winapp_unknown"
}
```
