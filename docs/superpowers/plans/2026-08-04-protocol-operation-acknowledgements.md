# Protocol Operation Acknowledgements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make state-changing input, clipboard, and frame-stream control operations return bounded, correlated success or error replies while preserving best-effort pointer movement and protocol v1 compatibility.

**Architecture:** Add a shared `operation.response` envelope and optional input `requestId`. The guest opts into success replies only when a request ID is present; the host requests and validates those replies for state-changing operations, while `input.mouse` movement stays fire-and-forget. Existing `error` messages remain the only failure envelope.

**Tech Stack:** JavaScript/Node protocol validators and fake-agent harness, C#/.NET 8 Windows agent, Swift macOS host, JSON fixtures, Swift Testing, xUnit.

## Global Constraints

- Keep protocol version at `1`; all request fields are additive.
- Do not acknowledge `input.mouse` with `event=move`.
- Do not retry clicks, key events, clipboard writes, or stream controls automatically.
- Guest-origin clipboard updates remain broadcast events without acknowledgements.
- A new guest sends success replies for previously fire-and-forget messages only when `requestId` is present.
- Guest platform `false` results become existing `error` envelopes with operation-specific codes.
- Update `docs/protocol.md`, protocol fixtures, validators, fake agent, host, and guest together.
- Do not commit Windows media, VM disks, signing material, or private guest data.

---

### Task 1: Shared Protocol Contract

**Files:**
- Modify: `packages/protocol/src/messages.mjs`
- Modify: `packages/protocol/test/messages.test.mjs`
- Modify: `harness/protocol-fixtures/input.mouse.left-down.json`
- Modify: `harness/protocol-fixtures/input.key.copy.json`
- Create: `harness/protocol-fixtures/operation.response.input-key.json`
- Modify: `harness/protocol-fixtures/README.md`
- Modify: `docs/protocol.md`

**Interfaces:**
- Produces: `MessageType.OperationResponse = "operation.response"`.
- Produces: `validateOperationResponse(response)` returning a validated object with `requestId: string`, `operation: string`, and `accepted: true`.
- Produces: optional non-empty `requestId` validation on `validateInputMouse` and `validateInputKey`.

- [ ] **Step 1: Add failing fixture and validator tests**

Add `operation.response.input-key.json`:

```json
{
  "type": "operation.response",
  "requestId": "req_key_1",
  "operation": "input.key",
  "accepted": true
}
```

Update `input.mouse.left-down.json` and `input.key.copy.json` with stable request IDs. Add tests that import `validateOperationResponse`, accept the fixture, reject `accepted=false`, reject mismatched/empty fields, and reject an explicitly empty input `requestId` while allowing it to be absent.

- [ ] **Step 2: Run the protocol test and verify RED**

Run: `node --test packages/protocol/test/messages.test.mjs`

Expected: FAIL because `OperationResponse` and `validateOperationResponse` do not exist.

- [ ] **Step 3: Implement the protocol validator**

Add the message type and validator:

```js
export function validateOperationResponse(response) {
  if (!response || response.type !== MessageType.OperationResponse) {
    throw new TypeError("Operation response must use type operation.response.");
  }
  requireNonEmptyString(response.requestId, "requestId", "Operation response");
  requireNonEmptyString(response.operation, "operation", "Operation response");
  if (response.accepted !== true) {
    throw new TypeError("Operation response field 'accepted' must be true; failures use error.");
  }
  return response;
}
```

For mouse/key validators, call `requireNonEmptyString` only when `requestId !== undefined`. Add the new fixture to the stable fixture list and document the compatibility and no-retry rules in `docs/protocol.md`.

- [ ] **Step 4: Run protocol tests and verify GREEN**

Run: `node --test packages/protocol/test/messages.test.mjs`

Expected: PASS.

- [ ] **Step 5: Commit the protocol contract**

```bash
git add packages/protocol harness/protocol-fixtures docs/protocol.md
git commit -m "Add protocol operation acknowledgements"
```

### Task 2: Fake-Agent Compatibility Contract

**Files:**
- Modify: `harness/fake-agent/src/session.mjs`
- Modify: `harness/fake-agent/test/session.test.mjs`
- Test: `harness/fake-agent/test/server.test.mjs`

**Interfaces:**
- Consumes: `operation.response` shape from Task 1.
- Produces: `createOperationResponse(message)` for request-ID-gated success replies.
- Produces: fake-agent behavior matching the real Windows agent for host integration tests.

- [ ] **Step 1: Replace no-reply expectations with failing compatibility tests**

Add tests for:

```js
assert.deepEqual(await session.handle({
  type: "input.key",
  requestId: "req_key_1",
  windowId: "hwnd:0003029A",
  event: "keyDown",
  key: "c",
  windowsVirtualKey: 67,
  modifiers: ["ctrl"]
}), [{
  type: "operation.response",
  requestId: "req_key_1",
  operation: "input.key",
  accepted: true
}]);
```

