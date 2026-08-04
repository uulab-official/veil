# App-First Windows Home Verification — 2026-08-04

Scope: Task 4 regression, installed-app lifecycle, and available visual QA for
the app-first Windows home. Checks are complete only where this pass produced
direct evidence.

## Presentation states

- [x] The automated installed-workspace policy verifies that installed Windows
  presents one app-first home and does not auto-open or duplicate the Windows
  desktop (`swift test`: 406 tests; lifecycle Node harness: 15 tests).
- [ ] Direct installed-app evidence of the default `Windows Apps` catalog state
  is unavailable. The current user data has an ISO but no VM profile or
  installed-Windows state, so `/Applications/Veil.app` correctly showed the
  first-run `Windows 11 Setup Required` route instead. Next action: launch with
  a real installed Windows profile and connected guest agent.
- [x] The available regular-size screenshot proves the branded first-run setup
  canvas only: it shows one prominent `Download Windows 11` action plus the
  quiet secondary `Use Existing ISO` action.
- [ ] Direct installed-`Windows Apps`-home evidence that its app catalog has no
  centered Windows hero or nested surface is unavailable. The captured
  first-run setup canvas visibly contains a centered Windows logo, `Get Windows
  11`, and a CTA, so it cannot prove this installed-home constraint. Next
  action: launch with a real installed Windows profile and connected guest
  agent, then capture the Windows Apps home.
- [ ] Direct `Windows Desktop` availability, real VM surface, and `Show Apps`
  return-path checks are unavailable: no VM profile, installed Windows record,
  or live display was present. Next action: boot the prepared VM, connect the
  guest agent, then exercise both workspace routes.
- [ ] Loading, reconnecting, empty-catalog, and safe-failure visual states were
  not reproduced against a live guest agent. Next action: induce each state in
  a connected test VM and capture the single contextual message.

## Interaction and accessibility

- [x] The installed first-run UI exposed one Veil main window, a semantic `Get
  Windows 11` heading, `Download Windows 11`, `Use Existing ISO`, Refresh,
  Diagnostics, and Settings through macOS accessibility.
- [ ] Tile hover/pressed/focus, Return/Space activation, queued progress,
  window counts, icon/fallback rendering, and long-name truncation require a
  live app catalog. Next action: repeat against a connected guest agent with
  long display names and one queued app.
- [ ] The 820 x 560 visual pass could not be completed: macOS locked while the
  resize action was being issued. Next action: unlock the Mac and repeat the
  compact-window inspection with the installed Windows app catalog.

## Automated verification

- [x] `swift test --package-path apps/mac-host` — 406 tests in 27 suites
  passed.
- [x] `node --test harness/macos-app-lifecycle/test/*.test.mjs` — 15 tests
  passed; 0 failed, cancelled, skipped, or todo.
- [x] `./script/build_and_run.sh --verify` — built, ad-hoc signed, strictly
  verified, and launch-contract verified the bundle (exit 0).
- [x] `./script/test_macos_lifecycle.sh --skip-build` — verified guarded
  replacement, quarantine cleanup, uninstall, temporary lifecycle-sentinel
  preservation, reinstall, and first-window launch (exit 0).

## Installed-app and distribution safety

- [x] `./script/install_macos.sh --replace` installed the newly built signed
  bundle at `/Applications/Veil.app`.
- [x] `codesign --verify --deep --strict /Applications/Veil.app` passed both
  after replacement and after reinstall.
- [x] `open -n /Applications/Veil.app` returned exit 0 after replacement and
  again after reinstall; the regular-size installed first-run window was
  captured before the desktop locked.
- [x] `./script/uninstall_macos.sh` moved only `/Applications/Veil.app` to
  `/Users/uulab/.Trash/Veil 4.app`; the installed path was then absent.
- [x] Reinstall restored `/Applications/Veil.app`; direct live preservation
  evidence is limited to the Windows ISO below. The lifecycle script separately
  verifies its temporary Application Support sentinel, not a full live
  Application Support manifest comparison.
- [x] ISO metadata was identical before and after lifecycle testing:
  `7951140864 1785761837` (size bytes, modification epoch).

## Visual evidence

- Regular-size installed first-run screenshot:
  `/var/folders/hc/ck1bcnks1kx3z5rslhm3qtg80000gn/T/com.openai.sky.CUAService/Veil Screenshot 2026-08-04 at 12.12.53 PM.jpeg`.
