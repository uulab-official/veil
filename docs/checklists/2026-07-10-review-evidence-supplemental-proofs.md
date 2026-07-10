# Review Evidence Supplemental Proofs

Goal: make review evidence setup guide users through optional Daily Use proof
artifacts that are verified outside the screenshot folder.

## Checklist

- [x] Add notification proof regeneration guidance to review evidence README and
  manifest next actions.
- [x] Add printer bridge proof regeneration guidance to review evidence README
  and manifest next actions.
- [x] Keep the guidance consistent between the CLI `app-runtime-review-init`
  path and the in-app evidence folder store.
- [x] Extend the app-runtime-review manifest harness so supplemental proof
  guidance cannot silently disappear.

## Engineering Review

Review verification now checks notification and printer proof JSON files when
the review card references them. This checklist makes the setup side match that
verification bar, so contributors know to keep or regenerate those diagnostics
before sharing evidence.
