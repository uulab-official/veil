# VM library and `.veilvm` bundles

Veil keeps a list of Windows machines. This page records where each machine's files live, what
clone, delete, export, and import do, and the `.veilvm` bundle format.

Code: `apps/mac-host/Sources/VeilHostCore/VMLibrary.swift`, `VMLibrary+Bundle.swift`;
sidebar: `apps/mac-host/Sources/VeilHostShell/Views/ControlCenterSidebar.swift`.

## Layout

`<support>` is `~/Library/Application Support/Veil` (or `VEIL_APPLICATION_SUPPORT_DIRECTORY`).

| | Original machine (`vm_default_windows11`) | Library machine (`vm_<12 hex>`) |
|---|---|---|
| Profile | `<support>/Profiles/default-vm-profile.json` | `<support>/Profiles/Machines/<id>.json` |
| Diagnostics, QEMU launch and suspend records, boot report | `<support>/Diagnostics/` | `<support>/Machines/<id>/Diagnostics/` |
| Disk, `uefi-vars.fd`, `tpm/` | `~/Virtual Machines/Veil/` | `~/Virtual Machines/Veil Machines/<id>/` |

`<support>/Profiles/library.json` holds the order and the selected machine:

```json
{ "machineIDs": ["vm_default_windows11", "vm_3f2a9c01b7de"], "selectedMachineID": "vm_3f2a9c01b7de" }
```

- The machine that existed before the library is referenced where it is. Nothing is moved,
  renamed, or rewritten when the library first loads; `library.json` is written only when a second
  machine is created, imported, or selected.
- With no `library.json`, every store resolves to the original paths, so a Mac with one machine
  behaves exactly as before.
- `uefi-vars.fd` and `tpm/` are always found next to the disk (`QEMUWindowsBootPlan`), which is why
  each library machine has its own folder.
- The shared folder (`~/Veil Shared`) is shared by all machines. The automatic-install media
  (`VeilAutoInstall.iso`, `Autounattend.xml`) is regenerated there when a machine is prepared, so
  preparing machine B rewrites the copy machine A attaches on its next boot. The content is the same
  except for the Windows account name; it only matters while a machine is still in Windows Setup.

## Selection and one machine at a time

`JSONVMProfileStore()`, `JSONQEMULaunchRecordStore()`, `JSONVMSuspensionRecordStore()`,
`JSONVMRuntimeBootReportStore()` and `QEMUVMRuntimeBooter` with no explicit directory resolve the
selected machine on every call (`QEMUVMRuntimeBooter.defaultDiagnosticsDirectory()`). The app and
`veil-vmctl` therefore act on whichever machine the sidebar selected.

Veil runs **one machine at a time**. The booter tracks one QEMU process, and the guest agent uses one
forwarded host port (127.0.0.1:18444). The sidebar refuses to switch, clone, export, or delete while
the selected machine is starting or running. A suspended machine can be switched away from; its
saved session stays in its own diagnostics folder and resumes when it is selected again.

## Operations

- **New**: writes a profile with a fresh id and this Mac's default resources, selects it, and the
  Installation Assistant sets up Windows the same way as on first run.
- **Rename**: changes `name` only. Paths do not change. Names are trimmed, limited to 64
  characters, and made unique ("Windows 11 Arm 2").
- **Clone**: refused while the source runs or is suspended (the disk is not consistent with the saved
  memory). The disk and `uefi-vars.fd` are copied with `clonefile(2)`, so on APFS the clone uses no
  extra space until either machine writes; across volumes it falls back to a full copy. `tpm/` is
  copied.
- **Delete**: refused while running. Moves to the Trash (never deletes): a library machine's disk
  folder, its `Machines/<id>` state folder, its saved memory state, and its profile. For the original
  machine only its disk (when it is inside `~/Virtual Machines/Veil`), `uefi-vars.fd`, `tpm/`, saved
  session, and profile go; other files in that folder stay. A disk the user picked from elsewhere and
  the shared folder are never moved.

### Clone, TPM, and UEFI variables

A clone is an exact twin, including the virtual TPM:

