# Parallels Parity Gaps

Date: 2026-11-11

This inventory compares Veil with Parallels Desktop's user-facing features. It comes from the code and
the docs, corrected by what was measured on the live Windows 11 Arm guest during 2026-11-09…11.
"Live" means checked on that guest; "unit" means covered by tests only.

| # | Feature | Status | Notes |
|---|---|---|---|
| 1 | Coherence: one Mac window per app, desktop hidden | Partial (live) | Windows come from the guest framebuffer (`window.layout`, `window.crop.set`, `window.move.request`). Every app window on the Windows desktop now gets a Mac window, whoever opened it (`capabilities.desktopWindows`, `window.list.request`). Live, 2026-11-12: Notepad and Paint left open in Windows and Character Map appeared as three Mac windows after a Veil relaunch, with no helper windows, and Character Map at its own 477 x 430. Not done: a window another one covers is still shown from captured frames every few seconds, and the Windows taskbar was visible in the guest during this check. The Dock menu and the menu bar menu have a Windows Start Menu; Character Map and File Explorer, now a built-in app, Calculator, and Settings were opened live and each got its Mac window at its own size; Calculator and Settings are UWP apps. After such a launch Veil's main window stays open behind the app windows, which is not yet explained. |
| 2 | Apps in Dock, Launchpad, Applications; "Open with" | Implemented (live, partly) | Opening a Windows app writes a signed launcher to `~/Applications/Veil Apps` (`09dfe151`). Live: Notepad's launcher was created, passes `codesign --verify --strict`, and is listed by Launch Services for `.txt` files. Opening a file through it was not tried, because that brings Veil forward. |
| 3 | Clipboard and drag and drop | Implemented | Text and images go both ways. Files go Mac to Windows by drop or paste, and Windows to the Mac by copying in Explorer (CF_HDROP through the shared folder to Downloads). Drops travel as base64. |
| 4 | Shared folders | Implemented (live) | Windows to Mac: `C:\VeilShared` over SMB. Mac to Windows, as UTM does for Windows guests: a folder chosen with Share a Mac Folder with Windows is served over WebDAV on 127.0.0.1 under a random token and mapped as `Mac (M:)` (`host.folder.mount.request`). Live: Explorer listed the test folder's file and subfolder; turning sharing off removed the drive and closed the port. Writing from Windows is unit-tested only. |
| 5 | Retina | Implemented (live, agent side) | With Retina resolution, the default once the agent reports `displayScale`, the apps view runs the guest display at twice the screen in points and Windows at 200% (`display.scale.request`). About 5% frame-rate cost. See `2026-11-11-retina-guest-scale.md`. |
| 6 | Keyboard and IME | Implemented (live, partly) | Keys reach Windows by position and the Windows IME composes, as in UTM and Parallels; 입니다 + Enter came out right through both QEMU and the agent. Switching the macOS input source also presses the Windows Hangul key; right Command switches Windows alone. Composing on the Mac and rewriting the guest's text swapped syllables and was dropped. Typing on the Mac keyboard is not yet confirmed by the user. |
| 7 | Trackpad | Implemented (unit) | Smooth scrolling works. Pinch is sent as Ctrl+wheel zoom and the three-finger page swipe as Browser Back/Forward. A two-finger horizontal swipe stays a horizontal scroll, and rotation has no Windows mapping. Not yet checked on the live guest: that needs real trackpad input. |
| 8 | Printers, camera, USB, audio | Partial | USB works. The printer bridge is research only. Camera is missing. |
| 9 | Suspend, idle pause, snapshots, shutdown | Implemented | Live: Stop now finishes when Windows shuts down without powering off (`1c3713b3`). Snapshots need qcow2. |
| 10 | Notifications | Implemented (unit) | Delivery on the live guest is unchecked. |
| 11 | Network | Partial | NAT and port forwarding work. Bridged networking needs Apple's vmnet entitlement. |
| 12 | Time, battery, dark mode sync | Implemented (live, partly) | Time: `time.sync.request` on agent connect, Mac wake, and session resume; correcting the clock needs the elevated-install `VeilTimeSync` task. Dark mode: `appearance.set.request`, on by default. Battery: not feasible, because QEMU `virt` has no ACPI battery (`docs/research/guest-host-state-sync.md`). Live, with agent `0.1.0+92b4061b37aa`: the agent reports `timeSync` and `appearanceSync`; with the Mac in dark mode Windows was already dark (`changed: false`), and the guest clock was 159 ms from the Mac's. Correcting a skewed clock and switching while Veil runs are unchecked. |
| 13 | DirectX acceleration | Missing (experiment measured) | Software rendering (WARP): Paint at 23.5 fps, DWM presents 40.6 ms apart. With Triton on the same VM: 72 fps and 13.6 ms (the 75 Hz cap). Not shippable yet: with the driver installed Windows does not shut down, and the default runtime shows no display. The VM was restored to `snapshots/pre-triton-20261111-1506`; the Triton disk is kept as `snapshots/post-triton-20261111-1617`. |
| 14 | Dynamic memory | Blocked (live) | The host side is done, but virtio-win 0.1.302's ARM64 Balloon driver gives wrong buffer addresses. Reported as virtio-win/kvm-guest-drivers-windows#1719. |

