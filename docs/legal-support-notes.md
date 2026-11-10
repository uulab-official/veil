# Legal and Support Notes

This document is not legal advice. It exists to keep product and README wording honest.

## macOS Direct Distribution

The local `script/build_and_run.sh` output is an ad-hoc signed development bundle and must not be published as a trusted download. Direct downloads require an Apple-issued Developer ID Application certificate, hardened runtime, Apple notarization, a stapled ticket, and successful Gatekeeper assessment. Release entitlements must not enable `com.apple.security.get-task-allow`.

Signing private keys and notarization credentials must stay in the maintainer's Keychain or approved CI secret store. They must never be committed, included in archives, or written to release reports.

Official references: https://developer.apple.com/developer-id/ and https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Bundled Windows Engine

Veil.app ships an open-source local VM engine under `Contents/Resources/Runtime`, assembled by `script/bundle_qemu_runtime.sh`:

- QEMU (`qemu-system-aarch64` and `qemu-img`, GPL-2.0) and the libraries they link (LGPL/GPL/BSD/MIT; each listed in `Runtime/licenses/NOTICE.md`), `qemu-system-aarch64` is built by `script/build_patched_qemu.sh` from the same upstream tarball Homebrew pins, with the patches in `script/qemu-patches/` (see its README); the bundle carries those patches and `qemu-PROVENANCE.md` next to the binary, and the upstream source that `script/collect_engine_sources.sh` already downloads for the `qemu` formula is the corresponding source before the patches. When that build is unavailable the bundle falls back to Homebrew's unpatched binary.
- swtpm and libtpms (BSD-3-Clause) for the TPM 2.0 device Windows 11 Setup checks,
- QEMU's own Arm UEFI firmware (EDK2, BSD-2-Clause-Patent).
- Veil's Secure Boot Arm UEFI firmware, built by `script/build_secure_firmware.sh` from upstream [TianoCore EDK2](https://github.com/tianocore/edk2) at the commit QEMU 11.1 pins, with QEMU's ArmVirtQemu recipe plus `SECURE_BOOT_ENABLE`. Its variable store enrolls Microsoft's published Secure Boot certificates (PK "Windows OEM Devices PK", the 2011 and 2023 KEK and db certificates) with [virt-firmware](https://gitlab.com/kraxel/virt-firmware); no private key is generated or shipped. The bundle carries `edk2-secure-PROVENANCE.md` and the EDK2 license. Debian's `qemu-efi-aarch64` builds were tried and do not boot the Windows 11 Arm installer, so no distribution firmware is used. dbx holds only a placeholder entry, so revocations come from Windows servicing; see Microsoft's [Windows Secure Boot key creation and management guidance](https://learn.microsoft.com/windows-hardware/manufacture/desktop/windows-secure-boot-key-creation-and-management-guidance).

