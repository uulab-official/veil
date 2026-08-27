# Parallels Gap: Guest Audio and Unicode/IME Text Input

Date: 2026-07-30

Two gaps from the Parallels-class assessment that are sized to close now, taken
in leverage order after the frame-pipeline rewrite was deferred as a separate
architectural decision.

## Why These Two

Grep evidence from the assessment pass:

- **Audio is entirely absent.** The QEMU boot plan has no `-audiodev` and no
  sound device of any kind (`QEMUWindowsBootPlanner` builds `qemu-xhci`, `nvme`,
  `virtio-rng-pci`, `ramfb`, `virtio-gpu-pci`, `usb-kbd`, `usb-tablet`, and
  nothing for audio). Windows in Veil is silent. Every Parallels-class comparison
  fails immediately on a Teams call or a YouTube tab.
- **Non-ASCII text input is impossible.** `VeilHostClient.keyInputs(windowId:text:)`
  maps each Unicode scalar to a Windows *virtual key*, and the guest posts
  `WM_KEYDOWN`/`WM_KEYUP`. There is no `WM_CHAR` path and zero `WM_IME_*`
  handling anywhere in the tree. Hangul, kana, and Han characters have no virtual
  key, so a Korean user cannot type their own language into a mirrored Windows
  app. This is a daily-use blocker, not a polish item.

Design decision for input: composition stays on macOS. The host owns the IME,
commits finished text, and sends it as Unicode. Veil does not try to drive the
Windows IME remotely, which would need per-keystroke round trips and guest-side
candidate windows over a mirrored bitmap.

## Track A: Guest Audio

- [x] Add a `QEMUWindowsAudioDevice` selection type mirroring the existing
      `QEMUWindowsNetworkAdapter` pattern, including the `VEIL_QEMU_AUDIO_DEVICE`
      environment override and a warning for unsupported values.
- [x] Include an explicit `none` option. QEMU built without CoreAudio would fail
      to start if audio were unconditional, so users must be able to turn it off
      without rebuilding. The Swift case is named `disabled` with raw value `none`
      so it can never collide with `Optional.none` at a call site.
- [x] Emit `-audiodev` plus the selected sound device from
      `QEMUWindowsBootPlanner`, defaulting to Intel HD Audio (`intel-hda` +
      `hda-duplex`) because Windows on ARM ships a native HD Audio class driver
      and the duplex codec gives playback and capture in one device.
- [x] Offer `usb-audio` as the alternate, routed through the `qemu-xhci`
      controller the plan already creates, for hosts where `intel-hda` misbehaves.
- [x] Report the selected audio device in the typed runtime configuration summary
      as its own `audio` section, resolved from the same environment override the
      boot plan reads so the summary cannot claim sound is wired while the plan
      omits it.
- [x] Extend `harness/qemu-boot-plan` to require an audio backend and device pair
      in the plan, including backend-before-device ordering and the USB controller
      prerequisite for `usb-audio`, and refresh its fixture.
- [x] Swift tests: default device, env override, unsupported value warning,
      `none` disabling audio entirely, and argument ordering.

## Track B: Unicode and IME Text Input

- [x] Add an `input.text` protocol message carrying committed Unicode text for a
      tracked HWND, documented in `docs/protocol.md` with the composition-on-host
      rule.
- [x] Register it in `packages/protocol` with a validator and a fixture, and add
      the parse/validate tests.
- [x] Add `InputTextEvent` and `MessageType.inputText` on the Swift side, plus
      `VeilHostClient.sendTextInput` and a `HostDashboardModel.sendTextInput`
      gated by the same live-agent/input capability checks as `sendKeyInput`.
- [x] Add `WindowTextInput` and `IWindowsDesktop.SendTextInputAsync` on the guest,
      implemented with `WM_CHAR` per UTF-16 code unit so surrogate pairs and
      precomposed syllables both arrive intact. Declared as a default interface
      method that throws, so the six existing desktop test doubles keep compiling
      without a silent no-op reaching production.
- [x] Route `input.text` in `AgentSession`, rejecting untracked HWNDs with
      `window_not_tracked` exactly like `input.key` does.
- [x] Bound the payload so a single message cannot post an unbounded number of
      window messages. Bounded at 4096 UTF-16 code units on both sides, rejected
      with `text_too_long` on the guest.
- [x] Implement `NSTextInputClient` on the mirrored window's content view so
      macOS IME composition is captured, marked text is shown while composing,
      and only committed text is sent to the guest. Composition is drawn as a
      bottom-left overlay because a mirrored bitmap has no text cursor to anchor an
      inline composition to; without it a Korean user would see nothing until the
      syllable committed.
