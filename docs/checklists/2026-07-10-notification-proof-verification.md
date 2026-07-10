# Notification Proof Verification

Goal: make review evidence reject stale or missing Windows notification proof
files instead of only mirroring status fields.

## Checklist

- [x] Add `notificationProof` to `app-runtime-review-verify` output when review
  evidence claims a latest Windows notification proof.
- [x] Validate the proof JSON exists and has `kind=windowsNotificationProof`
  plus `status=proved`.
- [x] Compare notification id, title, and received timestamp against
  `app-runtime-review.evidence.latestNotificationProof*`.
- [x] Block complete review verification when claimed notification proof is
  missing, malformed, unproved, or mismatched.
- [x] Route the next evidence action to `Regenerate Notification Proof` before
  allowing evidence sharing.

## Engineering Review

Notification evidence now has the same review-verification bar as app check and
printer evidence. The review card can show the latest notification proof only
when the referenced JSON artifact is still present and matches the metadata
promoted from app-runtime status.