- Keeping the TPM keeps BitLocker, Windows Hello PINs, and TPM-bound credentials working in the copy.
  A fresh TPM would make a BitLocker-protected disk ask for its recovery key and break Hello.
- Both machines then share one Windows identity: computer name, machine SID, TPM endorsement key,
  and any Microsoft Entra / Intune device registration. Do not run both on the same network domain or
  enroll both in management. Generalize the copy with Sysprep (`sysprep /generalize /oobe`) if it
  needs its own identity
  ([Microsoft: Sysprep overview](https://learn.microsoft.com/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation)).
- The UEFI variables hold the "Windows Boot Manager" entry that points at the disk's EFI partition.
  The cloned disk has the same partition GUIDs, so the copied variables boot it unchanged.
- Windows activation may need to be redone on the copy; Veil makes no licensing claim about copies.

## `.veilvm` bundle (format version 1)

A folder named `<name>.veilvm`:

```text
Windows 11 Arm.veilvm/
  veilvm.json      manifest (below)
  Disk.img         raw system disk (optional)
  uefi-vars.fd     UEFI variable store (optional)
  tpm/             swtpm state folder (optional)
```

`veilvm.json`:

```json
{
  "formatVersion": 1,
  "exportedAt": "2026-11-05T09:00:00Z",
  "disk": "Disk.img",
  "firmwareVariables": "uefi-vars.fd",
  "tpmState": "tpm",
  "profile": { "id": "...", "name": "Windows 11 Arm", "os": "windows-arm64", "cpuCount": 4,
               "memoryMB": 8192, "diskGB": 128, "autoStart": true, "suspendOnQuit": true,
               "sharedFolderPath": "", "windowsInstalled": true, "createdAt": "..." }
}
```

- `profile` is the `VMProfile` JSON (ISO 8601 dates). Export removes every host path and bookmark
  (`installerMediaPath`, `driverMediaPath`, `virtualDiskPath`, `sharedFolderPath`, the
  `*BookmarkData` fields) and `guestAgentConnectedAt`, because they point into the exporting Mac and
  carry its user name.
- `disk`, `firmwareVariables`, `tpmState` are bundle-relative names, or absent.
- Export is refused while the machine runs or is suspended; a saved memory state is never exported.
- Export clones files when the destination is on the same APFS volume.

Import treats the bundle as untrusted:

- `formatVersion` must be 1.
- Each named entry must be a single path component at the bundle root (no `/`, `.`, `..`), must not
  be a symbolic link, and `tpm/` must contain no symbolic links. Otherwise nothing is imported.
- The machine gets a new id, a unique name, this Mac's `~/Veil Shared`, and CPU and memory clamped to
  this Mac's limits. The Windows account name is sanitized again.
- After import the app prepares the machine (creates `uefi-vars.fd` from the firmware template if
  the bundle had none, and the `tpm/` folder), then a boot plan can be built from it.

The bundle is a plain folder; Veil does not register a document package type yet, so Finder shows it
as a folder.

## Importing another hypervisor's disk

"Import Disk Image…" accepts `.vhdx`, `.vhd`, `.vmdk`, `.qcow2`/`.qcow`, and raw `.img`/`.raw`. Non-raw
disks are converted with:

```text
qemu-img convert -f <vhdx|vpc|vmdk|qcow2> -O raw <source> <machine folder>/Windows.img
```

The source is only read. A raw disk is cloned instead. Veil boots raw images today; if the qcow2
default lands, the target format changes with it.

`qemu-img` lookup: next to every `qemu-system-aarch64` Veil knows (app bundle `Runtime/bin`,
`<support>/Runtime/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, user Homebrew
prefixes). The bundled runtime does not ship `qemu-img` yet (a separate change adds it), so today the
import usually uses Homebrew's `qemu-img` and says so when it is missing.

An imported disk has no UEFI variables or TPM state. Windows boots through its fallback loader
(`\EFI\Boot\bootaa64.efi`) and Windows Boot Manager re-registers itself. A BitLocker-protected disk
asks for its recovery key because the TPM is new. Only Windows 11 Arm disks boot; an x64 disk does not.
