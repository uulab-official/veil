# Auto Installer Assistant Checklist

Goal: move Veil toward the Parallels-style install assistant flow while keeping Windows media and license boundaries user-owned.

- [x] Confirm Parallels-style expectation: Windows can be downloaded/installed through an assistant, but licensing remains user-provided.
- [x] Replace automatic `~/Downloads` ISO discovery with explicit ISO selection.
- [x] Preserve manually configured installer media instead of overwriting it.
- [x] Keep selection conservative: installer media must be a user-selected `.iso`.
- [x] Update VM Runtime UI copy to describe Auto Prepare.
- [x] Update the roadmap with explicit ISO selection.
- [x] Add regression tests for avoiding automatic Downloads scans and preserving manual paths.
- [x] Generate `Autounattend.xml` during `Prepare VM`.
- [x] Generate `VeilAutoInstall.iso` during `Prepare VM`.
- [x] Treat the unattended answer file as a boot-readiness step.
- [x] Keep the answer file free of product keys, activation material, and bundled Windows media.
- [x] Attach the generated automatic install ISO in Apple Virtualization and QEMU/HVF boot plans.
- [x] Generate UEFI/GPT Disk 0 partitioning plus `InstallTo` Disk 0 Partition 3 for Windows Setup.
- [x] Hide disk/image setup UI with `WillShowUI=Never` while keeping product-key values absent.
- [x] Verify bounded QEMU/HVF smoke reaches the Korean Windows 11 installing screen at 32%.
- [x] Block stale Downloads ISO paths without security-scoped bookmarks so macOS permission prompts are handled through Veil's own setup flow.

## Next

- [ ] Run a persistent visible QEMU/HVF install through first reboot.
- [ ] Generate first-run guest-agent install scripts after Windows reaches the desktop.

Verification:

```sh
swift build --product veil-host-shell
swift test
git diff --check
```
