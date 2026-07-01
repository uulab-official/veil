# VM Device Summary Checklist

- [x] Review UTM's Apple virtualization configuration structure for system, drive, network, display, and device separation.
- [x] Add typed storage, graphics, and device summary values to `VMRuntimeSnapshot`.
- [x] Populate the device summary from the stored Windows 11 Arm profile.
- [x] Share graphics and system-disk constants between diagnostics and the Virtualization.framework booter.
- [x] Include device summary metadata in diagnostics through the snapshot.
- [x] Add a VM Runtime `Device Plan` panel.
- [x] Test installer, system disk, NAT network, Virtio graphics, input, and entropy summary output.
- [ ] Compare the device summary with real `VZVirtualMachineConfiguration.validate()` errors after Windows ISO testing.
- [ ] Add removable installer/eject state after the Windows installation path is proven.
