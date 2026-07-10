# Printer Bridge Guidance

Goal: move the v1.5 printer bridge from a buried research note into the
machine-readable Daily Use contract, while keeping it honest as a manual IPP
experiment.

## Checklist

- [x] Add `dailyUseReadiness.printerBridgeRecommendedAction` with the current
  `manual-ipp-experiment` lane.
- [x] Add `dailyUseReadiness.printerBridgeEndpointTemplate` with the QEMU
  user-network IPP endpoint:
  `http://10.0.2.2:631/printers/<shared-printer-name>`.
- [x] Add `dailyUseReadiness.printerBridgeSetupHint` so app and CLI surfaces can
  explain Mac printer sharing plus Windows IPP network-printer registration.
- [x] Add `dailyUseReadiness.printerBridgePlanCommand` so the app and CLI can
  hand off to one reproducible printer bridge setup plan.
- [x] Add `veil-vmctl printer-bridge-plan --json` with macOS sharing guidance,
  Windows `Add-Printer -IppURL`, verification steps, and honest proof
  limitations.
- [x] Add the `harness/printer-bridge-plan` validator and fixture so the setup
  contract cannot drift away from QEMU host IPP or live test-page evidence.
- [x] Validate the printer bridge guidance in the app-runtime-status harness.
- [x] Update status/action/review fixtures so automation carries the same
  printer bridge guidance everywhere Daily Use readiness appears.

## CEO Review

This does not claim printer bridging is automatic yet. It makes the next
manual experiment visible from the product status surface and gives operators a
single reproducible setup plan. That is closer to a UTM/Parallels-level support
experience than a roadmap footnote, while still refusing to call the feature
automatic before proof exists.

## Engineering Review

The contract is intentionally conservative: no new QEMU device surface, no
driver claim, and no automatic macOS printer enumeration. The status only
documents the known SLIRP host endpoint and the manual IPP setup path.
The Windows side uses PowerShell `Add-Printer -IppURL`, and the harness requires
test-page evidence before this can graduate beyond `manual-ipp-experiment`.
