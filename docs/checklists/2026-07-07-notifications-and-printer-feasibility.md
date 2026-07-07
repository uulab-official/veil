# Windows Notifications & Printer Bridge — Feasibility Research

Date: 2026-07-07

Goal: per `docs/roadmap.md`'s v1.5 "Daily Use" list, research the two
remaining unstarted items -- "Windows notifications to macOS notifications"
and "Initial printer bridge research" -- before proposing any implementation
plan. Both were explicitly flagged in the original v1.5 plan (see
`docs/checklists/` history) as needing feasibility research first, not a
build task. This document is that research; **no code was written for
either item.**

## Windows Notifications → macOS Notifications

### The original blocking question

Can `apps/windows-agent`'s unpackaged Win32 console guest agent read the
Windows notification center at all, given it has no MSIX package identity?

### Finding: yes, via a documented but non-trivial path

`UserNotificationListener` (the WinRT API that reads all of a user's
notifications, including from other apps) **requires package identity** --
confirmed via Microsoft's own docs: unpackaged apps "cannot access certain
Windows features," and `UserNotificationListener` is explicitly one of them.
An unpackaged `.exe` calling it today would get `APPMODEL_ERROR_NO_PACKAGE`.

However, Microsoft ships a specific, supported technique for exactly this
situation: **"packaging with external location"** (also called a *sparse
package*). It grants an existing unpackaged Win32 app package identity
*without* requiring MSIX conversion, without moving the app's binaries, and
without replacing its existing installer -- you register a small separate
identity package alongside the app, and the app's own `.exe` (wherever it
already lives) gains the ability to call identity-gated WinRT APIs,
including `UserNotificationListener`.

Two follow-up questions this raises, both resolved favorably:

1. **Does `userNotificationListener` need Microsoft Store approval, since
   it's a "restricted capability"?** No. Store approval is only required
   when *submitting to the Store*. Veil sideloads the guest agent via its
   own installer script, never through the Store, and Microsoft's docs are
   explicit that sideloaded apps declaring restricted capabilities need no
   approval at all -- approval is a Store-submission gate, not a
   runtime/OS gate.
2. **Does this need real code signing?** Yes, and this is the one genuine
   new cost. A sparse package must be signed with a certificate trusted on
   the target machine to install. For local development this can be a
   self-signed certificate added to the guest's Trusted People store (a
   scripted, one-time step); production distribution would want a real
   code-signing certificate. Veil's guest-agent install flow already runs
   elevated PowerShell for firewall/driver setup
   (`Repair-VeilAgentConnectivity.ps1`), so adding a certificate-trust step
   to that same elevated flow is a plausible, scoped extension -- not a new
   category of guest-side infrastructure.

### What the actual feature would require (not built, scoping only)

1. A sparse package manifest declaring the `userNotificationListener`
   capability (`uap3:Capability Name="userNotificationListener"`), signed
   with a certificate the install flow adds to Trusted People.
2. A one-time `UserNotificationListener.Current.RequestAccessAsync()` call
   at agent startup, which surfaces a real Windows permission prompt to the
   interactive user the first time -- this needs a real logged-in session,
   consistent with the guest agent's existing user-session assumption
   (already required for clipboard/input work today).
3. A polling or event-driven loop reading
   `UserNotificationListener.Current.GetNotificationsAsync(NotificationKinds.Toast)`,
   translated into a new protocol event (e.g. `notification.posted`) the
   host would render as a native macOS `UNUserNotificationCenter`
   notification -- this part is ordinary protocol/UI work matching the
   existing clipboard-sync pattern once the guest-side capability unlock is
   in place.

### Recommendation

Feasible, not blocked -- but real new cost (a signed sparse package + a
certificate-trust step in the install flow) that wasn't previously part of
the guest agent's shape. Worth a small, isolated follow-up spike that ships
*just* the sparse-package + signing + `RequestAccessAsync` plumbing behind a
feature flag, proven with one real notification round-tripped end to end
against the live QEMU/HVF guest, before building the full protocol
event/UI surface. Not attempted in this pass -- flagged as the next
concrete step, sized at roughly the same order of effort as the app-icons or
DPI-capture passes earlier this session.

