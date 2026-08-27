# File Drop Refusals Were Silent

Date: 2026-08-12

The roadmap listed "Drag and drop" as unbuilt v1.5 work. It was built. This is the
second time in three days the roadmap understated what exists — the Retina entry was
the first — so the entry has been rewritten with what is actually there.

What was **not** built is the part that matters when it fails: drag-and-drop refused
files without telling anyone.

## The Bug

`WindowsAppMirrorView.handleDrop` returned `true` immediately, which is what makes
macOS play the accept animation and end the drag. Everything that could refuse the
file ran *after* that, inside an `NSItemProvider` completion, and every refusal was a
bare `return`:

| Condition | Old behaviour |
|---|---|
| File over 50 MB | silent `return` |
| Size unreadable | silent `return` |
| File empty | silent `return` |
| Read failed (sandbox/permission) | silent `return` |
| Provider yielded no URL | silent `return` |
| **Five files dropped** | **one sent, four silently discarded** |

So the most likely failure — dragging something large — looked identical to a
successful drop that did nothing. The user has no way to distinguish "Veil refused
this" from "Windows opened it and the app ignored it".

Worth noting where the size check came from: it is on the host deliberately, so an
oversized file costs a `stat` instead of a full read plus a base64 copy of itself. That
optimisation was right. It just never said anything.

## What Changed

- [x] `WindowsAppFileDropPolicy` in VeilHostCore. Pure static rules, no AppKit, no disk,
      no VM — so the limits are testable.
- [x] `WindowsAppFileDropRefusal`, an enum where each case carries the values its own
      message needs. There is no way to construct a refusal without the facts that
      explain it.
- [x] Multi-file drops. Every file is processed, each independently, so one bad file
      cannot take the rest down and each refusal is reported when it is known.
- [x] Batch refusal decided **synchronously** from the provider count, so an oversized
      batch returns `false` and macOS never plays the accept animation at all. That is
      the one moment a drop can be declined without needing to explain it afterwards.
- [x] `WindowsAppWindowPresenter.presentDropRefusal` shows the refusal as a sheet on the
      window the file was dropped onto.
- [x] `HostDashboardModel.lastFileDropRefusal` records the most recent refusal for
      diagnostics, and is cleared once a drop is accepted.
- [x] 14 tests in `FileDropPolicyTests.swift`, 3 in `HostDashboardModelTests.swift`.

## Decisions

**A sheet, not a macOS notification.** A notification can be silently suppressed by a
permission the user set months ago, which would put this straight back into the
silent-failure class it exists to leave. A refused drop is also the immediate result of
a gesture the user just made, which is exactly when a modal is appropriate rather than
annoying. It attaches to the window that was dropped on, so the message is where the
gesture was.

**Not through `HostDashboardModel.errorMessage`.** This was the obvious wiring and it is
wrong. `AgentView` renders that field as an "Agent Unavailable" panel with a
`network.slash` icon, in a different tab. A file being the wrong size would have been
reported as a lost connection to Windows. The model records the refusal; it does not
word it or route it.

**`recordFileDropRefusal` does not touch `phase`.** `openFile`'s catch sets
`phase = .failed` because a launch genuinely failed. A refused drop is not a runtime
failure: nothing broke, and the app the user dropped onto is still running. Both
omissions look like oversights, so tests pin them.

**An unreadable size is refused, not assumed.** Treating `nil` as zero would report an
empty file, and treating it as unlimited means discovering the size by exhausting memory
on an unbounded read.

**The batch limit is 8, the same number as the per-app window bound.** Each dropped file
opens its own Windows app window, so a mis-dragged folder would carpet the screen. Two
different answers to "how many windows of one app will Veil put on screen" would drift
apart, so it is one number. It is written out rather than referencing
`HostDashboardModel.maximumAdoptedWindowsPerApp`, because that constant lives on a
`@MainActor` type and this policy runs in non-isolated file-loading callbacks; a test
pins the two together instead.