Cover mouse click, key, host clipboard, subscribe, and unsubscribe with request IDs. Keep separate legacy tests proving the same messages without request IDs return `[]`. Keep mouse `event=move` returning `[]` even when a request ID is supplied.

- [ ] **Step 2: Run fake-agent tests and verify RED**

Run: `node --test harness/fake-agent/test/*.test.mjs`

Expected: FAIL because successful operations still return no direct reply.

- [ ] **Step 3: Implement request-ID-gated responses**

Add:

```js
function operationAccepted(message) {
  if (!message.requestId || (message.type === "input.mouse" && message.event === "move")) {
    return [];
  }
  return [{
    type: "operation.response",
    requestId: message.requestId,
    operation: message.type,
    accepted: true
  }];
}
```

Return it only after the fake operation succeeds. Preserve `window_not_tracked` and validation errors.

- [ ] **Step 4: Run fake-agent tests and verify GREEN**

Run: `node --test harness/fake-agent/test/*.test.mjs`

Expected: PASS.

- [ ] **Step 5: Commit fake-agent behavior**

```bash
git add harness/fake-agent
git commit -m "Model operation acknowledgements in fake agent"
```

### Task 3: Windows Guest Acknowledgements and False-Result Errors

**Files:**
- Modify: `apps/windows-agent/src/VeilAgent/MessageTypes.cs`
- Modify: `apps/windows-agent/src/VeilAgent/AgentSession.cs`
- Create: `apps/windows-agent/tests/VeilAgent.Tests/AgentSessionOperationAcknowledgementTests.cs`

**Interfaces:**
- Consumes: `operation.response` contract from Task 1.
- Produces: `OperationResponse(string requestId, string operation)`.
- Produces: errors `input_mouse_rejected` and `input_key_rejected` when Windows `PostMessage` aggregation returns `false`.

- [ ] **Step 1: Add failing xUnit tests with a scripted desktop**

Create a test desktop whose input methods return configured booleans. Launch Notepad through `AgentSession.HandleAsync` to track its HWND, then assert:

```csharp
Assert.Equal("operation.response", reply["type"]!.GetValue<string>());
Assert.Equal("req_mouse_1", reply["requestId"]!.GetValue<string>());
Assert.Equal("input.mouse", reply["operation"]!.GetValue<string>());
Assert.True(reply["accepted"]!.GetValue<bool>());
```

Add corresponding key, clipboard, subscribe, and unsubscribe success tests; legacy no-request-ID tests; mouse-move no-ACK test; and false-result tests expecting `input_mouse_rejected` / `input_key_rejected`.

- [ ] **Step 2: Run the Windows agent test and verify RED when SDK is available**

Run: `dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj --filter AgentSessionOperationAcknowledgementTests`

Expected with .NET 8 installed: FAIL because operation responses and false-result conversion do not exist. If `dotnet` is unavailable, record the exact blocker and continue with source plus cross-platform harness verification; do not claim this test passed.

- [ ] **Step 3: Implement guest responses after successful operations**

Add `MessageTypes.OperationResponse`. Add helpers:

```csharp
private static AgentReplies OperationAccepted(string? requestId, string operation)
    => string.IsNullOrWhiteSpace(requestId)
        ? AgentReplies.Direct()
        : AgentReplies.Direct(OperationResponse(requestId, operation));

private static JsonObject OperationResponse(string requestId, string operation) => new()
{
    ["type"] = MessageTypes.OperationResponse,
    ["requestId"] = requestId,
    ["operation"] = operation,
    ["accepted"] = true
};
```

Use this after successful clipboard and stream-control operations. For key and non-move mouse input, inspect the returned bool; return the operation-specific error on `false`. Always leave mouse move without a success reply.

- [ ] **Step 4: Run available Windows agent verification**

Run when available:

```bash
dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj --filter AgentSessionOperationAcknowledgementTests
dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj
```

Expected: PASS. Otherwise preserve the exact `dotnet`-unavailable evidence for the final checklist.

- [ ] **Step 5: Commit guest behavior**

```bash
git add apps/windows-agent
git commit -m "Acknowledge guest control operations"
```

### Task 4: macOS Host Correlation and Bounded Waiting

**Files:**
- Modify: `apps/mac-host/Sources/VeilHostCore/ProtocolMessages.swift`
- Modify: `apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/ProtocolMessageTests.swift`
- Modify: `apps/mac-host/Tests/VeilHostCoreTests/VeilHostClientTests.swift`

**Interfaces:**
- Consumes: `operation.response` from Tasks 1 and 3.
- Produces: `OperationResponse` Swift model.
- Produces: correlated `acknowledgedOperation(_:operation:requestId:)` request helper.
- Preserves: `sendMouseInput(_:)`, `sendKeyInput(_:)`, `sendClipboardText(_:)`, `subscribeWindowFrames(windowId:)`, and `unsubscribeWindowFrames(windowId:)` public signatures.

