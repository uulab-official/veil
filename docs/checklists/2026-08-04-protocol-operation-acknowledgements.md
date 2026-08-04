# Protocol Operation Acknowledgements — Verification Evidence

Date: 2026-08-04

Scope: integration verification for the protocol operation acknowledgement rollout through commit `751ab42`. This records automated contract evidence only; it does not replace a live Windows guest proof.

## Completed automated evidence

- [x] `node --test packages/protocol/test/*.test.mjs` — exit 0; 30 tests passed, 0 failed.
- [x] `node --test harness/fake-agent/test/*.test.mjs` — exit 0; 31 tests passed, 0 failed.
- [x] `node --test harness/fake-host/test/*.test.mjs` — exit 0; 8 tests passed, 0 failed. The first exact invocation was blocked before tests ran because this clean worktree lacked the ignored `harness/fake-host/node_modules` dependencies (`ws` and `@veil/protocol`). `npm ci --prefix harness/fake-host` restored the pinned lockfile dependencies; the exact command then passed.
- [x] `swift test --package-path apps/mac-host` — exit 0; 418 tests in 27 suites passed.
- [x] `./script/build_and_run.sh --verify` — exit 0; built the development `veil-host-shell`, rebuilt and ad-hoc signed `dist/Veil.app`, and completed the script's launch-report contract verification and cleanup.

The automated protocol, fake-agent, fake-host, and Swift host coverage proves the acknowledgement contract: accepted click/key/clipboard/frame-control operations, structured failure/timeout handling, request and operation matching, and no automatic retry of these non-idempotent actions.

## Explicit limitations

- [ ] Windows-agent xUnit was not run. `dotnet test apps/windows-agent/tests/VeilAgent.Tests/VeilAgent.Tests.csproj` exited 127 with `zsh:1: command not found: dotnet`; this environment has no .NET SDK.
- [ ] No live Windows guest/VM proof was run in this task. The automated harness proves the contract, not guest platform delivery or guest-to-host transport behavior in a real Windows VM.
- [x] `input.mouse` with `event: "move"` remains intentionally unacknowledged, including when it has a request ID, as required by `docs/protocol.md`.

## Roadmap evidence boundary

- [x] The P1 `fire-and-forget input/clipboard/frame-control 메시지에 bounded acknowledgement 또는 오류 수신 경로 추가` item is complete based on the automated contract evidence above.
- [ ] This does not complete any live-validation item, the Windows-agent `dotnet test` item, or any other P1/P2 roadmap work.
