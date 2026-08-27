# Frame Pipeline: Measurement

Date: 2026-08-03

Fourth slice. Not a feature: the instrumentation that makes every remaining
frame-pipeline decision answerable instead of guessed.

## Why This Comes Before More Optimization

Three slices have landed with no before/after numbers behind any of them:

- 2026-07-31: unchanged-frame heartbeats, so idle windows stop re-encoding.
- 2026-08-01: binary frame channel, removing base64 and JSON from the frame path.
- 2026-08-02: dirty-rect tiles, so a changed window sends only what changed.

Each is defensible on reasoning. None is verified. That is the same pattern this
roadmap already criticized: frame latency was treated as a tuning problem for
months while nobody measured where the time went.

The concrete decisions that are currently unanswerable:

- **Did tiles actually help?** If a typical change covers most of the surface,
  the key-frame promotion threshold is wrong and the fix is the region strategy,
  not the transport.
- **What key-frame interval?** Deliberately deferred in the previous slice because
  picking one without data is a guess.
- **Codec next, or something else?** A PNG-per-tile pipeline that turns out to be
  CPU-bound needs a different fix than one that is bandwidth-bound. Reaching for
  H.264 before knowing which would be guessing again.

What already exists: `coherence-proof` measures first-frame and post-input frame
**latency** against a budget. What does not exist anywhere is **throughput and
efficiency**: bytes on the wire, achieved frame rate, how much of a surface a
typical change touches, and what compositing costs.

## Track A: Metrics Collection

- [x] Add a metrics collector that the frame channel and compositor feed, recording
      per-window frame counts, wire bytes, tile coverage, frame intervals, composite
      duration, heartbeats, and dropped tiles by reason.
- [x] Bound sample retention so a long run cannot grow without limit, while keeping
      counts exact.
- [x] Report percentiles, not just means. A mean frame interval hides the stalls a
      user actually notices.
- [x] Estimate what the same session would have cost sending full frames, so the
      report answers "did tiles help" directly rather than leaving arithmetic to the
      reader.
- [x] Base that estimate on **observed** key-frame bytes per pixel rather than a
      constant, and label it an estimate, since PNG size is not linear in area. Withheld
      entirely when no key frame was observed.
- [x] Derive next actions from the numbers, including flagging content where median
      tile coverage is high enough that dirty-rect tracking is not paying off.

## Track B: A Runnable Measurement

- [x] Add `veil-vmctl frame-pipeline-report` that opens the frame channel, collects for
      a bounded window, and emits the report as JSON, optionally saving it to a file.
- [x] Cap the duration at 300 seconds, so the command cannot become an accidental
      unbounded profiler.
- [x] Report honestly when no frames arrived at all, rather than emitting zeroes that
      look like a measured result. The command also exits non-zero in that case so
      automation cannot mistake it for a successful measurement.
- [x] Keep a partial measurement usable when the channel drops mid-run rather than
      failing the whole command.
- [x] Add a harness validator with the invariants that make a report trustworthy:
      counts that must agree, coverage bounded to 0-100%, percentiles ordered, and the
      estimate present whenever it was computable.

## Verification Status

Written alongside the implementation:

- `apps/mac-host/Tests/VeilHostCoreTests/FramePipelineMetricsTests.swift`: rates measured against the
  requested window rather than the last event, tile coverage percentages, the full-frame estimate derived
  from observed key-frame bytes per pixel, the estimate withheld when no key frame was seen, negative
  savings reported rather than hidden, dropped tiles counted by reason without counting as delivered
  frames, per-window separation, an honest report for a run with no activity, zero rates instead of
  infinity for a zero-length window, bounded sample retention with exact counts preserved, the
  coverage-too-high next action, and ordered nearest-rank percentiles.
- `harness/frame-pipeline-report`: rejects a report claiming frames when none were applied, a no-frame
  report that does not say how to diagnose it, byte totals that do not add up, coverage above 100%,
  unordered percentiles, a mean above a maximum, a zero-sample summary with non-zero statistics, more
  interval samples than consecutive updates allow, a missing full-frame estimate when one was computable,
  an estimate without its savings percentage, dropped tiles not called out, an estimation basis that does
  not admit being an estimate, and duplicate windows. Accepts a negative savings percentage.

**These were not executed.** Shell command execution was unavailable in the session that produced this
change, and it is not a permissions problem: `echo` itself returns exit 1 with no output, and background
processes report as running without executing.

```bash
cd apps/mac-host && swift build && swift test
cd harness/frame-pipeline-report && npm test
```

## Design Notes Worth Keeping

- Latency is deliberately out of scope. `coherence-proof` already measures first-frame and post-input
  latency against a budget; the gap was throughput and efficiency, and duplicating latency measurement here
  would have produced two numbers that could disagree.
- Percentiles are nearest-rank over sorted samples, so every reported value is one that actually occurred
  and `p50 <= p95 <= maximum` is a structural guarantee the harness can enforce.
- The full-frame comparison is an **estimate**, anchored to observed key-frame bytes per pixel for the same
  window rather than a constant, and it is withheld entirely when no key frame was seen. PNG size is not
  linear in area, and the report says so in a field the harness requires. Inventing a constant would have
  made a guess look like data.
- Rates are measured against the requested observation window, not the last event, so an idle tail is
  included honestly instead of inflating the rate the pipeline appears to sustain.
- A dropped tile is counted separately and never as a delivered frame, matching the same rule the model
  applies to frame timing.
- Sample retention is capped, but *counts* stay exact. Only the percentile inputs are bounded, so a long
  run cannot grow without limit while still reporting the true number of frames.
- The measurement command composites into a throwaway surface rather than the app's, so a diagnostic run
  never disturbs what a running Veil.app is displaying.

## Remaining Live Verification

This is the whole point of the slice, and none of it is done:

- [ ] Run `veil-vmctl frame-pipeline-report --json --seconds 30` against a real Windows 11 Arm guest with a
      Notepad window open, while typing continuously.
- [ ] Repeat with the window completely idle. Expect near-zero frames and a high heartbeat count; anything
      else means the 2026-07-31 heartbeat work is not doing what it claims.
- [ ] Repeat while scrolling a large document. This is the case most likely to show that dirty-rect
      tracking does not pay off, and where the key-frame promotion threshold would need revisiting.
- [ ] Record all three reports under `docs/` so the next optimization argues from data.
- [ ] Use the coverage numbers to choose a periodic key-frame interval, which the previous slice
      deliberately deferred rather than guessing.
- [ ] Decide from the byte-rate and composite-time numbers whether the pipeline is bandwidth-bound or
      CPU-bound. That determines whether a codec change is the next step at all.
