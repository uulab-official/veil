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

- Windows 11 Arm
- Bring-your-own license and installer media

App types:

- Simple Win32 desktop apps
- Office/productivity apps
- Browsers and light business apps

Out of scope for v1:

- high-performance 3D games,
- advanced DirectX acceleration,
- x86 Windows OS emulation,
- Intel Mac support,
- printer/scanner/smart-card bridges.

USB passthrough was on this list until 2026-11-05, when the product goal became UTM feature parity
("UTM 기능은 다 가져오라"). It is now in scope as UTM ships it: a running Windows can be handed a USB
device on this Mac and give it back, from Configuration > USB Devices. It stays bounded by macOS, not by
Veil: a device a macOS driver already owns (keyboards, mice, disks, most audio devices) can only be
captured with Apple's `com.apple.vm.device-access` entitlement or root, which Veil does not have. See
[The Privilege Boundary](architecture.md#the-privilege-boundary).

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
