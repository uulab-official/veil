# Package Identity Evidence Consistency

Goal: prevent Daily Use readiness from showing contradictory package identity
states while Veil moves toward Parallels-style Windows app integration.

## Checklist

- [x] Reject status reports where `connection.capabilities.packageIdentity=true`
  but the latest sparse package evidence reports `succeeded=false`.
- [x] Reject status reports where sparse package evidence reports
  `succeeded=true` but the live agent still lacks package identity.
- [x] Reject notification listener readiness when the listener claims it can
  listen without package identity.
- [x] Keep the rule in the app-runtime-status harness so review cards inherit
  the same Daily Use gate.

## Engineering Review

Borderless capture and Windows notification mirroring both depend on the signed
sparse package path. The app must not present those lanes as ready unless the
live capability and the latest sparse package evidence agree. This keeps the UI
from showing "ready" and "not complete" at the same time during real Windows
guest setup.
