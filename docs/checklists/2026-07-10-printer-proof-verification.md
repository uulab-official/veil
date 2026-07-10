# Printer Proof Verification

Goal: make review evidence reject stale or missing printer bridge proof files
instead of only mirroring status fields.

## Checklist

- [x] Add `printerBridgeProof` to `app-runtime-review-verify` output when review
  evidence claims a latest printer bridge proof.
- [x] Validate the proof JSON exists and has
  `kind=windowsPrinterBridgeProof` plus `status=proved`.
- [x] Compare proof JSON evidence metadata and IPP endpoint against
  `app-runtime-review.evidence.latestPrinterBridgeProof*`.
- [x] Block complete review verification when claimed printer proof is missing,
  malformed, unproved, or mismatched.
- [x] Route the next evidence action to `Regenerate Printer Proof` before
  allowing evidence sharing.

## Engineering Review

This closes a false-positive gap in the review pipeline. A release card can now
carry printer bridge evidence only if the referenced proof artifact is still
present and matches the metadata already promoted through app-runtime status.
The check remains metadata-only and does not copy the user's printer output.
