# Printer Bridge Proof

Goal: make the manual IPP printer bridge experiment evidence-backed without
claiming automatic printer provisioning.

## Checklist

- [x] Add `veil-vmctl printer-bridge-proof --json --evidence ...` to record a
  Windows test-page evidence file as metadata.
- [x] Save printer proof metadata under `Diagnostics/Printer Proof` by default.
- [x] Promote the latest printer proof summary into
  `app-runtime-status.proofArtifacts`.
- [x] Surface the latest printer proof in the Windows Apps panel so the app
  distinguishes setup-only state from evidence-backed printer proof.
- [x] Add `harness/printer-bridge-proof` so proof JSON must include evidence
  metadata, the generated IPP plan, and the QEMU host IPP endpoint.
- [x] Keep the proof privacy boundary explicit: Veil records metadata and does
  not copy printer output into diagnostics.

## CEO Review

This makes the printer lane feel less like a note and more like a supportable
product workflow: the user can prove a Windows test page happened, and support
can see the latest proof summary in the same app-runtime status surface.

## Engineering Review

The implementation still avoids macOS printer enumeration, CUPS changes,
Windows driver claims, or automatic guest registration. It adds a durable proof
contract around user-supplied evidence so the feature can graduate only after a
real test-page artifact exists.