## Order of work

1. Hide the Windows taskbar while app windows are shown (gap 1). This slice.
2. Set Windows to 200% on Retina so text is sharp (gap 5).
3. Per-app launchers and "Open with" (gap 2).
4. Files from Windows to the Mac (gap 3).
5. GPU acceleration (gap 13). Triton session.
6. Sync dark mode, time after resume, and battery state (gap 12).

## Found on the live guest on 2026-11-12

- **Typed commands are not safe with apps open.** The tools update and the agent repair type into the Windows
  Run dialog through QEMU: a click at a fixed place, Ctrl+A, then the command. With Notepad and Paint open,
  one run replaced the text of an open Notepad document and changed Paint's tool. The text was restored with
  undo. Two changes followed.
  - The agent now starts the update itself from the tools disc (`tools.update.request`), with nothing typed.
    Live: with Notepad and Paint open, the agent went from `81e9f0ca5511` to `2e7d41908223` in 11 seconds.
  - Typing is refused while Windows has app windows open, and when the tools were installed but do not
    answer (`GuestTypingSafety`). The second rule came from a second accident: after the agent had crashed,
    the host no longer saw the open apps and typed again. That rule is unit-tested only.
- **The agent crashed while capturing.** Two captures of one window shared a bitmap after the streamer's
  two-second timeout, and one disposed it under the other: an access violation in `CopyPixels`. Captures of
  a window now run one at a time. Live: the agent stayed up for a minute with four windows shown; a longer
  run has not been watched.
- **Maintenance closed windows by itself.** A window covered by another one looked stale and was closed and
  reopened every few seconds. Maintenance that runs by itself no longer closes a window.
- **`input.text` lost characters.** A command typed through the agent into Command Prompt arrived without
  seven of its characters while the host was also raising another window. Not investigated.
- **The guest clock is 65 minutes off.** `time.sync.request` fails with `install-time-sync-task-elevated`.
- **A new window was pushed behind an old one.** Two causes, both fixed. The agent raised a window on every
  mouse event, pointer moves included. And the host's automatic frame maintenance focused a window whose
  stream looked stale, so Paint's covered formatting bar kept coming to the front. Live: Calculator opened
  from the Mac stays in front in Windows and its Mac window appears within 3 seconds.
- **The agent restarts when it dies.** `Start-VeilAgent.ps1` leaves a hidden PowerShell waiting on the agent
  process. A crash code starts the agent again, at most five times in ten minutes; a clean exit,
  `Stop-Process` (exit code -1, which updates and repairs use), and sign-out are left alone. Live:
  `taskkill /f` took the agent down and it answered again 2 seconds later, with a new supervisor; after
  `Stop-Process` it stayed down and the log says `ended with code -1 ...; left stopped`. The hidden
  PowerShell stays in memory for as long as the agent runs. The five-restart limit is not checked live.

## Found without touching the running guest on 2026-11-13

Nothing here was checked in the running app: Veil was not relaunched and the agent was not updated. The
checks are unit tests, a read-only screen dump of the guest, and screens drawn to image files in a test.

- **A line of the window behind showed along a Mac window's edges.** A user screenshot of Notepad had
  Paint's palette colours in its top row. All four edge rows matched the guest's translucent one-pixel DWM
  border plus the Mac window's own edge highlight, so the frame on screen was one the agent copied from the
  guest screen, border included. Cropped framebuffer windows already replaced that ring
  (`CoherenceBorderlessCrop`); captured frames did not. `FrameLayerView` now does the same.
- **Why the window in use was on captured frames is not known.** It was in front and the layout should have
  marked it `fullyVisible`. One cause that fits, and is fixed in the agent: any shown window of another
  process above a window counted as covering it, including one-pixel helper windows and layered windows
  with zero opacity. Whether that was the cause that day cannot be told from what was recorded.
