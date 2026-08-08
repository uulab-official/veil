# Frame Stream Liveness and Duplicate Encode Elimination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop encoding and sending duplicate full-window PNG frames while a Windows app is visually unchanged, without making the macOS host mistake an idle window for a broken stream.

**Architecture:** Keep the existing `window.frame` JSON/full-PNG path as the compatibility path. Add a payload-free `window.frame.unchanged` heartbeat, a guest-side pixel change tracker, and an adaptive capture cadence. The host records real image arrival separately from stream activity, so rendering and latency evidence retain their current meaning while recovery uses the activity clock. Binary frame transport and changed-region tiles are deliberately deferred to a later contract-complete slice.

**Tech Stack:** C#/.NET 8 Windows agent, Swift 6.2 host core, JavaScript protocol package, xUnit, Swift Testing, Node test runner.

## Global Constraints

- Work only in `/private/tmp/veil-production-grade-20260808` on `codex/production-grade-target`; do not edit the user's dirty checkout.
- Follow red-green-refactor for each task: add the focused failing assertion, run it and record the intended failure, implement the smallest behavior, then rerun green.
- Preserve the existing `window.frame` fields and full-PNG behavior for changed frames. This slice must not require a binary frame channel or compositor.
- An unchanged heartbeat is liveness evidence only. It must not replace the displayed image, increment the real frame count, refresh image-age evidence, or satisfy the first-frame requirement.
- A capture exception is not an unchanged heartbeat. The host must still detect a capture path that has stopped producing evidence.
- Retained pixel buffers must be bounded to one buffer per actively streamed window and released on replacement, unsubscribe, close, cancellation, and unexpected stream termination.
- Keep protocol docs, fixtures, executable validators, C# message names, and Swift message types synchronized in the same implementation series.
- Use the bundled .NET executable at `/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet`; do not depend on shell `PATH` or a mutable home-directory variable.
- Do not claim Phase 0 complete from this slice alone. Phase 0 still requires all candidate slices integrated, three consecutive clean full-gate passes, and no dependency on untracked files.

---

## Task 1: Define the unchanged-frame protocol contract

**Files:**

- Create: `harness/protocol-fixtures/window.frame.unchanged.json`
- Modify: `harness/protocol-fixtures/README.md`
- Modify: `packages/protocol/src/messages.mjs`
- Test: `packages/protocol/test/messages.test.mjs`
- Modify: `docs/protocol.md`

### Step 1: Write the failing protocol tests

Import `validateWindowFrameUnchanged`, add the fixture to the stable-fixture table, then add these cases:

```js
test("validates one unchanged window frame heartbeat fixture", async () => {
  const event = validateWindowFrameUnchanged(await readFixture("window.frame.unchanged.json"));

  assert.equal(event.type, MessageType.WindowFrameUnchanged);
  assert.equal(event.windowId, "hwnd:0003029A");
  assert.equal(event.sequence, 42);
  assert.equal(event.capturedAt, "2026-07-31T09:14:02Z");
});

test("rejects an unchanged frame heartbeat that carries image data", async () => {
  const event = await readFixture("window.frame.unchanged.json");
  event.encodedData = "iVBORw0KGgo=";

  assert.throws(() => validateWindowFrameUnchanged(event), /must not carry image data/);
});

test("rejects an unchanged frame heartbeat without a valid capture timestamp", async () => {
  const event = await readFixture("window.frame.unchanged.json");
  event.capturedAt = "not-a-date";

  assert.throws(() => validateWindowFrameUnchanged(event), /capturedAt/);
});
```

Create the fixture with exactly this payload:

```json
{
  "type": "window.frame.unchanged",
  "windowId": "hwnd:0003029A",
  "sequence": 42,
  "capturedAt": "2026-07-31T09:14:02Z"
}
```

### Step 2: Run the focused test and confirm RED

Run:

```bash
npm test --prefix packages/protocol
```

Expected: failure because `WindowFrameUnchanged` and `validateWindowFrameUnchanged` do not exist.

### Step 3: Implement the protocol validator

Add `WindowFrameUnchanged: "window.frame.unchanged"` to `MessageType`. Add a validator that requires:

