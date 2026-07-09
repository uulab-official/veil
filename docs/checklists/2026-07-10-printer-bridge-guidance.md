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
- [x] Validate the printer bridge guidance in the app-runtime-status harness.
- [x] Update status/action/review fixtures so automation carries the same
  printer bridge guidance everywhere Daily Use readiness appears.

## CEO Review

This does not claim printer bridging is automatic yet. It makes the next
manual experiment visible from the product status surface, which is closer to a
UTM/Parallels-level support experience than a roadmap footnote.

## Engineering Review

The contract is intentionally conservative: no new QEMU device surface, no
driver claim, and no automatic macOS printer enumeration. The status only
documents the known SLIRP host endpoint and the manual IPP setup path.