**The 50 MB cap stays duplicated across host and guest.** Checking on the host avoids a
pointless transfer; checking in `AgentSession.cs` stops a host that skipped the check.
Duplication is the point, so a test pins the host value and names the guest constant.

**Locale-independent size formatting.** `ByteCountFormatter` uses a comma decimal
separator in much of the world, which would make the messages impossible to assert on.
`String(format: "%.1f MB")` is unlocalized.

## Not Fixed: The Transport

A 50 MB file becomes roughly 67 MB of base64 in a **single** message on the same channel
that carries input events and window frames. While that message is being written,
typing and frame delivery stall. This is the same problem that moved frames off base64
onto the binary channel (VFR1/VFR2), and it is worse here because the payloads are
larger.

The fix is available in principle: slice 7 added a shared folder, so the host could copy
the file into `VeilShared` and send only a guest path. That is what Parallels does. It is
not attempted because the shared-folder path has never been verified end to end, and
building a second unverified feature on top of an unverified one compounds the risk
rather than reducing it. The size cap exists largely *because* of this transport; a path
on the wire would make the cap a disk-space question instead of a channel question.

## Not Verified

`swift build` and `swift test` have not been run. The shell in this environment returns
exit 1 with empty output for every command. A probe file from an earlier session was
never created, which confirms commands are not executing rather than failing.

Specific risks a compiler would catch:

- `WindowsAppMirrorView` is a struct with a memberwise initializer, so the new
  `onDropRefused` property had to be declared and passed in the same position. Both were
  edited together.
- The presenter's `onDropRefused` takes one argument and the view's takes two
  (`windowId` first). They are different types in different scopes, mirroring the
  existing `onFileDrop` pattern, but the names are the same.
- `NSAlert.beginSheetModal` is called from a `@MainActor` method, and the refusal
  callbacks reach it through `DispatchQueue.main.async`, matching how the existing
  success path already hops to main.

Needs live confirmation: that a 60 MB file produces a sheet naming its size, that
dropping three files opens three windows, and that the sheet attaches to the correct
window when two apps are mirrored.

---

# Part Two: The Names macOS Allows And Windows Does Not

Found while checking the host's refusals against `docs/protocol.md`. The protocol already
documented guest-side rejections the host was not preventing and not surfacing.

## macOS Names That Windows Refuses

`docs/protocol.md` requires `fileName` to be a bare name with no separators, no
traversal, and not a reserved device name. `AgentSession.TryResolveSafeFileName` also
rejects anything in `Path.GetInvalidFileNameChars()`.