```js
export function validateWindowFrameUnchanged(event) {
  if (!event || event.type !== MessageType.WindowFrameUnchanged) {
    throw new TypeError("Unchanged window frame event must use type window.frame.unchanged.");
  }

  requireNonEmptyString(event.windowId, "windowId", "Unchanged window frame event");
  requirePositiveInteger(event.sequence, "sequence", "Unchanged window frame event");
  requireNonEmptyString(event.capturedAt, "capturedAt", "Unchanged window frame event");
  if (Number.isNaN(Date.parse(event.capturedAt))) {
    throw new TypeError("Unchanged window frame event field 'capturedAt' must be an ISO date.");
  }
  if (event.encodedData !== undefined) {
    throw new TypeError("Unchanged window frame event must not carry image data.");
  }
  return event;
}
```

Document the fixture in the fixture README and add a `Window Frame Unchanged` section to `docs/protocol.md` that states:

- the heartbeat is valid only for a tracked window;
- it carries no image payload;
- the host advances activity time, not displayed-frame time;
- it is ignored before the first real frame;
- capture errors do not emit it.

### Step 4: Run the focused test and confirm GREEN

Run:

```bash
npm test --prefix packages/protocol
```

Expected: all protocol tests pass.

### Step 5: Commit the protocol contract

```bash
git add harness/protocol-fixtures/window.frame.unchanged.json harness/protocol-fixtures/README.md packages/protocol/src/messages.mjs packages/protocol/test/messages.test.mjs docs/protocol.md
git commit -m "feat(protocol): add unchanged frame heartbeat"
git push
```

---

## Task 2: Detect duplicate guest frames and adapt capture cadence

**Files:**

- Create: `apps/windows-agent/src/VeilAgent/WindowFrameChangeTracker.cs`
- Create: `apps/windows-agent/src/VeilAgent/WindowFrameStreamCadence.cs`
- Modify: `apps/windows-agent/src/VeilAgent/WindowModels.cs`
- Modify: `apps/windows-agent/src/VeilAgent/IWindowFrameCapture.cs`
- Modify: `apps/windows-agent/src/VeilAgent/GdiWindowFrameCapture.cs`
- Modify: `apps/windows-agent/src/VeilAgent/WindowFrameStreamer.cs`
- Create: `apps/windows-agent/tests/VeilAgent.Tests/WindowFrameChangeTrackerTests.cs`
- Create: `apps/windows-agent/tests/VeilAgent.Tests/WindowFrameStreamCadenceTests.cs`
- Modify: `apps/windows-agent/tests/VeilAgent.Tests/WindowFrameStreamerTests.cs`

### Step 1: Write failing change-tracker tests

Cover these invariants in `WindowFrameChangeTrackerTests.cs`:

```csharp
[Fact]
public void FirstBufferIsChangedAndIdenticalBufferIsUnchanged()
{
    var tracker = new WindowFrameChangeTracker();

    Assert.True(tracker.HasChanged("hwnd:1", [1, 2, 3, 4]));
    Assert.False(tracker.HasChanged("hwnd:1", [1, 2, 3, 4]));
}

[Fact]
public void ChangedBytesAndChangedDimensionsProduceAFrame()
{
    var tracker = new WindowFrameChangeTracker();
    tracker.HasChanged("hwnd:1", [1, 2, 3, 4]);

    Assert.True(tracker.HasChanged("hwnd:1", [1, 9, 3, 4]));
    Assert.True(tracker.HasChanged("hwnd:1", [1, 9, 3, 4, 5]));
}

[Fact]
public void ForgetMakesTheNextBufferAChangedFirstFrame()
{
    var tracker = new WindowFrameChangeTracker();
    tracker.HasChanged("hwnd:1", [1, 2, 3, 4]);
    Assert.False(tracker.HasChanged("hwnd:1", [1, 2, 3, 4]));

    tracker.Forget("hwnd:1");

    Assert.True(tracker.HasChanged("hwnd:1", [1, 2, 3, 4]));
}
```

Also prove that two window IDs keep independent buffers.

### Step 2: Write failing cadence and streamer tests

In `WindowFrameStreamCadenceTests.cs`, prove:

- it starts at 33 ms;
- it remains active while frames change;
- it backs off to 250 ms only after the configured unchanged threshold;
- one changed frame immediately returns it to 33 ms;
- the unchanged counter does not overflow during a long idle period.

In `WindowFrameStreamerTests.cs`, retain the existing capture-failure test and add:

```csharp
[Fact]
public async Task EmitsHeartbeatWithoutResendingAnUnchangedFrame()
{
    // Fake capture returns Changed(frame_000001), then Unchanged(sequence: 2).
    // Cancel from onUnchanged.
    // Assert exactly one real frame and one heartbeat sequence 2.
}

[Fact]
public async Task CaptureFailureDoesNotPretendTheWindowWasUnchanged()
{
    // Fake capture throws once, then returns a real frame.
    // Assert onUnchanged was never invoked.
}
```

