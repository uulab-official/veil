# Daily Use Package Evidence

Goal: make the sparse package/package identity gate feel supportable from the
app surface, not like hidden Windows-side script output.

## Checklist

- [x] Keep `dailyUseReadiness.packageIdentityStatus` as the full sanitized guest
  evidence object.
- [x] Add flat package identity summary fields for UI and automation:
  `packageIdentityStage`, `packageIdentitySucceeded`, `packageIdentityMessage`,
  and `packageIdentityEvidencePath`.
- [x] Validate that summary fields match `packageIdentityStatus` when evidence
  exists.
- [x] Reject summary fields without package identity evidence so UI cannot imply
  a real sparse-package run happened.
- [x] Update the live app-runtime status fixture to show a `packageSigned`
  sparse-package blocker.

## CEO Review

This moves Veil closer to a Parallels/UTM-quality support surface: when Daily
Use polish is blocked by package identity, the app can say which exact Windows
preparation stage is blocking the path and where the sanitized evidence lives.

## Engineering Review

The shape remains backward-compatible for consumers that only read
`packageIdentityStatus`, while the harness now guarantees that flat UI fields do
not drift from the nested source of truth.
