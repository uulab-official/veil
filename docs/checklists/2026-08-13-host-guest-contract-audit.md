# Host/Guest Contract Audit

Date: 2026-08-13

A systematic pass over every host→guest message, comparing `docs/protocol.md`, the host's
Swift sender, and the guest's C# handler. Prompted by two bugs found the same way the day
before: the host was sending a file name the guest was documented to reject, and the guest's
structured rejections were being reported as a broken runtime.

The result is worse than "a few unvalidated fields". **Six of the nine host→guest messages
cannot receive an error at all**, by construction.

## The Structural Problem

`URLSessionWebSocketTransport.send` (`WebSocketTransport.swift:19-32`) opens a **new
WebSocket per message** and closes it in a `defer` immediately after writing:

```swift
let task = session.webSocketTask(with: url)
task.resume()
defer { task.cancel(with: .normalClosure, reason: nil) }
try await task.send(.data(message))
var replies: [Data] = []
while replies.count < expectedReplies { ... }
```

With `expectedReplies: 0` the loop body never runs and the socket closes. These six callers
all pass `0` (`VeilHostClient.swift:1139-1177`): `sendMouseInput`, `sendKeyInput`,
`sendTextInput`, `sendClipboardText`, `subscribeWindowFrames`, `unsubscribeWindowFrames`.

Every guest error on those paths is therefore unobservable: `window_not_tracked`,
`text_too_long`, `invalid_message`, `input_text_failed`, `input_mouse_failed`,
`input_key_failed`, `clipboard_text_failed`, `handler_failed`.

`protocol.md:625` permits fire-and-forget ("Invalid requests may still return structured
errors"), but with no path to read one, that sentence describes dead protocol surface.

A second consequence of one-socket-per-message: **messages have no ordering guarantee at the
guest.** Each arrives on its own connection and is handled independently.

## Fixed Now

### ⌘V could paste stale text with no indication

The worst finding, because it corrupts a document rather than failing.

`onPasteShortcut` wrote the Mac clipboard into Windows and then posted Ctrl+V
unconditionally. Ctrl+V cannot fail in a way anyone notices — it pastes whatever Windows had
before.

The clipboard write fails routinely. `WindowsDesktop.OpenClipboardWithRetry`
(`WindowsDesktop.cs:713-724`) retries 10 times at 25 ms and then throws — a 250 ms budget
that any clipboard manager, Office, or browser mid-copy can beat. The guest reports
`clipboard_text_failed` (`AgentSession.cs:592-594`), which the host cannot read.

And because the two messages travel on separate connections while the clipboard write retries
for up to 250 ms and a posted key message is immediate, the race is not occasional — when the
clipboard is contended it is **systematically lost**.

- [x] `sendHostClipboardText` returns `HostClipboardSendOutcome` instead of `Void`.
- [x] The paste path cancels Ctrl+V on `.failed` and shows a sheet on the window, rather than
      completing the paste with the wrong content.
- [x] `.skipped` is distinct from `.failed`. A connection with no clipboard capability still
      allows the paste, because the guest clipboard may hold exactly what the user copied
      inside Windows. Collapsing the two would have broken Windows-internal copy-paste.
- [x] The loop-prevention sequence does not advance on failure. It previously advanced on
      *transport* success, recording a host update the guest may never have taken, which could
      make the next genuine guest clipboard change look like an echo.

This does not make ⌘V correct. It makes it **honest**: it either pastes the right text or says
it did not paste. Correctness needs the guest to acknowledge the write — see below.

### `phase = .failed` reported unrelated failures as a lost connection

`.failed` is documented as reserved for "a user-triggered action that failed outright"
(`HostDashboardModel.swift:315-317`). What the enum comment does not say is that `.failed`
renders as **"Connection failed"** in the runtime status line, which feeds the menu bar title
(`HostDashboardModel.swift:1787-1788`).

- [x] `restartFrameSubscription` no longer sets it. That is background frame-stream
      maintenance, not a user action at all — a retry loop that could not resubscribe was
      putting the whole model into a failed phase.
- [x] `openFile` no longer sets it (fixed 2026-08-12); it restores the entering phase.

## Not Fixed: Needs A Compiler

### 1. Give fire-and-forget messages a way to see an error

Nothing else in this report is observable until this exists. The obvious fix has a trap:
`AgentSession.HandleClipboardTextSetAsync` returns `AgentReplies.Direct()` with **no
arguments** on success, meaning the guest sends nothing at all. So raising `expectedReplies`
to 1 would hang every paste forever.

Two options, both needing verification:

**(a) Bounded error drain, host-only.** After sending, race `task.receive()` against a short
sleep. An `error` frame means it failed; a timeout means success. No guest or protocol change,
works against today's agent. Cost: the caller either waits before acting (latency on every
paste) or acts first and reports afterwards (the wrong paste already happened).