- **A dropped app connection switched to the desktop view.** `DetailView` fell back to the desktop whenever
  the agent connection was lost, which hid every app window and brought the main window forward with all of
  Windows in it. It returned to apps only on a first app frame, and windows that kept their frames never
  sent one, so the desktop stayed. The agent restarts and updates by itself now, so this is ordinary use.
  Open app windows now stay on screen through a dropped connection, and the automatic desktop gives way to
  apps when the connection is back.
- **Installation Assistant.** Drawn to image files at 1100×760 and 760×560.
  - The steps and the page sat at the top of a mostly empty window. They now sit together a little above
    the middle.
  - The Prepare page listed the runtime's five steps in English with wording such as "Run Prepare VM to
    create the Windows unattended setup answer file", and marked what continuing creates with a warning.
    It now names each step for what it is for, is translated, shows not-yet-created steps as waiting, and
    keeps the warning for an installer Veil cannot read.
  - The Install page had a title and two buttons. It now shows the installer, the hardware, and the
    Windows account that setup will use.
  - Not drawn or reviewed: the download page (drawing it starts a download), the live Windows Setup panel,
    and the Korean strings on screen, since a test process does not load the app's string tables.
- **Lag.** With Veil closed, this guest's QEMU used about a third of one core idle on an 18-core Mac, and
  another project's VM and builds were running beside it. Veil's own share while mirroring was not
  measured, since that needs the app running. Builds and tests for this work ran at background priority
  (`taskpolicy -b`) and only the tests for the changed code.

## Found in the running app on 2026-11-13

Two relaunches, in the background, each with the user's go-ahead. Checks were window captures and a guest screen
dump; nothing was sent to the guest.

- **Mac windows showed the wrong part of the guest display.** Notepad's Mac window showed the wallpaper and
  Paint, with Notepad itself 254 by 63 pixels down and right: the crop was taken where the window had been
  before Veil moved it to match its Mac window. The host never learned the new place. Since 2026-11-12 the
  host sent `window.list.request` on its event connection, and the agent stops sending events to a
  connection that has sent a request. Every event after the answer was lost: `window.layout`, windows
  opening and closing, the clipboard, notifications. The request now goes out on a connection of its own
  and its answers are passed into the event stream. After a second relaunch with the fix, Notepad's Mac
  window matched the guest display at the window's frame (26,112 sampled pixels, mean difference 0.16 of
  255, none far off; the broken capture had 9% far off). That relaunch did not move any window, so it does
  not show a layout event arriving after the list: no layout changed in the 90 seconds watched. That part
  rests on the unit tests and on reading the agent's connection handling.
- The main window stayed hidden after the relaunch and Veil did not come to the front.
- Paint and File Explorer, covered in Windows and so shown from captured frames, had clean edges. The edge
  fix for screen-copied frames could not be seen at work: no window was in that state.
- **Load with three windows mirrored and nothing changing:** Veil about 10% of one core, this guest's QEMU
  about a third of one. Not measured while typing or dragging.
- **Agent updated with the app windows open.** The agent-driven tools update took the agent from
  `daf5a8c492ec` to `512faea4e697`; it was down for about 5 seconds. Nothing was typed into Windows and the
  disc was ejected afterwards. The three Mac windows kept their window numbers through the dropped
  connection and the main window stayed hidden, so the view did not switch to the desktop. Afterwards
  Notepad's Mac window still matched the guest display at its frame.

## Settings and translation pass on 2026-11-13

Done without relaunching Veil: unit tests, screens drawn to image files, and a script that reads the sources.

- **Settings said things that are no longer true.** The Integration tab listed the clipboard as planned and
  app windows as something that would follow VM boot. The Hardware tab described a planned Retina display
  and an Apple Virtio scanout, and the panels spoke of a "boot spike". They now state what Windows has and
  what works: app windows, clipboard, shared folders, cores, memory, disk.
- **Text passed through `Text(String)` was never translated.** Integration rows, setup rows, preflight
  checks, and the download's time-left line showed English in a Korean interface. They go through the
  string table now.
- **`script/audit_localization.py`** lists UI string literals with no Korean translation. It reported 121
  before this pass. After adding 56 translations and removing views nothing shows, it reports 44: numbers
  and names that need no translation, diagnostics meant for developers, review-evidence labels, and a
  developer view of the agent (`AgentView`) that is still to be looked at.
- **1,555 lines of views nothing creates were removed**, found by looking for view types never named
  outside their own declaration.