Each bundled binary is a separate executable launched by the host app, not linked into it. The bundle carries the upstream license texts and `NOTICE.md` with the exact versions and source locations. A published release must also satisfy GPL-2.0 section 3 for QEMU and the LGPL terms of its libraries. `script/collect_engine_sources.sh` lists every bundled Homebrew formula with its license, source URL, and formula file (which holds Homebrew's patches) in `SOURCES.md` and downloads the upstream source of each copyleft formula; `.github/workflows/release.yml` attaches both to every GitHub release next to `Veil.zip`. Nothing in the engine is Windows, a Windows image, or a component of another virtualization product; Veil no longer needs Homebrew installed. A build without the bundled Secure Boot firmware still looks for one in `~/Library/Application Support/Veil/Firmware` and then in an installed UTM.

Official references: https://www.qemu.org/license/ and https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

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

Veil must not upload, mirror, or serve Windows ISO files through project-owned storage, including Appwrite Storage buckets or other object-storage services. If a future Appwrite integration exists, it may store only metadata such as official download-page references, hashes supplied by the user, setup state, or user-owned private file references. It must not make Veil a Windows image distributor.

Veil may load Microsoft's official Windows 11 Arm64 download page, select the page's current Arm64 edition and a language derived from the Mac locale, and receive the resulting ISO response directly from Microsoft into Veil's local Application Support directory. This flow must keep the official page available as an inspectable/manual fallback, accept downloads only over HTTPS from Microsoft-owned domains, and retain an existing-ISO fallback. Veil must not depend on Microsoft's unpublished software-download connector as a stable API, manufacture a permanent ISO URL, bypass Microsoft's page workflow, or proxy the response through project infrastructure. Downloading media does not grant a Windows license or activation rights.

Official references:

- Windows 11 Arm ISO overview: https://learn.microsoft.com/en-us/windows/arm/iso
- Download Windows 11 for Arm-based PCs: https://www.microsoft.com/en-us/software-download/windows11arm64

## VirtIO Driver Media

Windows 11 Arm has no inbox driver for QEMU's `virtio-net-pci` NIC, and it binds QEMU's `usb-net` gadget as a serial port rather than a network adapter, so without a driver the guest never gets an IPv4 address. When the profile has no driver ISO, the app downloads Fedora's virtio-win ISO onto the user's Mac (`~/Library/Application Support/Veil/Downloads`), attaches it read-only, and the generated answer file installs its NetKVM driver.

- Source: the Fedora virtio-win project, which publishes the ISO under https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/ and documents it at https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md. Veil pins one release, 0.1.302 (`archive-virtio/virtio-win-0.1.302-1/virtio-win-0.1.302.iso`, 877,373,440 bytes), which is where the `stable-virtio` link pointed on November 5, 2026, instead of following that moving link.
- Integrity: Fedora's release `CHECKSUM` file lists MD5 sums for the RPMs only, not the ISO, so there is no publisher hash to compare against. Veil pins SHA-256 `303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d`, computed when the release was adopted on November 5, 2026, and deletes any download that does not match. Downloads are accepted only over HTTPS from `fedorapeople.org/groups/virt/virtio-win/`; redirects elsewhere are refused. Moving to a new release means downloading it, recording its SHA-256, and updating `VirtioWinDriverMedia`.
- License: the ISO's `virtio-win_license.txt` is a BSD 3-clause license (copyright Red Hat, Google, Virtuozzo, IBM). The Windows 11 Arm64 driver catalogs in 0.1.302 (`NetKVM`, `viogpudo`, `vioscsi`, `viostor`) are signed by "Microsoft Windows Hardware Compatibility Publisher", which is why they load with Secure Boot on.
- Distribution: the ISO is not committed, bundled in Veil.app, mirrored, or proxied. Each Mac fetches it from Fedora. A user can still pick a different driver ISO in Windows Settings, and Veil then downloads nothing.
- Support wording: Veil uses these drivers; it does not claim Red Hat, Fedora, or Microsoft support for Windows on Veil.

Official references for the answer-file mechanism:

- RunSynchronous (specialize commands run in order as SYSTEM): https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous
- RunSynchronousCommand `Path` (259-character limit): https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous-runsynchronouscommand-path
- FirstLogonCommands (now all start at once, so they cannot order a driver before the agent): https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands
- PnPUtil `/add-driver ... /install`: https://learn.microsoft.com/windows-hardware/drivers/devtest/pnputil-command-syntax
- PnpCustomizationsWinPE `DriverPaths` (needs a fixed local or UNC path, which a USB volume's changing drive letter cannot give): https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-pnpcustomizationswinpe-driverpaths

## Unattended Setup Keys

Generated answer files must not include Windows product keys, including generic setup keys. Microsoft documents `microsoft-windows-setup\UserData\ProductKey\Key` as a 25-character product-key value and explicitly notes that empty values are unsupported:

- https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-userdata-productkey-key

Veil may set `ProductKey/WillShowUI` to control whether Windows Setup shows the product-key UI, but it must not emit a `ProductKey/Key` value. That keeps the setup assistant from acting as a key distributor or activation workaround.

When Veil needs to reduce edition-selection prompts, it should prefer Windows Setup image metadata such as `/IMAGE/NAME` in `ImageInstall/OSImage/InstallFrom/MetaData`, which Microsoft documents as selecting an edition or image from a `.wim` file:

- https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-imageinstall-osimage-installfrom-metadata

Veil may generate unattended disk configuration only for the blank local VM disk it creates or the user explicitly assigns to the VM profile. Disk wiping must remain scoped to the guest VM disk (`DiskID` 0 inside Windows Setup), never to a host volume. Microsoft documents `DiskConfiguration`, `CreatePartition`, and UEFI/GPT partitioning as Windows Setup mechanisms:

- https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-diskconfiguration
- https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-setup-diskconfiguration-disk-createpartitions-createpartition
- https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions?view=windows-11

## Serverless Runtime Wording

Veil's VM execution layer is a local runtime provider. Product and architecture docs should not describe this as a cloud backend, hosted Windows backend, or server VM backend. If QEMU/HVF is added later, it is still a local runtime provider launched by the macOS app, not a remote service.

## Microsoft Support Position

Microsoft's public support page for Windows 11 on Apple Silicon Macs currently points users to Windows 365 Cloud PCs or Parallels Desktop when a Windows PC is not available:

- https://support.microsoft.com/en-us/windows/experience/platform-variants/options-for-using-windows-11-with-mac-computers-with-apple-m1-m2-and-m3-chips

Project wording should avoid saying Veil is Microsoft-authorized unless that becomes true.

## Windows Package Identity

Some Windows APIs require the calling process to have package identity. Veil's
guest agent exposes `agent.health.response.capabilities.packageIdentity` only as
a local readiness signal, not as a licensing, store distribution, or Microsoft
support claim.

Sparse package signing material is sensitive. Do not commit generated `.pfx`,
`.cer`, or `.msix` artifacts; only the source manifests and scripts belong in
the repository. A development `.pfx` contains a private key and should remain
local to the test Windows machine.

Official references:

- `GetCurrentPackageFullName`: https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-getcurrentpackagefullname
- Detect package identity: https://learn.microsoft.com/en-us/windows/msix/detect-package-identity
- Grant package identity by packaging with external location: https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/grant-identity-to-nonpackaged-apps

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