**(b) Guest acknowledges the write.** Correct and fast — the host waits for exactly one reply
and the latency is whatever the guest takes. Needs `protocol.md`, `AgentSession.cs`,
`packages/protocol` validators, fixtures, and the host client changed together.

**(b) must be bounded to stay backward compatible.** A new host waiting unconditionally for
an ack from an older agent would hang on every paste. Combining them — send an ack, wait with
a timeout, treat a timeout as today's behaviour — is correct with a new guest and unchanged
with an old one.

Deliberately not attempted here: it is a wire-contract change across two languages, and
neither `swift build` nor `dotnet test` can be run in this environment.

### 2. `window_not_tracked` escalates into offering to relaunch a closed app

The host's `canSendInput(to:)` (`HostDashboardModel.swift:1904-1906`) checks the host's own
`mirrorSessions`, not the guest's tracked-window map. When the user closes an app from inside
Windows, the guest untracks the HWND immediately; the host only learns via `window.closed` on
the separate event connection.

In that window, `restartFrameSubscription` (`HostDashboardModel.swift:4729-4738`) calls
unsubscribe then subscribe, the guest answers `window_not_tracked` to both, and the host
records a **successful** restart and increments `frameStreamRestartCount`. Two of those
escalate to `recover-window-capture` and then `reopen-windows-app` — so Veil offers to
relaunch the app for a window the guest already said does not exist.

Correct behaviour: treat `window_not_tracked` on subscribe or input as "this window is gone"
and drop the mirror session. Blocked on finding 1.

### 3. The guest returns `false` instead of an error for real input failures

`AgentSession` awaits the desktop call and discards the returned `bool`
(`AgentSession.cs:478-483`, `:519-523`, `:559-561`). `WindowsDesktop` returns `false` — not an
exception — for an unparseable HWND, an unknown event name, and a dead window
(`WindowsDesktop.cs:350-358`, `:373-376`, `:415-425`).

`protocol.md:760` says "Failures inside the guest are reported as `input_text_failed`". That
is true only for thrown exceptions. Either the `false` path should produce the error reply, or
the doc should say what actually happens. Guest change, so not attempted.

### 4. Seven guest error codes are undocumented

Absent from `protocol.md`: `handler_failed` (`AgentSession.cs:100`), `app_launch_failed`
(`:144`), `window_focus_failed` (`:407`), `window_close_failed` (`:445`),
`input_mouse_failed` (`:485`), `input_key_failed` (`:525`), `clipboard_text_failed` (`:594`).

`app_launch_failed` is the one a user meets today — `app.launch` uses `expectedReplies: 2`, so
it is read and surfaces as "The Windows agent returned app_launch_failed: …". The host cannot
explain or pre-empt a code the contract does not mention.

### 5. No length bound on a dropped file name

Neither side bounds it. The guest builds
`%TEMP%\VeilDroppedFiles\<32-char GUID>\<fileName>` (`AgentSession.cs:291-299`), which leaves
roughly 176 characters for the name against Windows' 259-character limit. macOS permits 255
UTF-8 bytes per component, so a legal 177+ character ASCII name overflows. `app.manifest`
declares no `longPathAware`.

On failure the guest returns `file_write_failed` carrying the raw .NET exception text, which
the host now surfaces verbatim — so the user is told something went wrong but nothing about
the name being too long. Low likelihood (CJK names stay well under, at ~85 characters), cheap
to fix on both sides.

### 6. The host is stricter than the guest in two places, and drops silently

- `InputTextEvent.isSendable` (`ProtocolMessages.swift:609-618`) rejects any scalar in the
  control general category; the guest and the doc reject only `\r`, `\n`, `\t`. The host
  returns `false` and the shell discards it, so the keystroke vanishes.
- `veil-vmctl app-runtime-action --action type-text` routes through `VeilHostClient.keyInputs`
  (`:1287-1308`), which throws for anything outside `[A-Za-z0-9]`. So `--text 안녕하세요` is
  refused **by the host** even though `input.text` exists specifically so Korean can be typed
  and the guest accepts it. That one contradicts the stated purpose of the feature.

## Verified Correct