Keep the `onFrame` callback typed as `Func<WindowFrame, CancellationToken, Task>`. This explicitly avoids the broken candidate contract that passed `WindowFrameCaptureResult` into callers and tests expecting `WindowFrame`.

### Step 3: Run the focused tests and confirm RED

Run:

```bash
"/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj --filter "FullyQualifiedName~WindowFrameChangeTrackerTests|FullyQualifiedName~WindowFrameStreamCadenceTests|FullyQualifiedName~WindowFrameStreamerTests"
```

Expected: compile failures for the missing tracker, cadence, and capture-result APIs.

### Step 4: Implement the pure change tracker and cadence

`WindowFrameChangeTracker` stores a copied byte array per window behind a lock. `HasChanged` returns `false` only when the retained and current buffers have equal lengths and `SequenceEqual`; otherwise it replaces the retained copy and returns `true`. `Forget` removes exactly one window.

Implement `WindowFrameStreamCadence` as a timer-free state machine with:

```csharp
public static readonly TimeSpan DefaultActiveInterval = TimeSpan.FromMilliseconds(33);
public static readonly TimeSpan DefaultIdleInterval = TimeSpan.FromMilliseconds(250);
public const int DefaultUnchangedTicksBeforeIdle = 15;
```

`Next(changed: true)` resets the counter immediately. `Next(changed: false)` increments only up to the threshold.

### Step 5: Add a backward-compatible capture-result seam

Add this result type to `WindowModels.cs`:

```csharp
public sealed record WindowFrameCaptureResult(WindowFrame? Frame, int Sequence)
{
    public bool IsUnchanged => Frame is null;
    public static WindowFrameCaptureResult Changed(WindowFrame frame) => new(frame, frame.Sequence);
    public static WindowFrameCaptureResult Unchanged(int sequence) => new(null, sequence);
}
```

Extend `IWindowFrameCapture` with default implementations so existing fakes remain source-compatible:

```csharp
async Task<WindowFrameCaptureResult> CaptureFrameResultAsync(
    LaunchedWindow window,
    int sequence,
    CancellationToken cancellationToken
) => WindowFrameCaptureResult.Changed(
    await CaptureFrameAsync(window, sequence, cancellationToken)
);

void ForgetWindow(string windowId) { }
```

### Step 6: Skip the encode in `GdiWindowFrameCapture`

Refactor capture into these operations:

1. obtain bounds and capture one `Bitmap` with the existing `PrintWindow`/screen-copy fallback;
2. copy only the `width * 4` bytes from each locked ARGB row into a contiguous array;
3. call `WindowFrameChangeTracker.HasChanged(windowId, pixels)`;
4. return `WindowFrameCaptureResult.Unchanged(sequence)` without creating a PNG stream or base64 string when equal;
5. otherwise encode the already captured bitmap through the existing `WindowFrame` schema;
6. delegate `ForgetWindow` to the tracker.

Keep `CaptureFrameAsync` as an unconditional full capture for existing direct callers. The optimized path is `CaptureFrameResultAsync`.

### Step 7: Add adaptive behavior without changing the frame callback

Change `WindowFrameStreamer.StreamAsync` to:

```csharp
public async Task StreamAsync(
    LaunchedWindow window,
    int firstSequence,
    Func<WindowFrame, CancellationToken, Task> onFrame,
    CancellationToken cancellationToken,
    Func<int, CancellationToken, Task>? onUnchanged = null
)
```

Use one `PeriodicTimer`, retune its `Period` only in production adaptive mode, and preserve an explicitly supplied fixed interval for deterministic tests. Behavior per tick:

- exception or timeout: back off cadence, emit neither frame nor heartbeat, do not increment sequence;
- unchanged: invoke `onUnchanged(sequence)` when supplied, back off cadence, do not increment sequence;
- changed: invoke `onFrame(result.Frame!)`, increment sequence once, return cadence to active.

Expose `ForgetWindow(windowId)` as a pass-through to the capture implementation.

### Step 8: Run focused and complete agent tests

Run:

```bash
"/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj --filter "FullyQualifiedName~WindowFrameChangeTrackerTests|FullyQualifiedName~WindowFrameStreamCadenceTests|FullyQualifiedName~WindowFrameStreamerTests"
"/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj
```

Expected: all focused and all Windows Agent tests pass.

### Step 9: Commit the guest capture slice

```bash
git add apps/windows-agent/src/VeilAgent apps/windows-agent/tests/VeilAgent.Tests
git commit -m "perf(agent): suppress duplicate window frames"
git push
```

