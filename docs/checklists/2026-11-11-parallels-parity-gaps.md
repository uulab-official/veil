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

## Fifth relaunch and agent update on 2026-11-13

In the background, with the user's go-ahead; checks were window lists, a window capture, a guest screen
dump, and requests to the agent that change nothing.

- Veil did not come to the front, the main window stayed hidden, and the three Mac windows opened where
  they were before.
- The agent-driven tools update took the agent from `512faea4e697` to `b5342bd09e85` in about six seconds
  with the three app windows open. They kept their window numbers through it.
- **A handshake carrying `Origin` is refused on the live agent** with `403 Forbidden`; the host's own
  connections, which carry none, work as before.
- **The agent does not mistake the user's desktop for the secure one.** `window.layout` reports
  `secureDesktop: false`, the window in use is still cropped from the framebuffer, and Notepad's Mac window
  matches the guest display at its frame (26,112 sampled pixels, none far off). A wrong `true` here would
  have frozen every window.
- Not seen yet: a real User Account Control prompt or the lock screen. Nothing was run in Windows to raise
  one, so the window for the secure desktop, its input, and its closing are still unit-tested only.

## Lag with several windows open, 2026-11-13

The user reported that Windows apps on the Mac still stutter, run at a low frame rate, and show "the
Windows screen behind". Nothing was opened or moved to look into it; the numbers come from the agent's own
capture counters, read twice ten seconds apart, and from process listings.

- **Windows behind another were printed all the time.** With Paint in front of Notepad and File Explorer and
  nothing changing, the agent ran `PrintWindow` 6.8 times a second, 40 ms on average and up to 531 ms, to
  see whether the two covered windows had changed. Each print makes the app draw itself again, in a guest
  that renders on the CPU. When a covered window does change, its stream goes to the fast pace and prints
  back to back.
- **Now:** the agent reports which parts of a covered window the display shows (`visibleRegion`). The host
  crops those parts from the guest display like a whole window, keeps the captured frame for the rest, and
  slows such a window's captures to one a second. A window hidden behind others entirely is slowed too.
  Three overlapping windows should cost about two prints a second in place of seven, and the visible parts
  of a window behind update at the display's pace.
- **A window that just opened** was cropped at once, while Windows was still fading it in over the desktop.
  It now waits out the same 0.3 seconds a moved window does, showing its captured frame. This may be the
  desktop the user saw; it was not reproduced.
- **Two app windows of one process** (two File Explorer windows) no longer count as one: the lower one was
  reported fully visible and showed the upper one's pixels.
- **The Mac was overloaded when this was measured:** a load average of 24 on 18 cores, with another virtual
  machine at 108% of a core, a second QEMU, Spotlight indexing, and four Simulator windows. Veil took 24%
  of a core and this guest's QEMU 40 to 47% with nothing changing. Some of the lag is that.
- Not done: the guest still renders on the CPU (gap 13), which bounds the frame rate of the window in use.
  A covering window's Windows shadow now shows on the visible part of the window behind it, next to the
  Mac shadow that is drawn there anyway. One agent test failed once in a 23-second run on the loaded Mac
  and passed in three runs after; which one was not captured.
- Not seen in the app: all of the above is unit-tested only until Veil is relaunched and the agent updated.

## Sixth relaunch and agent update on 2026-11-13

In the background, with the user's go-ahead; nothing was opened or moved in Windows.

- Veil did not come to the front, the three Mac windows opened where they were, and the agent went from
  `b5342bd09e85` to `43d15c91498f` in about six seconds with them open.
- **Prints of covered windows fell from 6.8 to 2.0 a second**, one per covered window, 25 ms on average,
  with the same three windows and nothing changing. All three windows are on the slow capture list.
- **The layout reports visible parts as designed:** Paint in front is fully visible, Notepad behind it
  shows a strip 64 pixels high along its bottom, and File Explorer, wholly behind Notepad, shows nothing.
- **Notepad's Mac window is right in both parts.** The strip matches the guest display (3,315 sampled
  pixels, mean difference 0.00); above it the window shows Notepad from its captured frame where the guest
  display shows Paint.
- **Found: the front window's Windows shadow in the strip.** Paint's shadow darkens Notepad for about 45
  pixels below Paint's edge, and the strip was cropped with it. The agent now leaves 48 pixels around each
  covering window out of the visible region. That fix is committed and not yet in the running agent.
- Not seen: a window opening, since none was opened, so the wait before a new window is cropped is still
  unit-tested only.

