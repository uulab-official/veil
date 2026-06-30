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
- USB passthrough,
- printer/scanner/smart-card bridges.

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