---

## Task 3: Broadcast heartbeats and release capture state on every exit

**Files:**

- Modify: `apps/windows-agent/src/VeilAgent/MessageTypes.cs`
- Modify: `apps/windows-agent/src/VeilAgent/AgentSession.cs`
- Modify: `apps/windows-agent/src/VeilAgent/WebSocketAgentServer.cs`
- Create: `apps/windows-agent/tests/VeilAgent.Tests/AgentRepliesTests.cs`
- Modify: `harness/windows-agent-contract/test/windows-agent-contract.test.mjs`

### Step 1: Write failing serialization and source-contract tests

Add an `AgentRepliesTests` assertion for a deterministic timestamp:

```csharp
var json = AgentReplies.SerializeUnchangedFrame(
    "hwnd:0003029A",
    42,
    new DateTimeOffset(2026, 7, 31, 0, 14, 2, TimeSpan.Zero)
);
var message = JsonNode.Parse(json)!.AsObject();

Assert.Equal("window.frame.unchanged", message["type"]!.GetValue<string>());
Assert.Equal("hwnd:0003029A", message["windowId"]!.GetValue<string>());
Assert.Equal(42, message["sequence"]!.GetValue<int>());
Assert.Equal("2026-07-31T00:14:02.0000000+00:00", message["capturedAt"]!.GetValue<string>());
Assert.Null(message["encodedData"]);
```

Extend the Windows Agent contract harness to require the C# `WindowFrameUnchanged` constant and the server's heartbeat serializer call.

### Step 2: Run tests and confirm RED

Run:

```bash
"/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj --filter FullyQualifiedName~AgentRepliesTests
npm test --prefix harness/windows-agent-contract
```

Expected: failures because the constant, serializer, and server callback do not exist.

### Step 3: Implement serialization and server wiring

Add `MessageTypes.WindowFrameUnchanged`. Add:

```csharp
public static string SerializeUnchangedFrame(
    string windowId,
    int sequence,
    DateTimeOffset? capturedAt = null
)
```

Serialize `type`, `windowId`, `sequence`, and `(capturedAt ?? DateTimeOffset.UtcNow).ToString("O")`; never serialize image data.

In `StartFrameStream`:

- call `frameStreamer.ForgetWindow(window.WindowId)` before starting so a replacement always emits a real first frame;
- pass an `onUnchanged` callback that broadcasts `SerializeUnchangedFrame`;
- call `ForgetWindow` in `finally` after removing the stream;
- call `ForgetWindow` in `StopFrameStream` even when the dictionary entry is already absent.

The changed-frame callback remains the existing `AgentReplies.SerializeFrame(frame)` path.

### Step 4: Run focused and complete agent/contract tests

Run:

```bash
"/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj
npm test --prefix harness/windows-agent-contract
```

Expected: all tests pass.

### Step 5: Commit the server integration

```bash
git add apps/windows-agent/src/VeilAgent apps/windows-agent/tests/VeilAgent.Tests harness/windows-agent-contract
git commit -m "feat(agent): broadcast frame liveness heartbeats"
git push
```

---

## Task 4: Separate displayed-frame age from host stream liveness

**Files:**

- Modify: `apps/mac-host/Sources/VeilHostCore/ProtocolMessages.swift`
- Modify: `apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`

### Step 1: Write failing host behavior tests

Add tests proving:

1. after a real frame at `t=2000` and heartbeat at `t=2009.75`, the displayed frame stays unchanged, `latestFrameReceivedAt` stays at `t=2000`, `latestActivityAt` becomes `t=2009.75`, real-frame count remains 1, heartbeat count becomes 1, and a report at `t=2010` is fresh;
2. a heartbeat before the first real frame is ignored and the session stays `waitingForFirstFrame`;
3. a heartbeat for an unknown window is ignored;
4. `receiveProtocolMessage` routes `window.frame.unchanged` and returns `.handledWindowFrameUnchanged`.

Use a private test helper that creates:

```swift
WindowFrameUnchangedEvent(
    windowId: "hwnd:0003029A",
    sequence: sequence,
    capturedAt: "2026-07-31T09:14:02Z"
)
```

### Step 2: Run the focused tests and confirm RED

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter HostDashboardModelTests
```

Expected: compile failures for the new message and liveness fields.

### Step 3: Add the Swift message contract

Add `.windowFrameUnchanged = "window.frame.unchanged"` to `MessageType` and define:

```swift
public struct WindowFrameUnchangedEvent: Codable, Equatable, Sendable {
    public var type: MessageType
    public var windowId: String
    public var sequence: Int
    public var capturedAt: String