## Seventh relaunch and agent update on 2026-11-13

In the background, with the user's go-ahead; nothing was opened or moved in Windows.

- Veil did not come to the front, the three Mac windows opened where they were, and the agent went from
  `43d15c91498f` to `3eb6f3c5562b` with them open.
- **The dark band is gone.** With 48 pixels around the covering window left out, Notepad's visible strip
  is 16 pixels high, the rows that were darkened are back to the window's own colour, and the strip
  matches the guest display (780 sampled pixels, mean difference 0.00). Prints stayed at 2.0 a second.
- **A faint tail is left.** The strip's first row is still six levels of 255 darker than the status bar it
  belongs to, a tenth, fading out over the next 15 rows: the shadow reaches about 63 pixels. On this dark
  window it cannot be seen; on a light one it would be a grey step. The margin is now 64 pixels, committed
  and not yet in the running agent.

## Optimization pass on 2026-11-13

Done without relaunching Veil or touching the guest; unit-tested only until the next relaunch and agent
update. Tests: host core 1,015, host shell 301, agent 394, all passing.

- **Windows' visual effects are turned down.** The guest draws on the CPU, and the translucent materials
  and window animations of Windows 11 are the costly part of that. The agent switches off transparency,
  the minimize and maximize animation, and animations inside windows (`visual.effects.set.request`),
  saving what the user had so the switch puts it back. The Veil menu has Reduce Windows Visual Effects, on
  by default. How much frame time this saves is not measured yet; that is the first thing to read after
  the update.
- **The window scan costs less.** It asked the Desktop Window Manager about every top-level window, hidden
  helpers included, 125 times a second for as long as any window was tracked. Hidden windows now take one
  cheap call each, and the scan drops to 30 a second once nothing has moved for a second.
- **The agent reports processor totals** for itself and for Windows in its health answer, so the cost of
  mirroring inside the guest can be read from the Mac. Until now it could only be guessed from QEMU's
  share of a host core.
- **The shadow margin is 64 pixels** (see the seventh relaunch).
- The host was looked at and left alone: with three windows and nothing changing Veil takes about 6% of a
  core, and a sample shows it mostly waiting.

## Eighth relaunch and agent update on 2026-11-13

In the background, with the user's go-ahead; nothing was opened or moved in Windows. The Mac was busy
throughout (load average 28 to 39 on 18 cores), so the numbers are rough.

- Veil did not come to the front, the three Mac windows opened where they were, and the agent went from
  `3eb6f3c5562b` to `724862e1027c` with them open.
- **This guest's QEMU fell from 35 to 47% of a Mac core to 10 to 15%** with three windows open and nothing
  changing, read three times each. The earlier readings were taken before the window scan was cut down;
  the load on the Mac differed between them.
- **Inside Windows, mirroring now costs about 4% of one of its 8 cores at rest**, which is the two prints a
  second of the covered windows. All of Windows used 8 to 12% of one core.
- **Turning visual effects down made no difference that could be measured at rest**, and changed no pixel
  of the guest display: the agent read back transparency and both animations as off, and a screen dump
  before and after is identical in 40,960 sampled pixels. Without graphics acceleration Windows was
  apparently not drawing transparency in the first place. What it saves while windows open, close, and
  animate was not measured, since nothing was opened.
- **A setting changed from outside the app is not picked up.** `defaults write` on the running app's
  setting sent nothing in 30 seconds; the request was sent to the agent directly for this measurement.
  The switch in the Veil menu changes the setting inside the app, which is the path that is wired. Not
  tried, since that needs a click.
- With the shadow margin at 64 pixels, the 64-pixel strip of Notepad below Paint is left out whole, and
  Notepad counts as hidden behind Paint.
- **Next, not yet in the running agent:** streams held Windows' timer at 1 ms for as long as they ran, for
  every window open, even at one sample a second. They now hold it only while ticking fast.

## Administrator windows and the clock, 2026-11-13

Done without relaunching Veil or touching the guest. Tests: host core 1,028, host shell 301, agent 405,
all passing. None of it has run in the app or on the live guest; each needs an administrator prompt in
Windows, which only the user raises.

