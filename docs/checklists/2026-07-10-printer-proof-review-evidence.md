# Printer Proof Review Evidence

Goal: keep printer bridge proof visible in the Parallels-style review card, not
only in raw app-runtime status.

## Checklist

- [x] Mirror latest `proofArtifacts.latestPrinterBridgeProof*` fields into
  `app-runtime-review.evidence`.
- [x] Print latest printer proof status and evidence file in the human-readable
  review command output.
- [x] Extend `harness/app-runtime-review` so review evidence must match embedded
  status proof artifacts.
- [x] Keep the QEMU host IPP endpoint and `Diagnostics/Printer Proof` path
  constraints in review validation.

## Engineering Review

This keeps Daily Use evidence auditable from the same review card used for
one-screen launcher, app-window, menu/Dock, and screenshot checks. The review
card still does not claim automatic printer provisioning; it only carries the
latest user-supplied Windows test-page evidence metadata already recorded by
`printer-bridge-proof`.