Worth recording so the next pass does not redo it: `appId` is checked against the latest
`app.list.response` before both `app.launch` and `file.open`; dropped-file characters,
reserved names, and byte size are all mirrored from the guest's rules; mouse coordinates are
clamped and out-of-surface clicks are never sent; `input.key` only ever emits `keyDown`/`keyUp`
with a mapped virtual key; `input.text` length, emptiness, and newline rules match the guest's
bound exactly including the UTF-16-versus-Character distinction for emoji;
`shared.folder.request` fields are compile-time constants that satisfy the guest's regexes; the
frame subscribe `format` is hardcoded `"png"`; and `window.focus`/`window.close` use
`expectedReplies: 1`, so the host does read and act on `accepted: false`.

## Suggested Order

1. Error-reading path for fire-and-forget messages (blocks 2 and 3).
2. Clipboard acknowledgement, bounded for backward compatibility.
3. Treat `window_not_tracked` as "window is gone".
4. Reconcile the guest's `false` input path with `protocol.md:760`.
5. Document the seven missing error codes.
6. Bound the dropped file name length on both sides.
7. Relax the host's control-character and CLI `type-text` restrictions to match the guest.

## Not Verified

Nothing in this repository has been compiled or run this session. The shell returns exit 1
with empty output for every command; a probe file from an earlier session was never created,
confirming commands do not execute rather than failing.

Everything in "Verified Correct" and every file:line citation above is verified by reading
source. The claims about *runtime behaviour* — that `OpenClipboard` contention actually occurs
often, that a 177-character name actually throws — are reasoned from the code, not observed.

---

## Progress, 2026-08-13 (later)

Two more items closed, both host-only or documentation-only, so neither needed a compiler on
the guest side.

### Item 5 closed: dropped file name length

- [x] `WindowsAppFileDropPolicy.maximumFileNameUTF16Length = 160`, derived rather than picked:
      Windows allows 259 usable code units, the guest builds
      `%TEMP%\VeilDroppedFiles\<32-char GUID>\<fileName>`, and `C:\Users\<user>\AppData\Local\Temp\`
      is 29 plus the user name — 79 code units of prefix, plus up to 20 for a Windows user
      name, leaves 160.
- [x] Over-long names are **shortened, not refused**, keeping the extension. Same reasoning as
      the character rewrite: the name is legal on the user's own operating system, and the guest
      copy lives in a temporary per-drop GUID directory that is deleted minutes later, so a
      shortened name cannot collide with anything.
- [x] Shortening walks `Character` values, not the UTF-16 array, so a surrogate pair is never
      cut in half. Slicing UTF-16 to fit a budget would leave a half surrogate that Swift
      surfaces as U+FFFD and Windows receives as a different name.
- [x] Counted in UTF-16 code units because that is what Windows counts. A 200-emoji name is 400
      units, and a Hangul name is one unit per syllable.
- [x] One code unit is held in reserve so appending `_` to a reserved device base name cannot
      push the result back over the limit.
- [x] 7 tests.

The guest still has no length check of its own. That is now a documented expectation rather
than a silent assumption: a host that skips the shortening gets `file_write_failed`.

### Item 4 closed: the seven undocumented error codes

- [x] `docs/protocol.md` now has an `Error / Codes` section listing every code the guest can
      emit, with what raises each one.
- [x] It also records the two gaps a reader needs in order to trust the list: that most of these
      codes cannot currently be observed by the host at all, and that
      `input_mouse_failed`/`input_key_failed`/`input_text_failed` are only raised for thrown
      exceptions while the `false` return path produces no reply.

Documenting the second gap matters more than it looks. Without it, a future reader would take
`protocol.md:760` at face value and build error handling for a message the guest never sends.

## Remaining, In Order

1. Error-reading path for fire-and-forget messages. Still blocks 2 and 3.
2. Clipboard acknowledgement, bounded for backward compatibility.
3. Treat `window_not_tracked` as "window is gone".
4. Reconcile the guest's `false` input path with `protocol.md` — now that the doc states what
   actually happens, this is a choice between changing the guest and accepting the behaviour.
5. Relax the host's control-character rule and the CLI `type-text` restriction to match the
   guest. `veil-vmctl app-runtime-action --action type-text --text 안녕하세요` is refused by the
   host because that path routes through `VeilHostClient.keyInputs`, which only accepts
   `[A-Za-z0-9]` — reasonable for the coherence proof it was written for, wrong for a general
   type-text action, and directly contrary to why `input.text` exists. Deferred because moving
   the action onto `input.text` changes the `app-runtime-action` report shape, which several
   harness fixtures pin.