- **Not seen in the running app.** The Korean wording was checked by reading it, not on screen: a test
  process does not load the app's string tables, so the drawn images show the English keys.

## Third relaunch on 2026-11-13

In the background, with the user's go-ahead; checks were window captures and a guest screen dump.

- **A window moved after connecting is cropped from its new place.** This start opened the Mac windows at
  other places than the last one and moved the Windows windows to follow, which is what used to leave the
  crop behind. Notepad's Mac window matched the guest display at its new frame (26,112 sampled pixels, none
  far off) and did not match at the old one (4% far off). The window list on its own connection is now
  seen working in the running app.
- **Windows land somewhere new each start.** Every Mac window opened in the middle of the screen, stepped
  aside by how many were already open, so the order the guest listed them in decided where each went:
  Notepad moved 56 points up and left, Paint and File Explorer 28 down and right, and all three Windows
  windows were moved to follow. A Mac window now opens where its Windows window already is, when the guest
  display stands for the Mac screen (`WindowsAppWindowPlacement.frameMatchingGuest`). After a fourth
  relaunch all three Mac windows opened at the places they had before it, and no Windows window moved.

## Production pass on 2026-11-13

Done without relaunching Veil, updating the agent, or touching the guest. Two read-only audits looked for
what would block a release: one at the host/guest trust boundary, one at the virtual machine's lifecycle
and the safety of its data. Each fix below was confirmed by reading the code path first and is covered by
unit tests. None of it has run in the app or on the live guest yet.

Fixed:

- **User Account Control prompts and the lock screen were invisible.** With apps shown as Mac windows,
  nothing showed Windows' secure desktop, and input sent through the agent does not reach it: an installer
  asking for administrator rights looked frozen, and the prompt's pixels were cropped into whichever app
  windows sat under it. The agent now reports the secure desktop in `window.layout` (`secureDesktop`),
  captures nothing during it, and keeps the heartbeat going. The host crops nothing, and shows the guest
  display in a window of its own, driven through QEMU's display connection, until the prompt is answered.
  When Veil is not the app in use it asks for attention in the Dock instead of opening over other work.
- **A web page could drive Windows.** The agent's port is forwarded to `127.0.0.1` with no check on who
  connects, so a page open in any browser on the Mac could open a WebSocket to it, type, start programs,
  and read the clipboard. The agent now refuses a handshake that carries `Origin`, which a browser always
  sends. `URLSessionWebSocketTask` and Node's `WebSocket` were checked not to send it.
- **A reused process id passed for the virtual machine.** The launch record outlives QEMU. Any process
  that later got its id made Windows show as running, blocked Start, and received SIGTERM from Stop. The
  process must now be a QEMU system emulator.
- **A failed suspend froze Windows.** The guest is paused before its memory is saved; a save that failed or
  timed out, as on a full Mac disk, left it paused with nothing to resume it. The save is now cancelled
  and the guest continued.
- **A saved session that cannot resume blocked Start for good.** After an update of Veil or a settings
  change the session no longer matches the machine. Start always tried to resume, failed, and nothing
  discarded the session. The main window now asks whether to start Windows without it.
- **App icons from the guest were decoded unchecked.** They must now be PNGs of at most 1024 pixels a side
  and 1 MiB.
- **The WebDAV server recursed on blank lines**, before checking the token.

Open, from the same audits:

- The agent's socket still has no secret, and QEMU's loopback display has no password: another program on
  the Mac, or another user account, can connect to both.
- The guest reaches every service on the Mac's loopback interface through QEMU's user networking.
- Windows that run with administrator rights, such as an installer after its prompt is approved, take no
  input from the agent, which runs without them. They are shown but cannot be clicked. Not yet looked at.
- The WebDAV server checks a path and then opens it by path again, which a symbolic link swapped in between
  can redirect. The event queue from the guest is bounded by message count, not bytes.
- Reported by the lifecycle audit and not yet confirmed by reading: resume deletes the saved state before
  the load is known to have worked; Stop sends SIGTERM when a graceful shutdown times out, without asking;
  quitting without "suspend on quit" leaves QEMU running without asking; a full Mac disk is not handled
  (`werror`/`rerror`); the system disk is opened with `file.locking=off`, so only a process listing keeps
  two QEMUs off one disk; QEMU exiting right after launch is reported nowhere in the app.
- This guest's clock is still 65 minutes off: its tools were installed without administrator rights, so
  the `VeilTimeSync` task is missing. A fresh installation registers it.
