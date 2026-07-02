# Real Windows Start Checklist

Goal: keep the main Veil experience pointed at real local Windows boot and console visibility, not a standalone demo flow.

## Completed

- [x] Recenter the main screen on one Windows 11 Arm machine instead of a multi-section sidebar.
- [x] Keep the default window large enough for a VM-focused control surface.
- [x] Compact the default host window to a launcher-sized 1000 x 560 point control surface instead of a tall dashboard.
- [x] Replace the native window title with a custom Veil header that matches the focused setup launcher.
- [x] Keep runtime status and refresh in the custom header so the main screen stays simple.
- [x] Make the custom header draggable while preserving macOS traffic-light controls.
- [x] Add a macOS menu bar item so Veil can be reopened and controlled from the top system bar.
- [x] Fill the whole window and custom titlebar with one continuous product backdrop.
- [x] Replace the translucent system-looking header with a Discord-style custom dark titlebar surface.
- [x] Model the visible setup process as Get Windows, Prepare, Install, and Connect instead of a developer checklist.
- [x] Keep ISO, disk, runtime provider, and guest-agent details visible only as compact status metadata on the first screen.
- [x] Remove developer-style status badges from the first screen so the VM card reads like a product launcher.
- [x] Make the first screen a large Windows display preview with a central Play action instead of a setup dashboard.
- [x] Remove the pre-install Windows Apps bridge panel from the first runtime screen.
- [x] Replace the internal runtime card with a production-style Windows Setup Assistant surface.
- [x] Keep advanced setup, preflight, provider, resource, and device information behind the Details toggle.
- [x] Use icon-only secondary controls with tooltips so the primary action stays focused on installing Windows.
- [x] Remove scrolling from the primary Windows setup screen.
- [x] Make the primary setup action a large Play control, with secondary actions reduced to icon buttons.
- [x] Split the pre-install setup process from the post-install Windows start launcher.
- [x] Add a `windowsInstalled` runtime snapshot flag so the UI can switch to the one-click launcher only after setup.
- [x] Make the post-install launcher fill the full primary panel with the blue Windows display surface.
- [x] Simplify the pre-install assistant into one calm setup panel with a primary action, compact timeline, and ISO/Disk summaries.
- [x] Remove the visible setup timeline from the default install screen so it behaves like a Parallels-style single decision assistant.
- [x] Ensure the primary ready-state action calls the real VM start path.
- [x] Open the VM Console through `VZVirtualMachineView` when a local display is available.
- [x] Rename visible progress from automatic-install simulation to VM console handoff.
- [x] Keep Windows media user-provided and local-only.
- [x] Confirm Apple Virtualization can start the configured VM and produce a `running` boot report.
- [x] Capture that the current Apple Virtualization console can still appear black even after VM start succeeds.
- [x] Add guarded `veil-vmctl qemu-start` execution for the local QEMU/HVF compatibility provider.
- [x] Verify `qemu-start` opens a visible foreground QEMU Cocoa window.
- [x] Record current QEMU/HVF result: TianoCore/Arm UEFI is visible, but Windows Setup is not reached yet.
- [x] Generate a local `Autounattend.xml` during VM preparation so automatic setup has a real artifact to attach next.
- [x] Generate and attach `VeilAutoInstall.iso` as setup-readable automatic install media in local runtime plans.
- [x] Route the main app Start action to the local QEMU/HVF console when QEMU is available.
- [x] Verify the app-launched QEMU console opens a real foreground `QEMU Windows 11 Arm` Cocoa window.
- [x] Verify the app-launched console previously reached UEFI Shell instead of Windows Setup before boot-key input was automated.
- [x] Test USB storage, SCSI CD-ROM, and virtio-blk installer attachment variants; without boot-key input they all fell back to UEFI Shell on the current local machine.
- [x] Identify the Windows ISO boot timeout cause: Windows installer boot waits for a key press and falls back when no key is sent.
- [x] Add a short QEMU monitor socket and automatically send boot key input after VM start.
- [x] Verify the app-launched QEMU console reaches the Korean Windows 11 Setup product-key screen.
- [x] Check the current local VM state: QEMU is running, but the 128 GB Windows disk only has 16 KiB allocated, so Windows is not installed yet.
- [x] Check the current host integration state: no Windows guest agent is listening on `127.0.0.1:18444`.
- [x] Add QEMU `hostfwd=tcp::18444-:18444` so a future Windows guest agent can connect back to the macOS host through localhost.
- [x] Surface sparse-disk allocation evidence in the runtime snapshot so the main screen does not imply Windows is installed before setup completes.
- [x] Change the stopped runtime detail from a generic ready state to install-specific copy: not installed, setup can start, or installed.

## Next

- [ ] Promote disk/agent evidence into a first-class install-complete signal after the Windows guest agent connects.
- [ ] Improve `Autounattend.xml` so Windows Setup skips the product-key page without bundling a key.
- [ ] Restart the currently running QEMU VM so the new guest-agent port forwarding takes effect.
- [ ] Replace the static setup preview with a real VM screenshot once QEMU reaches Windows Setup.
- [ ] Add a QEMU screenshot/screencapture harness so boot failures can be compared visually, not only through serial text.
- [ ] Add recovery copy for common boot failures: bad ISO attachment, unsupported device model, EFI state, and disk format issues.
- [ ] Convert the console handoff timer into real runtime state events.
- [ ] After Windows reaches the desktop, install and auto-start the Veil guest agent.
- [ ] Set `windowsInstalled` from a real guest-agent or boot-completion signal instead of manual profile state.
