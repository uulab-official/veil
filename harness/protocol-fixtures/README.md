# Protocol Fixtures

These JSON files mirror the stable examples in `docs/protocol.md`.

## Current Fixtures

- `agent.health.request.json`
- `agent.health.response.json`
- `app.list.request.json`
- `app.list.response.json`
- `app.launch.request.json`
- `app.launch.response.json`
- `window.created.json`
- `window.updated.json`
- `window.closed.json`
- `window.frame.json`
- `window.frame.unchanged.json`
- `window.frame.subscribe.json`
- `window.frame.unsubscribe.json`
- `window.focus.request.json`
- `window.focus.response.json`
- `window.close.request.json`
- `window.close.response.json`
- `window.resize.request.json`
- `window.resize.response.json`
- `file.open.request.json`
- `file.open.response.json`
- `input.mouse.left-down.json`
- `input.key.copy.json`
- `input.text.json`
- `clipboard.text.set.host.json`
- `clipboard.text.set.guest.json`
- `notification.listener.request.json`
- `notification.listener.response.json`
- `notification.received.json`
- `error.app_not_found.json`

## Validation Rule

`packages/protocol` now exists, and its test suite parses every fixture listed above through
`parseMessage()` plus the matching `validateXxx()` helper. Run it with:

```bash
cd packages/protocol
npm test
```

A new stable message is not done until it has a fixture here, an entry in `MessageType`, and a
validator call in `packages/protocol/test/messages.test.mjs`. Keep fixture shapes aligned with
`docs/protocol.md`.