- **Windows run as administrator took no input.** Once an installer's prompt is approved its window runs
  above the agent, and Windows discards what the agent injects there without reporting it. The window was
  shown on the Mac and ignored every click and key. The agent now marks such windows in `window.layout`
  (`elevated`), and the host sends their mouse, keys, and plain text over QEMU's display connection as
  hardware input, aimed with the window's frame on the guest display. A press on a point another window
  covers in Windows is not sent, since it would land on that window. Text a US keyboard cannot type,
  Hangul included, is not sent to such a window; keys typed on the Mac keyboard go by position as usual.
- **The guest clock was 15 hours off and nothing said so.** This guest's tools were installed without
  administrator rights, so the task that corrects the clock is missing. The Veil menu now offers Set
  Windows Clock while that is the case; the agent asks Windows for approval and registers the task.
- **SYSTEM ran a file the user can write.** The clock task ran a script from the tools' folder under
  `%LOCALAPPDATA%`. It now runs two programs from the Windows directory. A guest that already has the
  older task keeps it until its tools are installed again as administrator.
- To check, in this order, once the next relaunch and agent update are in: Set Windows Clock from the Veil
  menu, which raises the approval prompt, which should open in its own Mac window; approving it there;
  then any installer, whose window should take clicks after its own prompt.

## Ninth relaunch and agent update on 2026-11-13

In the background, with the user's go-ahead; nothing was opened or moved in Windows.

- Veil did not come to the front, the three Mac windows opened where they were, and the agent went from
  `724862e1027c` to `e9d8f78b0ac0` with them open. It reports `timeSyncRepair` and `visualEffects`.
- **No ordinary window is taken for an administrator's.** Notepad, Paint, and File Explorer carry no
  `elevated` mark, so their input still goes through the agent. A wrong mark would have sent every click
  through the hardware path.
- **The host sends the visual effects setting on connecting**: `reduced=true: changed=false`, twice, once
  for each agent. This is the path a `defaults write` did not reach last time.
- **The guest clock is right again without the repair**: 669 and 740 ms from the Mac's, where it was 15
  hours off four hours earlier. Windows corrected it by itself in between; what triggered that is not
  known. Set Windows Clock therefore does not show now, and the repair stays unit-tested only.
- Paint's Mac window matches the guest display at its frame (30,820 sampled pixels, 41 far off).
- **Holding the fine timer only while ticking fast made no difference that could be measured**: Windows
  used 13% of one core at rest and the agent 6%, as before, and this guest's QEMU 12 to 24% of a Mac core
  in the minute after the update against 9 to 11% before it, with the Mac's load average at 18 to 26.
- Still not seen: an approval prompt in its own Mac window, and input reaching a window run as
  administrator. Both wait for the user to run something in Windows that asks for administrator rights.

## Second production pass on 2026-11-14

Done without relaunching Veil or touching the guest. Each item is covered by unit tests; none has run in
the app yet.

- **A full Mac disk failed Windows' writes instead of pausing it.** QEMU's NVMe controller, which carries
  the Windows disk, ignores the drive's `werror` policy and completes a write the Mac volume refused as an
  NVMe write fault (`nvme_rw_complete_cb` in `hw/nvme/ctrl.c`), which can corrupt the guest file system.
  Veil now reads the free space of the disk's volume every two seconds, pauses a running Windows below
  2 GiB, and continues it at 4 GiB, as Parallels does. It continues only a pause it made, says so in the
  menu bar menu and in a notification. This Mac had 74 GiB free (96% used) when this was written.
- **Opened with no Windows app open, the main window kept the whole Windows desktop.** Veil shows the
  desktop until the app connection is up and returned to apps only when an app window had a frame, which
  never came with no app open. It now returns as soon as the connection is up and no app window is waiting.
- **Stop turned off a Windows that was waiting on the user**, such as an app asking to save a document,
  when the shutdown deadline passed. It now asks: show Windows, keep it running, or turn it off. The
  automatic quiet after the last app window closes never turns Windows off.
- **QEMU exiting right after launch was reported as a running Windows.** The start now fails with the end
  of QEMU's output when QEMU exits within 800 ms.
- **The display connection was open to every account on the Mac.** QEMU's display server now listens on
  `/tmp/vq-*.vnc.sock`, and that socket, QMP, and the monitor are set to 0600. Checked headless with the
  bundled QEMU, which answered `RFB 003.008` on the socket. This takes effect from the next Windows start
  or resume; the running QEMU keeps its TCP port until then, and the app still connects to it.
- **WebDAV checked a path, then opened it by path again.** Reads, uploads, and the file a LOCK creates now
  check the path of the open descriptor (`F_GETPATH`).
