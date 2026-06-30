# Safe Demo Fallback Checklist

Goal: keep the internal demo agent helpful without hiding real agent or protocol failures.

## Checklist

- [x] Add a failing test proving primary agent errors are not hidden by demo fallback.
- [x] Restrict demo fallback to network availability errors.
- [x] Keep no-agent startup fallback working.
- [x] Document that protocol and agent errors remain visible.
- [x] Run Swift and harness tests.
- [x] Commit and push to `main`.

## Out of Scope

- Retrying failed network connections.
- Adding user-configurable fallback settings.
- Simulating real Windows app failures in the demo service.
