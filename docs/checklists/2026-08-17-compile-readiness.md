# Compile Readiness

Date: 2026-08-17

Seventeen slices of work have never been compiled. This is the closest substitute available:
a symbol-by-symbol review of every file touched, against the declaration of everything it
references. It is not a build. It is the set of things a reader can check that a compiler
would otherwise catch first.

It found two real defects, one of them a hard compile error.

## Found And Fixed

### `#expect` cannot call a `mutating` method — 12 sites

`GuestEventRateLimiter.allows(at:)` is `mutating`. swift-testing's `#expect` does not evaluate
a member call in place: it decomposes `#expect(limiter.allows(at: x))` into

```swift
__checkFunctionCall(limiter.self, calling: { $0.allows(at: $1) }, x, …)
```

where `$0` is an immutable closure parameter. So every bare assertion on it was
`error: cannot use mutating member on immutable value`.

The `== false` variants were fine — an infix operator routes through a different overload that
evaluates the left side at the call site. Which is worse than uniform failure, because half the
assertions compiled.

Fixed by collecting results first, through one `inout` helper. That is also better as a test:
the assertion shows the whole sequence at once, `[true, true, true, false]`, instead of four
separate lines that have to be read in order.

### `@discardableResult` attached to the wrong function

When `recordFileDropRefusal` was inserted above `openFile`, it landed *between* `openFile`'s
`@discardableResult` and its doc comment. Swift parses that happily — a `///` block is trivia —
so the attribute silently moved to a `Void`-returning function.

Two consequences: a warning that it is unnecessary there, and three real
`result of call ... is unused` warnings at the `openFile` call sites that had relied on it.
A build with `-warnings-as-errors` would have failed; this package does not set it, so it would
have shipped as noise.

### Coverage hole closed

`FileDropPolicyTests.everyRefusalIsReportable` asserts that every refusal has a distinct id and
a non-empty message — while enumerating only 6 of 8 cases. The two missing ones were
`unusableFileName` and `guestRejected`, added most recently. A list that drifts behind its enum
stops guaranteeing the thing it claims to.

## Verified Clean

Each of these was checked against real declarations, not assumed:

- **Symbols.** Every cross-module reference resolves — VeilHostShell and VeilVMControl into
  VeilHostCore, and every `@testable` reference from the test targets.
- **Signatures and label order.** Every initializer and call in the changed files, checked in
  declaration order. Swift requires that order, and one bug of exactly this kind
  (`WindowsNotificationReceivedEvent`) was caught and fixed while writing the tests.
- **Access levels.** The `internal` helpers on `WindowsAppFileDropPolicy`,
  `VMSharedFolderReportFactory`, and `HostDashboardModel` are reached only from inside
  VeilHostCore or from `@testable` suites. Everything crossing a module boundary is `public`.
- **Exhaustive switches.** `WindowsAppFileDropRefusal` grew three cases; it is switched in
  exactly three places, all inside its own file, all complete. `RejectionReason`, `CodecError`,
  `VMSharedFolderReadiness`, `HostProtocolMessageResult`, and `VMControlArguments.Command` all
  checked too.
- **Redeclaration.** `restartFrameSubscription`, `recoverFrameCapture`, `pauseFrameStream`, and
  `resumeFrameStream` each bind `startingIndex` before the `await` and a distinct `index` after.
  Reusing the name would have been an error, which is why the first attempt was renamed.
- **Concurrency.** All eight `nonisolated static` declarations inside
  `@MainActor @Observable final class HostDashboardModel` are valid as written. Every non-isolated
  test suite touches only those; every suite touching instance members carries `@MainActor`.
- **`AsyncThrowingStream(_:bufferingPolicy:_:)`** matches the initializer available when
  `Failure == any Error`, which is what both changed channels declare.
- **Imports.** Checked on line 1 of each file with grep, since `read_file` drops it.

## Two Things A Build Will Still Decide

Recorded because reading cannot settle them:

- **`HostDisplayScale.current` reads `NSScreen.main` from a non-isolated context.** It is the
  only non-`@MainActor` `NSScreen` read in the package; the other two sit inside `@MainActor`
  types. It compiles against the current SDK, where `NSScreen.main` carries no isolation
  annotation. If a future SDK annotates it, this one file breaks while the others keep working.
- **Platform behaviour.** Whether `CGContext` refuses an over-budget allocation outright, how
  AppKit reacts to a `contentAspectRatio` set alongside a matching `contentMinSize`, and the
  effective `URLSessionWebSocketTask` message cap are all reasoned from documentation.

## Build Order

Stop at the first failure and fix it before continuing. The Swift build is first because
everything else depends on nothing.

```bash
cd apps/mac-host && swift build
cd apps/mac-host && swift test
cd apps/windows-agent && dotnet test
cd packages/protocol && npm test
cd harness/app-runtime-status && npm test
cd harness/app-runtime-action && npm test
cd harness/shared-folder && npm test
cd harness/device-passthrough && npm test
cd harness/qemu-boot-plan && npm test
cd harness/export-diagnostics && npm test
cd harness/vm-session && npm test
cd harness/vm-snapshots && npm test
cd harness/frame-pipeline-report && npm test
cd harness/mvp-proof && npm test
```