    public init(
        type: MessageType = .windowFrameUnchanged,
        windowId: String,
        sequence: Int,
        capturedAt: String
    ) {
        self.type = type
        self.windowId = windowId
        self.sequence = sequence
        self.capturedAt = capturedAt
    }
}
```

### Step 4: Split image timing from activity timing

Extend `WindowFrameTiming` with:

```swift
public var latestActivityAt: Date
public var unchangedHeartbeatCount: Int
```

Give initializer defaults of `latestFrameReceivedAt` and `0` respectively so stored/demo call sites remain source-compatible. `receiveWindowFrame` sets both frame time and activity time to the real frame's receive time. `WindowFrameStreamAssessment.assess` derives fresh/delayed/stale from `latestActivityAt`, while `latestFrameAgeMilliseconds` continues to use `latestFrameReceivedAt`.

Add `receiveWindowFrameUnchanged` that requires an existing session with a real-frame timing record, advances only `latestActivityAt`, increments only `unchangedHeartbeatCount`, and returns whether it accepted the heartbeat.

Route the new enum case in `receiveProtocolMessage`. Add `.handledWindowFrameUnchanged(windowId:)` to the result enum.

Expose `latestActivityAgeMilliseconds` and `unchangedHeartbeatCount` in `WindowsAppRuntimeWindowStatus` so diagnostics can distinguish healthy idle windows from frozen capture without opening raw logs.

### Step 5: Run focused and complete Swift tests

Run:

```bash
swift test --disable-sandbox --package-path apps/mac-host --filter HostDashboardModelTests
swift test --disable-sandbox --package-path apps/mac-host
```

Expected: focused and all Swift tests pass.

### Step 6: Commit the host integration

```bash
git add apps/mac-host/Sources/VeilHostCore/ProtocolMessages.swift apps/mac-host/Sources/VeilHostCore/HostDashboardModel.swift apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift
git commit -m "feat(host): track idle frame stream liveness"
git push
```

---

## Task 5: Record evidence and run the complete integration gate

**Files:**

- Create: `docs/checklists/2026-08-08-frame-stream-liveness.md`

### Step 1: Create the evidence checklist

Record:

- the problem and scope boundary;
- each focused red failure and green command;
- unchanged heartbeat protocol fields;
- changed-frame backward compatibility;
- pixel-buffer lifecycle behavior;
- full gate command and result;
- explicit deferral of binary channel, damage-region tiles, real-VM CPU/latency measurement, and Phase 0 completion.

### Step 2: Run static checks

Run:

```bash
git diff --check
git status --short
rg -n "window\.frame\.unchanged|WindowFrameUnchanged" apps packages harness docs
```

Expected: no whitespace errors; every protocol layer contains the same message name; only intended files are modified.

### Step 3: Run the complete repository gate

Run:

```bash
VEIL_DOTNET_BIN="/Users/uulab/Library/Application Support/Veil/Toolchains/dotnet8/dotnet" ./script/test_all.sh
```

Expected: Swift, Windows Agent, Node packages, macOS bundle/launch, and install lifecycle all pass. If the gate exposes unrelated baseline flakiness, record the exact failing test and rerun only to classify it; do not silently label a retry as the original pass.

### Step 4: Update the checklist with measured output

Replace planned counts with the actual test counts and command timestamps. Mark real-VM performance measurement `BLOCKED` until the live Windows reference environment is exercised.

### Step 5: Commit and push the evidence

```bash
git add docs/checklists/2026-08-08-frame-stream-liveness.md
git commit -m "docs(checklist): record frame liveness verification"
git push
```

### Step 6: Verify branch state

Run:

```bash
git status --short --branch
git log --oneline --decorate -8
git rev-list --left-right --count origin/codex/production-grade-target...HEAD
```

Expected: clean branch, all implementation commits visible, and `0 0` divergence after push.

---

## Completion Criteria for This Slice

- Static windows emit heartbeats without repeated PNG/base64 output.
- Changed windows still emit the existing full `window.frame` JSON shape.
- Capture failures emit no false liveness.
- Replacement and shutdown release retained pixel buffers and force a real first frame next time.
- Host recovery uses activity age while image latency evidence continues to use real frame age.
- Protocol, agent, host, fixture, docs, and harness tests pass together.
- Full repository gate passes once from the isolated clean worktree.
- Phase 0 and overall production readiness remain explicitly incomplete until their broader evidence gates pass.
