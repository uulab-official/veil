# Guest Follows Host: Time, Appearance, Battery

Parity gap 12: Windows should follow the Mac's clock, light/dark appearance, and battery, the way
Parallels Tools does. Protocol shapes are in `docs/protocol.md` ("Guest Time Sync", "Guest Appearance",
"Battery"). This note records why each part is built the way it is.

## Time

### Why the guest clock goes stale

Windows reads the real-time clock at boot and keeps its own clock after that. Two Veil paths stop the
guest without Windows knowing:

- **Session resume.** `QEMUVMSuspension` restores a saved machine with QEMU migration. The guest continues
  from the instant it was saved, with that instant's clock.
- **Long Mac sleep.** The QEMU process is frozen along with the rest of macOS, so the guest loses the
  whole sleep.

### Why the host sends its time instead of the guest asking

The host knows when either event happened (`NSWorkspace.didWakeNotification`, the suspended-to-running
state change). The guest does not. So the host sends `time.sync.request` and the guest compares.

### Why there are two correction paths

The agent runs as the interactive user with a limited token (`-RunLevel Limited` in
`Install-VeilAgent.ps1`), and it has to: an elevated agent would launch elevated child apps and break
window control (see the comment in `Repair-VeilAgentConnectivity.ps1`). Setting the clock needs
`SeSystemtimePrivilege`, which a UAC-filtered token does not have
([SetSystemTime](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-setsystemtime)).

- **`SetSystemTime`** is tried first and only works when the agent happens to be elevated.
- **The `VeilTimeSync` scheduled task** is the normal path. An elevated install registers it to run
  as SYSTEM and grants the installing user read and execute rights on that one task, so the
  limited-token agent can start it with `schtasks /Run` but cannot change what it runs.

The SYSTEM task runs `w32tm /resync` and takes no input. It could have set the clock from `hostUtc`, but
then any program running as the user could write a value for SYSTEM to apply. Network time takes no
caller input, at the cost of needing the Mac to be online. That trade is recorded in the response:
`resync-requested` is never reported as `corrected`.

The elevated install also sets W32Time's `MaxPosPhaseCorrection` and `MaxNegPhaseCorrection` to
`0xFFFFFFFF`. Their standalone-machine defaults reject corrections larger than 15 hours, which is the
long-sleep case itself ([Windows Time service tools and settings](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)).

### What is not covered

- A guest installed without elevation reports `failed` with
  `recommendedAction: install-time-sync-task-elevated` until the installer is run as administrator once.
- An offline Mac with a limited-token agent stays stale until network time answers.
- Not yet verified on the live Windows 11 Arm guest. The `schtasks /Run` permission grant is the part
  most likely to need adjustment.

## Appearance

The guest writes two per-user DWORDs under
`HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`:

- `AppsUseLightTheme` (app mode),
- `SystemUsesLightTheme` (taskbar and Start).

It then broadcasts `WM_SETTINGCHANGE` with `lParam = "ImmersiveColorSet"`
([WM_SETTINGCHANGE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange)).

These are the values Settings > Personalization > Colors writes. Microsoft does not document them as
an API. Its supported guidance for apps is to *read* the theme through `UISettings`
([Support dark and light themes in Win32 apps](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-windows-themes)).
There is no documented API for *setting* the user's theme. Because of that, the agent:

- reads the values back after writing,
- reports what it found,
- and fails with `appearance_set_failed` if they did not take effect.

Running apps that handle the broadcast repaint at once. Apps that cache the theme at startup change on
their next launch.

HKCU needs no elevation. The host setting "Match Mac Appearance in Windows" (menu bar menu, on by default)
controls the feature. Turning it off stops syncing but leaves Windows in its current theme.

## Battery: not feasible on the current machine model

Checked against the QEMU that Veil uses (`qemu-system-aarch64 --version` reports 11.1.3, Homebrew):

- `qemu-system-aarch64 -device help` lists 360 device types. None is a battery, AC adapter, or other
  power-supply device. The only ACPI-named device is `acpi-erst`, an error-record store unrelated to
  power.
- `qemu-system-aarch64 -machine virt,help` has no battery or power-supply property.

Windows learns about a battery through ACPI. It needs either a Control Method Battery (`PNP0C0A`) whose
AML methods (`_BIF`/`_BIX`, `_BST`) return live values, or a vendor battery miniclass driver. Neither
exists here:

- The `virt` machine builds its own ACPI tables, and they contain no battery.
- A static table supplied with `-acpitable` cannot report changing charge, because nothing on `virt`
  backs AML reads with live host data.
- A guest battery miniclass driver would be a kernel driver. It would need signing and is far outside the
  agent's scope.

So battery sync is skipped and documented as unsupported. Veil makes no battery claim. Revisit if
upstream QEMU adds a battery device that `virt` can expose.
