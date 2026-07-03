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
- `window.closed.json`
- `window.frame.json`
- `window.frame.subscribe.json`
- `window.frame.unsubscribe.json`
- `window.close.request.json`
- `window.close.response.json`
- `input.mouse.left-down.json`
- `input.key.copy.json`
- `clipboard.text.set.host.json`
- `clipboard.text.set.guest.json`
- `error.app_not_found.json`

## Validation Rule

Once `packages/protocol` exists, CI should validate every fixture against the schema package. Until then, contributors should keep fixture shapes manually aligned with `docs/protocol.md`.
