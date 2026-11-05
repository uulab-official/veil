# Project Brief

## One-Line Definition

Veil lets Apple Silicon Mac users run Windows apps as if they were native macOS windows, using a background Windows 11 Arm VM and a host/guest app bridge.

## Product Positioning

Veil is not trying to become a full Parallels Desktop replacement first. It targets the coherence-style experience:

```text
Windows app -> macOS window -> macOS-like input, clipboard, files, Dock, and notifications
```

## Target Users

- Mac users who need one or two Windows-only work apps.
- Public-sector, banking, tax, accounting, ERP, and office-tool users.
- Developers who need Windows tooling without living in a Windows desktop.
- Designers and solo operators who prefer macOS but must open Windows-specific apps.
- Teams issuing Macs while retaining legacy Windows workflows.

## Initial Scope

Host:

- macOS 15+
- Apple Silicon Macs

Guest:

- Windows 11 Arm (the product path: guest agent, app windows, clipboard, files)
- Bring-your-own license and installer media
- Secondary, plain-VM guests: Linux Arm64 on Hypervisor.framework, and x86_64 operating systems under
  QEMU's TCG emulator. These boot their installer and show a console like UTM does; they get no
  guest agent, app windows, or Windows-specific setup automation.

App types:

- Simple Win32 desktop apps
- Office/productivity apps
- Browsers and light business apps

Out of scope for v1:

- high-performance 3D games,
- advanced DirectX acceleration,
- app-window integration (coherence) for any guest other than Windows 11 Arm,
- performance targets for x86_64 guests (emulation is offered for compatibility, not speed),
- Intel Mac support,
- USB passthrough,
- printer/scanner/smart-card bridges.

### Scope change: other guests and x86_64 emulation (2026-11-05)

v1 originally listed x86 OS emulation as out of scope. On 2026-11-05 the project owner asked for UTM's
feature set ("UTM 기능은 다 가져오라"), so Linux Arm64 guests and x86_64 emulation moved into scope as
secondary features. Reasons:

- The engine is already QEMU, which runs these guests with no new dependency; the cost is a second
  boot plan and one more emulator binary (about 30 MB uncompressed, see docs/architecture.md).
- Users comparing Veil with UTM and Parallels expect to keep a Linux VM or an old x86 tool next to Windows.
- The Windows path stays unchanged: other guests use a separate plan type and their own folders, so
  they cannot regress the coherence loop.

The product principle below still describes the Windows path; other guests are an explicit,
VM-shaped feature reached from File > New Virtual Machine.

## Product Principle

The user should not think, "I am opening a VM." The user should think, "I am opening the Windows app I need."

## First Success Demo

```text
Click "Notepad" in Veil.
Windows VM starts in the background.
The Windows guest agent launches Notepad.
Only the Notepad window appears on macOS.
Mac keyboard and mouse input work.
Cmd+C and Cmd+V work.
The Windows desktop is not part of the normal user experience.
```
