# Daily Use CLI Evidence

Goal: keep the app UI, JSON status contract, and human-readable CLI output
aligned for the package identity gate that blocks Daily Use polish.

## Checklist

- [x] Print `dailyUseReadiness.packageIdentityStage` in human-readable
  `veil-vmctl app-runtime-status` output when package evidence exists.
- [x] Print `dailyUseReadiness.packageIdentitySucceeded` as a compact
  succeeded/not-complete status.
- [x] Print `dailyUseReadiness.packageIdentityMessage` so sparse-package
  failures or partial progress are visible without opening the JSON file first.
- [x] Print `dailyUseReadiness.packageIdentityEvidencePath` as the supportable
  evidence location.

## CEO Review

This is a small but useful service-quality pass: a contributor or user can run
the plain status command and see the same package identity blocker the app and
harness see, without switching to JSON inspection.

## Engineering Review

The nested `packageIdentityStatus` remains the source of truth. The CLI now
uses the flattened `dailyUseReadiness` summary fields that the status harness
already verifies against that source, reducing duplicate interpretation logic.
