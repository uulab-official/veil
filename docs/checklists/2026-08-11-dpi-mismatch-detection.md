# DPI Mismatch Detection

Date: 2026-08-11

Follow-on to `2026-08-10-retina-scaling-finding.md`, which established that Retina
scaling is mostly already correct and that the remaining gap is **not** host
arithmetic: a 100% Windows guest on a Retina Mac supplies half the pixels the display
draws, and no calculation on the host creates them.

Veil cannot set Windows' display scaling from outside the guest. So this slice does
the next most useful thing: it measures the mismatch and names the exact percentage
that would fix it, instead of leaving soft text as an unexplained quality problem.

## Why Both Directions

The two failures are not symmetric, and reporting only the obvious one would have
missed a real cost.

| Case | What happens | Cost |
|---|---|---|
| Guest scale **below** host | macOS enlarges a bitmap that lacks the pixels | Visible: text looks soft |
| Guest scale **above** host | Guest renders pixels the display cannot show | Invisible: every one is encoded, transferred, and composited before being discarded |

The second case is a frame-pipeline problem wearing a display-settings costume. A 200%
guest mirrored to a 1x Mac pays four times the encode and transfer cost per frame for
nothing. That connects directly to the pending codec decision — it would be
embarrassing to shop for a better codec while shipping 4x the pixels needed.

## What Was Built

- [x] `WindowsAppRuntimeDisplayScalingStatus` in `HostDashboardModel.swift`. Reports
      `hostBackingScale`, `guestRenderScale`, `scaleRatio`, `isUpscaling`,
      `isOverRendering`, `recommendedGuestScalePercent`, `recommendedAction`, `reason`.
- [x] `HostDashboardModel.displayScalingStatus(hostBackingScale:)`. Pure arithmetic over
      the foreground window's most recent frame.
- [x] `displayScaling` on `WindowsAppRuntimeStatusReport`, plus the `runtimeStatusReport`
      parameter that feeds it.
- [x] `HostDisplayScale` in the app shell, reading `NSScreen.main?.backingScaleFactor`.
      Wired into all three shell report call sites.
- [x] `veil-vmctl app-runtime-status --host-backing-scale 2`, so the check is reachable
      from the CLI, which has no window server to ask.
- [x] 11 Swift tests in `HostDashboardModelTests.swift` (`GuestDisplayScalingTests`).
- [x] `validateDisplayScaling` in `harness/app-runtime-status/`, plus 15 harness tests.

## Decisions

**`hostBackingScale` is `Double?`, and `nil` means unknown rather than 1.**
VeilHostCore does not import AppKit, so it cannot read a screen itself. Defaulting to
1 would have been the convenient choice and it would have told every Retina user to
change a display setting that was already correct — a false positive on the most common
hardware Veil runs on. `nil` produces `inspect-host-display-scale`, which is honest
about which half of the measurement is missing. The guest half is still reported.

**A 5% tolerance, not exact equality.** Windows offers 125% and 150% steps that can
never equal a Mac's 1x or 2x. Exact equality would nag permanently on hardware where
no setting satisfies it. The tolerance is deliberately narrow enough that 125% on a 1x
Mac still reports over-rendering, which is a real 1.56x pixel cost; a harness test pins
that boundary so the tolerance cannot be widened until it swallows a genuine mismatch.

**The recommended percentage must appear in `reason`, enforced by the harness.**
"Your display scaling does not match" is not actionable — the user has to choose between
125, 150, and 200. The validator rejects a mismatch report whose text omits the number.

**Actions are named as guest settings, not Veil operations.**
`raise-guest-display-scaling` rather than `set-guest-dpi`, because Veil does not perform
it. Every other `recommendedAction` in this report names something Veil or the user can
actually do, and inventing an action Veil cannot execute would break that.

**The foreground window supplies the guest scale.** Windows exposes one display-scaling
setting per display, so any mirrored window is representative. This matches how
`macWindowIntegration` already picks a foreground window.

**`NSScreen.main`, with a documented limitation.** It is the screen holding keyboard
focus, not necessarily the screen a given mirrored window sits on. On a mixed-DPI setup
those differ and there is no single correct answer, because the recommendation is one
guest setting. The focused screen is the one whose text the user is reading. Existing
placement code in `WindowsAppWindowPresenter` reads `NSScreen.main` the same way.

**The CLI does not link AppKit to read a real scale.** `NSScreen.main` in a
command-line process depends on a window server connection that a CI or headless run
does not have. An explicit `--host-backing-scale` flag is honest about where the number
came from and works in both settings. Out-of-range or unparseable values fail loudly
rather than being ignored.

## Validator Rules Worth Naming

The section is only useful if it cannot lie. `validateDisplayScaling` rejects:

- `scaleRatio` that does not equal `hostBackingScale / guestRenderScale`, so a mismatch
  cannot be derived from something other than the two scales it claims to compare.
- `isUpscaling` and `isOverRendering` both true, which would mean the comparison ran
  twice with different inputs.
- A mismatch claim with no `scaleRatio` to support it.
- `none` outside the match tolerance, or `none` without both sides measured. This branch
  needed an explicit `scaleRatio === undefined` guard: both flags are false there, so the
  mismatch check cannot catch a missing ratio, and `Math.abs(undefined - 1)` is `NaN`,
  which fails every comparison silently and would have passed.
- `recommendedGuestScalePercent` disagreeing with `hostBackingScale`.
- `wait-for-first-frame` with nothing mirrored, and `open-windows-app` while windows are
  mirrored.
- `inspect-host-display-scale` while already reporting a host scale.

## Growing Debt: Optional Fields For Back-Compat

`displayScaling` is the **third** field made optional so that saved fixtures predating it
still validate, after `unchangedHeartbeatCount` and `quietMode`. The pattern is correct
in isolation — absence means "predates the check", which is a genuinely different claim
from a passing value, and the validator must not read absence as a pass.

But three is a trend. The cost is that the strongest form of each rule is never enforced
against the canonical fixtures, only against mutated copies in tests. The fixtures should
be regenerated from real CLI output and these three fields promoted to required. That
needs a working shell, so it is recorded here rather than attempted.

## Not Verified

`swift build`, `swift test`, and `npm test` have not been run. The shell in this
environment returns exit 1 with empty output for every command, including `echo`. Every
item above is written but uncompiled.

Specific risks a compiler would catch immediately:

- `WindowsAppRuntimeStatusReport` has an explicit `public init`, not a memberwise one.
  The new parameter was added there and to the assignment body; a missed one is a build
  error, not a silent bug.
- `VMControlArguments.Command.appRuntimeStatus` gained a third associated value. No test
  pins its arity (checked by search), and the two construction and match sites were both
  updated.
- `HostDisplayScale` is a new file in `VeilHostShell`. It reads `NSScreen.main` from a
  non-isolated static, matching `VeilHostShellApp.fitToPreferredSize`, which already does
  exactly that and compiles.

## Next

Run the build order in `docs/checklists/2026-08-07-unverified-slice-review.md` and stop
at the first failure. Then take the four `frame-pipeline-report` measurements before any
codec decision — and take them with `displayScaling.recommendedAction == "none"`, because
measuring a pipeline that is shipping 4x the necessary pixels would produce numbers that
say more about a display setting than about the codec.