## Printer Bridge — Initial Research

### The question

Can a Windows app running in the guest print to a printer physically
connected to (or shared by) the macOS host, without a new virtual printer
driver stack?

### Finding: Veil's existing QEMU networking mode already provides a path

Veil's QEMU launch plan (`QEMUWindowsBootPlan.swift`) uses
`-netdev user,id=net0,hostfwd=...` -- QEMU's **user-mode (SLIRP) networking**,
the same mode the guest-agent WebSocket connection already relies on. SLIRP
gives the guest a virtual NAT'd network where the macOS host is always
reachable at a fixed, well-known address (`10.0.2.2` by SLIRP convention),
with **no bridge, no tap device, and no additional QEMU configuration
needed** -- this is already true today, for free, because of how the
guest-agent port forwarding is already set up.

This means the most plausible printer bridge shape needs no new QEMU
device at all:

1. macOS host enables printer sharing (System Settings → Printers & Scanners
   → Share this printer), which exposes the printer via IPP over CUPS
   (typically port 631).
2. Inside the Windows guest, add a standard TCP/IP or IPP network printer
   pointing at `http://10.0.2.2:631/printers/<name>` -- using Windows' own
   built-in "Add a network printer" flow, no custom driver needed for the
   *transport*, only the usual print-driver matching any network printer
   setup already requires.
3. Veil's role would be mostly UX and automation: detecting shared macOS
   printers, offering a "share this Mac printer with Windows" action, and
   scripting the guest-side network-printer registration (likely via
   `Add-Printer`/`rundll32 printui.dll` PowerShell automation, matching the
   install flow's existing PowerShell-scripting pattern) rather than
   inventing new transport plumbing.

### Open questions for a real spike (not resolved here)

- Whether macOS's CUPS sharing binds in a way reachable from the SLIRP guest
  address by default, or needs an explicit `cupsd.conf`/firewall allowance
  (untested; needs a live experiment against the actual QEMU VM).
- Driver matching on the Windows side for non-AirPrint/non-IPP-Everywhere
  printers (older host-connected USB printers without a generic IPP
  driver may not "just work" the way modern IPP-Everywhere printers would).
- Whether this should be scoped to IPP-capable printers only for v1
  (recommended -- avoids needing to solve arbitrary driver installation on
  the guest for a first pass).

### Recommendation

More promising and lower-cost than notifications, because it needs no new
package-identity/signing infrastructure and reuses networking Veil already
has running. Right-sized next step: a manual, undocumented experiment
(enable Mac printer sharing, manually add an IPP network printer inside the
already-running Windows 11 Arm guest pointed at `10.0.2.2:631`, try printing
a test page) to confirm the SLIRP-reachability assumption before investing
in any Veil-side automation UI. Not attempted in this pass, since it
requires a physical or virtual/AirPrint-capable printer to test against,
which wasn't available in this session.

## Summary

| Item | Blocked? | Real new cost | Recommended next step |
|---|---|---|---|
| Windows notifications | No -- feasible via sparse package | Code signing + install-flow cert trust step | Isolated spike: sparse package + `RequestAccessAsync` + one round-tripped notification, before full protocol/UI work |
| Printer bridge | No -- SLIRP networking already reachable | Likely none (reuses existing QEMU networking) | Manual experiment: share a Mac printer, add it as an IPP network printer in the guest at `10.0.2.2`, confirm it prints |

Neither item is implemented in this pass -- both remain appropriately at the
"feasibility research done, scoped for a future spike" stage the original
v1.5 plan called for.

## Sources

- [Packaging overview - Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/)
- [Grant package identity by packaging with external location manually - Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps)
- [Grant package identity by packaging with external location - Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps-overview)
- [Notification listener - Windows apps | Microsoft Learn](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/notification-listener)
- [App capability declarations - UWP applications | Microsoft Learn](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations)
- [Create a certificate for package signing - MSIX | Microsoft Learn](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)
- [Creating a sparse signed Win32 app package | Andrew Leader](https://andrewleader.medium.com/creating-a-sparse-signed-win32-app-package-9809320cfaab)
