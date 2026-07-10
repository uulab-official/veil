# Review Daily Use Evidence

Goal: make app-runtime review evidence show the current Daily Use blocker
without requiring reviewers to inspect the nested status object.

## Checklist

- [x] Mirror Daily Use package identity readiness into review evidence.
- [x] Mirror borderless capture and notification preflight readiness into review
  evidence.
- [x] Mirror the Daily Use recommended action, command, reason, and sparse
  package evidence summary into review evidence.
- [x] Extend the app-runtime-review harness so review evidence cannot drift from
  embedded `status.dailyUseReadiness`.
- [x] Print the Daily Use blocker in the human-readable review command output.

## Engineering Review

The review card is the evidence surface for deciding whether Veil feels like a
usable Windows App Runtime rather than a CLI-only proof. Daily Use readiness now
appears directly in `evidence`, while the embedded full status remains the source
of truth. This makes package identity, borderless capture, and notification
blockers visible during review without duplicating logic.
