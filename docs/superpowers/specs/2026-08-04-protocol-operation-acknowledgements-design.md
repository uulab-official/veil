# Protocol Operation Acknowledgements Design

Date: 2026-08-04

## Goal

Close the protocol reliability gap where the macOS host sends input, clipboard,
and frame-stream control messages and closes the request socket without seeing
whether the Windows guest accepted or rejected them.

The change must preserve protocol v1 compatibility, surface guest-side `false`
results as actionable protocol errors, and avoid adding acknowledgement traffic
to high-frequency pointer movement.

## Scope

Acknowledged operations:

- mouse button and scroll input,
- key input,
- host-to-guest text clipboard writes,
- window frame subscribe,
- window frame unsubscribe.

`input.mouse` with `event=move` remains best-effort and does not wait for an
acknowledgement. Guest-origin clipboard events remain broadcasts and are not
acknowledged.

## Chosen Approach

Add an optional `requestId` to input messages and a common
`operation.response` message:

```json
{
  "type": "operation.response",
  "requestId": "req_key_42",
  "operation": "input.key",
  "accepted": true
}
```

New hosts attach a unique request ID to acknowledged operations and wait for one
bounded direct reply. New guests return `operation.response` only when a
request ID is present. This keeps old hosts compatible: messages without a
request ID retain their existing no-reply behavior, so old clients do not leave
unconsumed success replies on their request sockets.

Failures continue to use the existing `error` envelope. A guest platform method
that returns `false` becomes an operation-specific protocol error rather than a
silent success. Missing or untracked windows continue to use
`window_not_tracked`.

## Alternatives Considered

1. Acknowledge every mouse movement. This gives the strongest delivery signal,
   but serializes a high-frequency path through one response per event and risks
   visible pointer lag.
2. Acknowledge state-changing operations while keeping mouse movement
   best-effort. This closes the user-visible correctness gaps without putting the
   hottest input path behind round trips. This is the selected approach.
3. Add a persistent batched acknowledgement channel. This would scale better,
   but requires transport lifecycle, batching, retry, and ordering work beyond
   the current protocol reliability item.

## Component Changes

### Protocol package and fixtures

- Add `operation.response` to the shared message type list.
- Allow optional `requestId` on mouse and key input.
- Add a validator and fixture for `operation.response`.
- Keep `requestId` required on clipboard and frame stream control requests.

### Windows guest agent

- Return a success response for scoped operations only when `requestId` exists.
- Convert `SendMouseInputAsync` and `SendKeyInputAsync` `false` results into
  `input_mouse_rejected` and `input_key_rejected` errors.
- Preserve existing exception-to-error behavior.
- Return subscribe/unsubscribe and host clipboard success acknowledgements after
  the operation has been accepted.

### macOS host

- Generate request IDs for acknowledged operations.
- Wait for exactly one reply and validate its request ID, operation, and
  `accepted=true` fields.
- Decode existing `error` replies through `VeilHostError.agentError`.
- Send pointer movement without waiting for a reply.

### Fake agent and harness

- Mirror the compatibility behavior of the real guest.
- Update fixtures and assertions so failures are observable by the host rather
  than being silently dropped.

## Error Handling and Compatibility

- A mismatched response type, request ID, operation, missing response, or
  `accepted=false` is a host-visible failure.
- Existing protocol errors remain the source of machine-readable failure codes.
- New guest + old host remains compatible because success replies are opt-in via
  `requestId` for previously fire-and-forget input.
- New host + old guest cannot provide acknowledgement guarantees; the bounded
  request times out and presents a connection/update error instead of claiming
  success. This is intentional because silent success is the bug being removed.
- No protocol version bump is required because fields are additive and the new
  response type is requested only by clients using the new behavior.

## Verification

- JavaScript protocol tests validate accepted and malformed operation responses.
- Fake-agent tests cover acknowledged success, legacy no-reply compatibility,
  untracked windows, and asynchronous pointer movement.
- Windows agent tests cover success acknowledgements and platform `false`
  conversion for mouse and key input.
- Swift host tests cover response validation, protocol errors, timeouts/missing
  replies, and the mouse-move exception.
- Full protocol, harness, Swift, and available Windows agent test suites run
  before merge. If the local .NET SDK remains unavailable, Windows test execution
  is reported as an environment blocker rather than claimed as passed.

## Non-Goals

- Persistent multiplexed WebSocket transport.
- Input replay or retry, which could duplicate clicks or keystrokes.
- Batching pointer movement acknowledgements.
- Changing window focus/close response shapes.
- Binary frame transport or frame latency tuning.
