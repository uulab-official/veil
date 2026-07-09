# Daily Use Action Guidance

Goal: keep failed sparse-package preparation guidance aligned with the app and
status surfaces, so users see one supportable package identity story.

## Checklist

- [x] Update rejected `prepare-sparse-package` next actions to point at
  `dailyUseReadiness.packageIdentityStage`, `packageIdentityMessage`, and
  `packageIdentityEvidencePath`.
- [x] Keep Windows SDK and retry guidance visible for packing/signing failures.
- [x] Update low-level sparse package attempt guidance to use the same Daily Use
  summary field names instead of raw nested `packageIdentityStatus` paths.
- [x] Add action-harness coverage so rejected sparse-package reports must expose
  Daily Use package identity summary evidence.

## CEO Review

This makes the failure path less like an internal protocol dump and more like a
product support path: one command tells the user the package identity stage,
message, and evidence location to inspect before retrying.

## Engineering Review

The source evidence still comes from `agent.health.response.packageIdentityStatus`.
The user-facing retry guidance now routes through the flattened
`dailyUseReadiness` contract, which is already validated against that source of
truth by `app-runtime-status`.
