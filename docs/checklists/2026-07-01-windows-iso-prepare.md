# Windows ISO Prepare Checklist

- [x] Verify `/Users/bonjin/Downloads/Win11_25H2_Korean_Arm64_v2.iso` exists.
- [x] Verify the ISO is detected as bootable ISO 9660 media.
- [x] Add `veil-vmctl prepare --installer <path>` for repeatable local VM setup.
- [x] Use `veil-vmctl` to create the default profile, shared folder, sparse disk, installer path, and diagnostics bundle.
- [x] Add `./script/build_and_run.sh --start-vm`.
- [x] Launch signed `Veil.app` with `--start-vm`.
- [x] Confirm `com.apple.Virtualization.VirtualMachine.xpc` is running.
- [x] Confirm EFI variable store and machine identifier files were created next to the VM disk.
- [ ] Complete Windows Setup in the VM console.
- [ ] Install the Veil Windows guest agent after Windows reaches the desktop.
