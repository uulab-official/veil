# Demo Mode Indicator Checklist

Goal: make the internal demo agent visibly distinct from a real or fake WebSocket Windows agent.

## Checklist

- [x] Add model state for agent vs demo connection mode.
- [x] Preserve agent mode for real and fake WebSocket responses.
- [x] Mark fallback responses as demo mode.
- [x] Show demo mode in the header.
- [x] Show connection mode in the Agent view.
- [x] Document the visible demo mode indicator.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- User preference to disable demo fallback.
- Persistent connection history.
- Real Windows agent installation state.