- Translated the agent, launch result, and configuration titles into Korean.

Confirmed by reading, from the lifecycle audit: resume deletes the saved state only after the guest runs,
so that item was not a bug. Still open:

- The agent's port is a loopback TCP port; since 2026-11-14 a token keeps other accounts off it (below).
- The guest reaches every service on the Mac's loopback interface through QEMU's user networking.
- The system disk is opened with `file.locking=off`; only a process listing keeps two QEMUs off one disk.

## Tenth relaunch on 2026-11-14

Veil only, in the background, with the user's go-ahead; the agent was not updated (still `e9d8f78b0ac0`)
and nothing was opened or moved in Windows.

- Veil did not come to the front, the three Mac windows opened where they were, and the main window stayed
  off screen. The running QEMU keeps its TCP display port until Windows next starts.
- No disk space pause: the Mac volume has far more than 2 GiB free.
- **The guest clock loses the time the Mac sleeps.** It was 669 ms off at 22:09 on 2026-11-13, 3.4 hours
  off at 12:47, and 9.6 hours off after the Mac woke at 19:12; `pmset` shows the Mac asleep in between.
  The guest's clock does not run while the Mac sleeps, and the agent cannot set it without the elevated
  `VeilTimeSync` task, so every wake reports `install-time-sync-task-elevated`. The 2026-11-13 correction
  came from Windows itself. Set Windows Clock now shows in the Veil menu; using it once registers the task,
  after which the wake sync corrects the clock.

## Third production pass on 2026-11-14

Done without relaunching Veil or touching the guest; unit-tested only.

- **Quitting Veil left Windows running without a word** whenever "Suspend Windows when Veil quits" was
  off, still using memory and battery with nothing on screen. Veil now asks: suspend Windows, keep it
  running, or cancel, with "do not ask again". A logout, restart, or shutdown is not held up by the
  question, and changing the setting clears a remembered answer.
- **A wrong Windows clock was only a menu item.** When the clock is at least five minutes off and needs
  the repair, Veil posts one notification per session that names the skew and points at Set Windows Clock.
- **The guest event queue could hold 32 GiB** (1,024 messages of up to 32 MiB). Waiting bytes are now
  counted and the stream reconnects past 96 MiB. The frame channel was already bounded at 256 messages of
  1 MiB each, URLSession's default message limit.

## Eleventh relaunch on 2026-11-14

Veil only, in the background, with the user's go-ahead; the agent was not updated and nothing was opened
or moved in Windows.

- Veil did not come to the front; the three Mac windows opened where they were.
- **The wrong-clock notification was delivered**: NotificationCenter logged `org.uulab.veil.guest-clock-wrong`
  for Veil once, with the guest 9.6 hours behind (`skew 34404442 ms`).
- The hidden main window reported a 435 x 273 frame. It is resized to the preferred size whenever it is
  shown (`MainWindowChrome.fitToPreferredSize`), so nothing shows at that size.
- Not exercised: the quit question, which needs the user to quit Veil while Windows runs.

## Agent token on 2026-11-14

- **Another account on the Mac could drive Windows through the agent.** Veil now keeps one random token
  per Mac user in `Application Support/Veil/Agent Access/agent-token.smbios` (0700 folder, 0600 file),
  hands it to Windows on a cold boot as an SMBIOS OEM string through `-smbios type=11,path=`, and sends it
  in `X-Veil-Agent-Token` on every connection. The path, not the value, goes in QEMU's arguments: `ps`
  showed this account the arguments of root's processes, so other accounts can read QEMU's. An agent that
  finds the token refuses connections without it (401); without it, as before.
- Checked headless: the bundled QEMU 11.1.3 accepts the option with a path holding spaces and a doubled
  comma. A separate empty `virt` machine (TCG, the bundled EDK2 firmware, a test token) showed the string
  in the firmware's SMBIOS 3.0 table: `smbiosview -t 11` in the UEFI shell listed one type 11 structure,
  length 5, holding `org.uulab.veil.agent-token=<token>`. Windows reads SMBIOS from that table; the agent
  test `ReadsTheStructureQemuWritesForTheTokenFile` parses those exact bytes. Not yet seen in Windows
  itself, which needs Windows started again from Veil.
- Takes effect only with all three: Veil relaunched (sends the header), the agent updated (checks it), and
  Windows restarted (reads the tables). The order does not matter; none of them alone locks Veil out.

## Twelfth relaunch and agent update on 2026-11-14

