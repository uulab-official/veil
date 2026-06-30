# Legal and Support Notes

This document is not legal advice. It exists to keep product and README wording honest.

## Windows Distribution

Veil must not bundle:

- Windows installers,
- Windows images,
- product keys,
- activation workarounds,
- proprietary Parallels components,
- closed-source guest tools from other virtualization products.

The project should use a bring-your-own Windows model until a different distribution path is explicitly reviewed.

The local VM profile stored by the host app is configuration. The host may create a blank virtual disk file for a user-owned VM, but it must not be described as a Windows installer, activation flow, license grant, or Windows image provider.

Installer media and virtual disk paths in the local profile are local references. Veil may validate that those references still point to local files and may create an empty disk file for later VM use. Storing, checking, or creating those local resources does not imply Veil distributes Windows media, creates a licensed Windows installation, or validates whether a selected file is suitable for Windows installation.

Starting a local virtual machine with user-provided installer media and a blank disk is a VM lifecycle feature. It must not be described as Windows distribution, Windows activation, Windows support from Microsoft, or official Apple endorsement.

## Microsoft Support Position

Microsoft's public support page for Windows 11 on Apple Silicon Macs currently points users to Windows 365 Cloud PCs or Parallels Desktop when a Windows PC is not available:

- https://support.microsoft.com/en-us/windows/experience/platform-variants/options-for-using-windows-11-with-mac-computers-with-apple-m1-m2-and-m3-chips

Project wording should avoid saying Veil is Microsoft-authorized unless that becomes true.

## Apple Virtualization.framework

Relevant Apple documentation:

- Virtualization framework: https://developer.apple.com/documentation/virtualization
- `VZVirtualMachine`: https://developer.apple.com/documentation/virtualization/vzvirtualmachine
- Shared directories: https://developer.apple.com/documentation/virtualization/shared-directories
- Clipboard sharing: https://developer.apple.com/documentation/virtualization/clipboard-sharing

Important wording rule:

- It is safe to say Veil researches use of Apple's Virtualization.framework for VM lifecycle.
- Do not imply Apple endorses Veil or officially supports every intended Windows guest flow.

## Trademark Wording

- Windows is a Microsoft product.
- macOS, Mac, and Apple Silicon are Apple products.
- Parallels Desktop is a Parallels product.

Use product names only to describe compatibility goals or market context.

## Contributor Rule

Any PR that changes public claims about Windows support, Apple support, licensing, or distribution must update this file.