- [ ] **Step 1: Add failing Swift message and client tests**

Assert that `OperationResponse` decodes the stable shape. Replace no-reply client tests so key, click/scroll mouse, clipboard, subscribe, and unsubscribe provide matching operation replies and assert `expectedReplyCounts == [1]`. Assert move mouse still uses `[0]`. Add tests for protocol `error`, mismatched request ID, mismatched operation, and `accepted=false` validation failures.

Extend `RecordingTransport` to record sent request IDs:

```swift
if let requestId = object?["requestId"] as? String {
    sentRequestIds.append(requestId)
}
```

- [ ] **Step 2: Run focused Swift tests and verify RED**

Run:

```bash
swift test --package-path apps/mac-host --filter ProtocolMessageTests
swift test --package-path apps/mac-host --filter VeilHostClientTests
```

Expected: FAIL because the host does not model or wait for operation responses.

- [ ] **Step 3: Implement request IDs and response validation**

Add `MessageType.operationResponse` and:

```swift
public struct OperationResponse: Codable, Equatable, Sendable {
    public var type: MessageType
    public var requestId: String
    public var operation: MessageType
    public var accepted: Bool
}
```

Add optional `requestId` to `InputMouseEvent` and `InputKeyEvent`, preserving default `nil`. In `VeilHostClient`, copy the input with a generated request ID for acknowledged events, send with `expectedReplies: 1`, decode protocol errors first, then require matching request ID, operation, and `accepted=true`. Mouse move sends the original event with `expectedReplies: 0`.

- [ ] **Step 4: Run focused Swift tests and verify GREEN**

Run the two focused commands from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit host behavior**

```bash
git add apps/mac-host/Sources/VeilHostCore/ProtocolMessages.swift apps/mac-host/Sources/VeilHostCore/VeilHostClient.swift apps/mac-host/Tests/VeilHostCoreTests/ProtocolMessageTests.swift apps/mac-host/Tests/VeilHostCoreTests/VeilHostClientTests.swift
git commit -m "Wait for guest operation acknowledgements"
```

### Task 5: Regression Verification and Roadmap Evidence

**Files:**
- Modify: `docs/checklists/2026-08-02-missing-functionality.md`
- Create: `docs/checklists/2026-08-04-protocol-operation-acknowledgements.md`

**Interfaces:**
- Consumes: verified protocol, fake-agent, guest, and host behavior from Tasks 1-4.
- Produces: durable evidence for the P1 protocol reliability roadmap item and explicit .NET/live-guest limitations.

- [ ] **Step 1: Run complete local regression suites**

Run:

```bash
node --test packages/protocol/test/*.test.mjs
node --test harness/fake-agent/test/*.test.mjs
node --test harness/fake-host/test/*.test.mjs
swift test --package-path apps/mac-host
```

Run the full Windows agent test suite if `dotnet` is available. Expected: all available suites PASS.

- [ ] **Step 2: Run application build verification**

Run: `./script/build_and_run.sh --verify`

Expected: signed development bundle builds and launch-contract verification passes.

- [ ] **Step 3: Record evidence without overstating live proof**

Mark `fire-and-forget input/clipboard/frame-control messages` complete in the missing-functionality checklist. Keep live Windows validation distinct. In the new checklist record exact commands, pass counts, .NET availability, and that mouse move remains intentionally unacknowledged.

- [ ] **Step 4: Run final hygiene checks**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended evidence files remain uncommitted. Read the completed checklist once to confirm every statement names concrete evidence or an explicit limitation.

- [ ] **Step 5: Commit verification evidence**

```bash
git add docs/checklists/2026-08-02-missing-functionality.md docs/checklists/2026-08-04-protocol-operation-acknowledgements.md
git commit -m "Verify protocol operation acknowledgements"
```

### Task 6: Publish and Merge

**Files:**
- No source changes expected.

**Interfaces:**
- Produces: pushed `codex/protocol-operation-acks-v11` and merged `develop`.

- [ ] **Step 1: Confirm clean feature branch and recent commits**

Run: `git status --short --branch && git log --oneline -7`

Expected: clean branch tracking its remote with design, plan, implementation, and verification commits.

- [ ] **Step 2: Push the feature branch**

Run: `git push origin codex/protocol-operation-acks-v11`

Expected: remote branch advances successfully.

- [ ] **Step 3: Merge into the clean develop worktree**

In the verified clean develop worktree, run:

```bash
git fetch origin
git merge --no-ff codex/protocol-operation-acks-v11 -m "Merge protocol operation acknowledgements"
```

Expected: merge succeeds without touching the user's original dirty workspace.

- [ ] **Step 4: Verify merged develop and push**

Run the focused protocol, fake-agent, and Swift tests against merged `develop`, then run `git push origin develop`.

Expected: tests pass and `origin/develop` points at the merge commit.