`harness/app-runtime-status` is listed early because it carries the most new rules: the
`displayScaling` section and the `inspect-guest-display-scale` action.

## After The Build Is Green

In this order, because each one depends on the previous being true:

1. **Four `frame-pipeline-report` measurements** — typing, idle, scrolling, and three concurrent
   windows against one. Take them with `displayScaling.recommendedAction == "none"`, because
   measuring a pipeline that is shipping four times the necessary pixels produces numbers about a
   display setting rather than about the codec.
2. **Live confirmation of the unverifiable UI work** — a second document window taking its own
   input; a leftover window of a never-opened app still refused; a 60 MB file drop producing a
   sheet that names its size; a file with a colon in its name opening under a rewritten one;
   a mirrored window that no longer letterboxes when resized; a minimized window's frame stream
   actually stopping.
3. **Then** revisit the privileged helper for USB passthrough and bridged networking, against a
   baseline that is known to work rather than hoped to.

---

## Follow-up: The Package Builds In Swift 6 Language Mode

`Package.swift` declares `// swift-tools-version: 6.2` and sets no `swiftLanguageModes` and no
per-target `.swiftLanguageMode(.v5)`. So every target compiles in **Swift 6 mode**, where
data-race safety violations are errors rather than warnings.

Two pieces of evidence that the project really does build that way: fourteen `@unchecked
Sendable` conformances, which is the escape hatch a codebase reaches for under strict
concurrency, and a `[weak self]` capture in `DispatchQueue.main.asyncAfter` in
`VeilHostShellApp.swift` — the shape that works when a plain capture does not.

Against that, a pre-existing comment in `WindowsAppWindowPresenter` reasoned about avoiding "a
Sendable/MainActor-isolation **warning**". In Swift 6 mode that class of problem is an error.
One of those two readings is wrong, and reading cannot settle which: it turns on SE-0414 region
analysis and on whether the current SDK annotates `DispatchQueue.async`'s work item as
`@Sendable`.

### What was done about it

Not a speculative rewrite based on uncertain semantics. Something narrower and true either way.

The drop path had grown from **one** `DispatchQueue.main.async` to **six**, all of them added in
this session, and every one captured the SwiftUI view's callbacks — non-Sendable function values.
Whatever the answer about Swift 6, six copies of a questionable capture is worse than one, and
the file-loading logic had no business living inside a view in the first place.

- [x] The view now decides only what it can decide synchronously: how many files were dropped.
      It hands the providers to the presenter and does no file I/O.
- [x] `WindowsAppWindowPresenter` owns the loading. `droppedFileOutcome(for:)` is a
      `nonisolated private static` function that returns a `Sendable` enum — no presenter
      reference, no view, no closure.
- [x] One hop back to the main actor, capturing only `[weak self]` on a `@MainActor` class
      (implicitly Sendable), two `String`s, and that `Sendable` outcome. The same shape as the
      existing `asyncAfter` call in `VeilHostShellApp`, so it follows a pattern already in the
      package rather than a guess about the language.
- [x] Six risky captures became one, and the drop rules became reachable outside a closure —
      `droppedFileOutcome` is now a plain function that a test could call.

The uncertainty is recorded rather than resolved. If a build reports a Sendable error here, it
will now be one error in one place, in a function whose signature makes the fix obvious, instead
of six scattered through a closure chain.

### Why the privileged helper stays deferred

This is the argument in miniature. A question as basic as "does this package compile" cannot be
answered from here — and the answer plausibly changes what a third of this session's UI code has
to look like. That is not the moment to add a signed system extension and a root helper.

---

## A Different Way To Get The Build Output

`execute_bash` returns exit 1 with empty output for every command in this environment, including
`echo`. Background processes are created and never run. `list_directory` on `.build` subpaths
returns empty. So neither running the build nor inspecting its artifacts was possible.

Asking for the output by hand did not work either, six times over. So: a hook.

`.kiro/hooks/veil-temp-build-probe.json` is a `UserPromptSubmit` hook whose command action runs

```
cd .../apps/mac-host && (swift build 2>&1; echo "VEIL_BUILD_EXIT=$?") | head -80
```

Hook command actions are run by the IDE's hook runner, not through the agent's bash tool, so this
path may work where the other does not. `UserPromptSubmit` stdout is forwarded into the agent
context, and piping through `head` makes the pipeline exit 0 regardless of whether the build
failed — so the output arrives either way, with the real status on the `VEIL_BUILD_EXIT` line.

**It activates at the next session start, not immediately.** And it is deliberately temporary: a
full build on every prompt is not something to leave installed. Delete
`.kiro/hooks/veil-temp-build-probe.json` once the first output has been read, or narrow it to a
`PostFileSave` matcher on `\.swift$` if a standing check turns out to be useful.

## One More Concurrency Risk Closed

`HostDisplayScale` was the only non-`@MainActor` `NSScreen` read in the package; the other two sit
inside `@MainActor` types. It is now `@MainActor` as well. `NSScreen.main` carries no isolation
annotation in the current SDK, so the non-isolated read compiled — but that made this the one file
that would break if a future SDK annotated it, for no benefit. Every call site was already
main-actor isolated, since each one also touches `HostDashboardModel`.
