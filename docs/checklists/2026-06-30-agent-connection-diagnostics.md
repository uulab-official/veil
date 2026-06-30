# Agent Connection Diagnostics Checklist

Goal: improve service quality by explaining why the host shell entered demo mode and which agent endpoint was unreachable.

## Checklist

- [x] Add connection detail to host overview results.
- [x] Add connection detail to launch results.
- [x] Preserve connection detail on the dashboard model.
- [x] Include the unreachable endpoint in demo fallback diagnostics.
- [x] Show connection detail in the header demo banner.
- [x] Show connection detail in the Agent view.
- [x] Document the endpoint diagnostic behavior.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Agent endpoint editing UI.
- Automatic background retry.
- Persistent diagnostics history.