- [x] Keep the existing `input.key` path for navigation, shortcuts, and ASCII so
      the proven Coherence proof contract does not change. The routing decision
      lives in `MacTextInputRouter` in `VeilHostCore`, free of AppKit so it is unit
      testable without a window or input context.
- [ ] Add a `type-unicode` app-runtime action plus validator coverage, leaving the
      existing `type-text` virtual-key contract untouched. **Deferred**: the
      user-facing IME path is complete without it, and the app-runtime action report
      plus its validator have a large required-field surface that is not worth
      editing blind while the build cannot be run. Tracked below.
- [x] Swift tests for the routing decisions and the model send path.
- [ ] .NET tests for `SendTextInputAsync`. **Deferred** with the CLI action for the
      same reason; the contract harness does assert the guest wiring exists.

## Wider Bug Found While Implementing

The gap was larger than "IME missing". `MacKeyboardInputMapper.windowsVirtualKey`
only resolves letters, digits, and nine named keys. Everything else returned `nil`,
`sendKey` returned `false`, and the keystroke was dropped:

- Space returned `" "`, which has no virtual key, so **space did not reach the
  guest**.
- Every punctuation mark (`-`, `,`, `.`, `!`, `@`, ...) was dropped the same way.
- Uppercase relied on posting a synthetic `VK_SHIFT` before the letter, which
  `PostMessage` cannot make the target control observe reliably, since it does not
  update real keyboard state.

`MacTextInputRouter` now falls back to committed text for any printable key the
virtual-key mapper drops, so space, punctuation, and correct casing work through
`WM_CHAR`. This was not in the original plan; it surfaced while writing the router
tests.

## Verification Status

Written alongside the implementation:

- `apps/mac-host/Tests/VeilHostCoreTests/MacTextInputRouterTests.swift`: committed
  text for Hangul/kana/Han/punctuation/space, Enter and Tab staying on the
  virtual-key path, the UTF-16 bound including surrogate pairs, shortcut chords
  never becoming text, and every key going to the input method while composing.
- `apps/mac-host/Tests/VeilHostCoreTests/QEMUWindowsBootPlanTests.swift`: audio
  default, env override, unsupported-value warning, disabled audio, and
  backend-before-device ordering.
- `apps/mac-host/Tests/VeilHostCoreTests/HostDashboardModelTests.swift`: committed
  Korean text reaching the service, untracked HWNDs ignored, and host-side refusal
  of payloads the guest contract would reject.
- `packages/protocol`: fixture parse plus `validateInputText` acceptance and
  rejection cases.
- `harness/qemu-boot-plan`: audio device/backend agreement, ordering, and the
  `usb-audio` USB-controller prerequisite.
- `harness/windows-agent-contract`: asserts the guest actually wires `WM_CHAR`,
  `HandleTextInputAsync`, `text_too_long`, and `input_text_failed`.
- `harness/export-diagnostics`: `deviceSummary.audioDevice` and the typed `audio`
  configuration section are now required, so an exported bundle can never hide the
  fact that a guest has no sound device.

**These were not executed.** Shell command execution was unavailable in the session
that produced this change, so `swift build`, `swift test`, `dotnet test`, and
`node --test` have not been run. Treat the suite as written-but-unverified until:

```bash
cd apps/mac-host && swift build && swift test
cd apps/windows-agent && dotnet test
cd packages/protocol && npm test
cd harness/qemu-boot-plan && npm test
cd harness/windows-agent-contract && npm test
```

## Remaining Live Verification

- [ ] Boot Windows 11 Arm and confirm the HD Audio device appears and plays. If the
      emulated controller misbehaves, retry with `VEIL_QEMU_AUDIO_DEVICE=usb-audio`
      before changing the default.
- [ ] Confirm QEMU on the test host was built with CoreAudio. If it was not, QEMU
      will refuse to start with an audio backend attached, and
      `VEIL_QEMU_AUDIO_DEVICE=none` is the escape hatch.
- [ ] Type Korean into a mirrored Notepad with the macOS 2-set input source and
      confirm the composition overlay appears, the committed syllables arrive, and
      backspace deletes a jamo rather than a whole character.
- [ ] Confirm space, punctuation, and uppercase now reach the guest correctly; these
      were broken before this change and have no live proof yet.
- [ ] Check that Enter and Tab still submit and move focus in a mirrored dialog,
      since they were deliberately kept off the committed-text path.
- [ ] Add the deferred `type-unicode` app-runtime action so automation can drive the
      Unicode path without a keyboard, and the deferred .NET test for
      `SendTextInputAsync`.