The host sent `url.lastPathComponent` unchecked. That is a problem because the two
platforms disagree, and not symmetrically — every one of `: * ? " < > | \` is legal in an
APFS file name and forbidden by Windows.

The likely case is not exotic. Finder *displays* `/` in a file name while storing it as
`:` on disk, so a file the user sees as `2026/08/12 report.txt` reaches the host as
`2026:08:12 report.txt`. Any date typed with slashes hits this. The guest refused it
correctly, and the user watched a perfectly legal file be rejected for a reason that is
invisible on their own machine.

- [x] `WindowsAppFileDropPolicy.windowsSafeFileName(for:)` rewrites forbidden characters
      and control characters to `_`, and suffixes a reserved base name so `CON.txt`
      becomes `CON_.txt`.
- [x] Refuses only names carrying no content at all (`""`, whitespace, `.`, `..`), as
      `.unusableFileName`.
- [x] 13 tests pinning the rewrite to the guest's rules.

**Rewrite, not refuse.** Refusing would have been the more conservative-looking choice and
it is the wrong one: the user's file is fine, the name is fine on their own operating
system, and the copy lands in a temporary guest directory that is deleted minutes later.
The rewritten name is not something they have to live with.

**This does not weaken the security boundary.** The guest validates independently and
still rejects anything unsafe. The host rewriting a name only decides whether a
legal-on-macOS file gets a chance to open. Host sanitizes for usability; guest validates
for safety.

**Suffix the base, not the whole name.** `CON.txt` → `CON_.txt`, not `CON.txt_`, so
Windows still resolves the extension and opens it with the right app.

**Only the exact base name is reserved.** `console.txt`, `COM10.txt`, and `nullify.dat`
are left alone. Rewriting those would be a bug the user would notice.

**Leading dots stay.** Splitting `.gitignore` into an empty base plus a `gitignore`
extension would run the reserved-name check against nothing.

**Split on the last dot only**, matching `Path.GetFileNameWithoutExtension`. So `CON.tar.gz`
has base `CON.tar`, which is not reserved, and both ends leave it alone.

**Control characters are checked by scalar value with an explicit single-scalar guard**, so
a flag or skin-tone emoji sequence is never mistaken for one.

## Windows-Side Failures Claimed The Runtime Broke

The guest returns structured reasons a drop failed: `app_not_found`, `invalid_file_name`,
`file_decode_failed`, `file_too_large`, `file_write_failed`, `file_open_failed`.

`HostDashboardModel.openFile` turned every one of them into:

```swift
errorMessage = userMessage(for: error)
phase = .failed
```

Two problems in two lines. `phase = .failed` claims the entire Windows runtime broke
because one file did not open — the app the user dropped onto is still running. And the
explanation went into `errorMessage`.

- [x] `openFile` now records `.guestRejected(fileName:detail:)`, keeping the guest's own
      wording, which is the only thing that says why.
- [x] Restores the phase it captured on entry, so a failed drop leaves neither `.failed`
      nor a launcher stuck in `.launching`.
- [x] `onFileDrop` carries the window id, so a failure only Windows could report lands on
      the same sheet, on the same window, as the checks the host made itself.
- [x] `presentDropRefusal` split from `showDropRefusal`, because refusals now arrive from
      two directions and the guest-side ones are already recorded by the time they get here.

**Worded as a Windows problem.** "Windows could not open X. <guest detail>" rather than
"Veil could not read X". Veil did its part; misplacing the blame would send the user
looking at the wrong thing.

## Finding: `HostDashboardModel.errorMessage` Has No Display Surface

Not fixed, because fixing it is a UX decision rather than a bug fix.

`AgentView` is the only consumer of that field, and `AgentView` is **never instantiated**
anywhere in the shell. The three views that hold a `HostDashboardModel` — `ContentView`,
`DetailView`, `WindowsAppBridgePanel` — none of them reference `errorMessage`.
`VMRuntimeView`'s `errorMessage` usages are `VMRuntimeModel`'s, a different model.

This is plausibly deliberate. The project built `agentDiagnostic`, `launchOnboarding`,
and `primaryNextAction` specifically to give product-facing guidance instead of raw error
strings, and `load()` failures do set `agentDiagnostic`, which is surfaced. Under that
reading `errorMessage` is an internal diagnostic and the one-screen launcher shows curated
state on purpose.

But it is written by several failure paths that look like they expect to be seen, and
`AgentView` is a whole view kept alive for a field nobody reads. Either the field should
get a surface, or the dead view and the writes should go. Worth a decision, not a
unilateral rewrite.

## Still Not Verified

No compiler has seen any of this. Highest-risk items in part two:

- `onFileDrop` went from three parameters to four. The presenter property, the view
  property, the view's call site, the presenter's forwarding closure, and the app's
  assignment were all updated together; a missed one is a type error.
- `showDropRefusal` had to become non-private for the app to call it.
- The app's `onFileDrop` closure captures the presenter strongly, matching the adjacent
  `onRestartFrameStream` closure that already does exactly that. A weak capture-list
  shorthand on a property is not obviously valid Swift, so the proven pattern was copied
  rather than guessed at.
- `splitExtension` returns a tuple labelled `fileExtension`, because `extension` is a
  keyword and would need backticks at every use site.

Needs live confirmation: that a file named with a colon opens in Notepad under a rewritten
name, and that uninstalling an app then dropping a file on its window produces a sheet
quoting Windows rather than a launcher in a failed state.