In the background, with the user's go-ahead; Windows was not restarted and nothing was opened or moved in it.

- Veil did not come to the front, the three Mac windows opened where they were, and the agent went from
  `e9d8f78b0ac0` to `909fa2217f50` (its first attempt found no tools disc yet and the second ran).
- **The new agent accepts connections without a token while the machine carries none**: a probe sending
  no `X-Veil-Agent-Token` still got its health answer. The running QEMU started without `-smbios`, and no
  token file exists yet; both come with the next Windows start from Veil.
- Once, the Mac windows read 2,102 points to the left; three seconds later they were back. That was a Space
  switch on the Mac at that moment, not Veil moving them.
- Still to check after the next Windows start from Veil: that Windows sees the OEM string, so that a probe
  without the token gets 401 and Veil still connects.

## What stands between this branch and a production release, 2026-11-14

Code-side items that can be done without the user are done. What remains needs the user, an outside
service, or work outside this repository:

- **A notarized build.** `script/release_macos.sh` signs with hardened runtime, notarizes, staples, and
  checks Gatekeeper (`2026-08-03-notarized-macos-release.md`). This Mac has a Developer ID Application
  identity; a `notarytool` keychain profile and a run against Apple's service are still to do, and the
  current app is ad-hoc signed.
- **Updates of Veil itself.** There is no in-app update channel; it needs a decision on where releases are
  hosted.
- **GPU acceleration** (gap 13): Triton measured 72 fps against 23.5 with WARP, but Windows does not shut
  down with its driver.
- **Guest access to the Mac's loopback interface.** QEMU 11.1.3's user networking has no option to refuse
  it (`-netdev user` help lists none); closing it means patching libslirp's `disable_host_loopback` into
  the bundled QEMU and serving the shared folder through a fixed `guestfwd` instead.
- **Checks only the user can start**: the approval prompt in its own Mac window and input to an
  administrator's window (Set Windows Clock), the quit question, and the agent token after Windows is
  started again from Veil.

## Review of this session's changes, 2026-11-14

An independent read of `81e891a0..8e415a97` found five defects; all are fixed and unit-tested
(`f183cb33`, `8a2c1521`):

- The agent token was read once when Veil started, so a Windows first started from that Veil refused
  every later connection until Veil restarted, and Veil could start typing its tools repair into a
  healthy Windows. Connections now read it each time (cached two seconds).
- A disk-space pause lived only in memory: after a quit or crash nothing continued Windows. It is now
  recorded against the QEMU launch.
- Suspend, the automatic quiet, and the quit question could save memory to the nearly full volume and,
  on failure, continue Windows on it. They now leave a paused Windows paused.
- Stop on a paused Windows waited 90 seconds and then blamed unsaved documents; it now names the disk.
- Show Windows after a shutdown timeout stopped watching; Veil now waits for that shutdown and finishes.

The same review found nothing wrong in the WebDAV descriptor check (checked against case-folded paths and
hard links on APFS), the SMBIOS parsing, compatibility with a QEMU started before these changes, the event
byte budget, the quit reply, or the release scripts.

## Thirteenth relaunch on 2026-11-14

Veil only, in the background, with the user's go-ahead; nothing was opened or moved in Windows.

- The first build with Sparkle: the running Veil maps `Contents/Frameworks/Sparkle.framework` from its own
  bundle, so the rpath and the ad-hoc signing from `embed_sparkle.sh` work in the app itself. A
  development build has no `SUFeedURL`, so the updater does not start and Check for Updates is hidden.
- Veil did not come to the front; the three Mac windows opened where they were; the agent
  (`909fa2217f50`) connected, and the clock is still 9.6 hours behind until Set Windows Clock is used.

## Desktop showing through a dragged window, 2026-11-14

The user saw the Windows desktop in Paint's and Notepad's Mac windows while dragging them quickly. At the
end of each caption drag Veil moves the guest window; Windows presented the moved window before the
agent's next layout scan (33 ms apart once the layout is still) reached the host, and cropping the old
frame from that picture showed the desktop the window had just left. Since `fb8194da` the layout store
holds a window's last cropped picture from the move or resize request until the layout shows the new
frame and it settles, at most a second. Unit-tested; Veil was relaunched with it (fourteenth relaunch,
in the background, Veil not brought forward, agent connected). Whether the flash is gone needs the user
to drag a window. Moves Windows makes by itself, such as snapping, are not announced to Veil and can still
show it for a frame.
