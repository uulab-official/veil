# [Balloon] ARM64: inflate and stats buffers are announced 0xB000 away from where the driver writes them

<!-- Filed as https://github.com/virtio-win/kvm-guest-drivers-windows/issues/1719 on 2026-11-11. -->

**Describe the bug**

On Windows 11 ARM64 under QEMU (`virt` machine, HVF), the Balloon driver from virtio-win 0.1.302 never
returns memory to the host. The guest does inflate: `actual` rises in steps of 512 pages, and the
inflate queue sees hundreds of requests.

Every PFN the device reads from the inflate buffer is 0, though. QEMU reports
`virtio_balloon_bad_addr 0x0` for all 353,280 entries, and the device's guest statistics stay unset.

Reading guest memory from the host shows why. The guest physical address the driver puts in the
descriptors is not where it wrote the data. For both of its DMA buffers, the data sits exactly `0xB000`
lower than the address announced to the device:

| Buffer | Address in the descriptor | Contents there | Where the driver's data actually is |
|---|---|---|---|
| Inflate PFN array (len 4096) | `0x11B4A0000` | all zeros | `0x11B495000`: 512 entries such as `0x23d952`, `0x23d953`, … |
| Stats buffer (len 100) | `0x11B49F000` | unrelated kernel data (`0xffffa50f…` pointers) | `0x11B494000`: 100 bytes of `0xFF` (the initial `RtlFillMemory(-1)`) |

The virtqueue rings for the same device are read correctly at the addresses the driver programmed. The
descriptor table is at `0x11B4A3000`, and QEMU sees valid descriptors and the advancing avail index. So
the problem is specific to the addresses returned for the common buffers from
`VirtIOWdfDeviceAllocDmaMemory` / `VirtIOWdfDeviceGetPhysicalAddress`
(`WdfCommonBufferGetAlignedLogicalAddress` plus the offset).

The two buffers are allocated back to back in `BalloonEvtDevicePrepareHardware`, and both are off by the
same 11 pages. That pattern suggests the address lookup returns the address of a different common
buffer, rather than an off-by-one inside one buffer. One possibility is a block left over from an earlier
D0 transition whose VA range was reused, but I have not confirmed this.

Two more problems are visible in 0.1.302 but are already fixed on master:

- The PFNs are 64-bit (`0x000000000023d952`). The spec and QEMU read 32-bit entries. This is fixed by
  9f96702d, "Submit 32-bit PFNs on the inflate/deflate queues".
- The stats queue is answered only once (`avail.idx` stays at 1), which looks like interrupts not
  reaching the driver. This may be addressed by d92b9c07, "Support MSI-X interrupts".

The address offset seems independent of both. Even 32-bit PFNs at the announced address would not
reach the device.

**To Reproduce**

1. Boot Windows 11 ARM64 with `-device virtio-balloon-pci,id=balloon0,guest-stats-polling-interval=5`
   and install `Balloon\w11\ARM64` from virtio-win-0.1.302.iso.
2. From QMP, run `balloon` with a target 1 GiB below `-m`.
3. Enable the trace events with `trace-event-set-state name=virtio_balloon_*`. Every entry logs
   `virtio_balloon_bad_addr 0x0`.
4. Inspect the descriptors and memory:
   - `x-query-virtio-queue-element path=/machine/peripheral/balloon0/virtio-backend queue=0 index=0`
     gives the descriptor address.
   - `xp /4gx <descriptor addr>` shows zeros.
   - `pmemsave` of RAM, then a search for a page of in-range 64-bit PFNs, finds the real array at
     `<descriptor addr> - 0xB000`. The stats page shows the same offset.

**Expected behavior**

The descriptors carry the guest physical address of the buffers the driver filled. The device then
reads the PFNs and the statistics, and the inflated pages are released.

**Host:**
 - macOS 27 (Darwin 27.0.0) on Apple silicon, Hypervisor.framework (`-accel hvf`).
 - QEMU 11.1.3, built from the release tarball with two local patches to `hw/virtio/virtio-balloon.c`:
   - releasing discarded pages with `MADV_FREE_REUSABLE` on macOS;
   - tracking partly ballooned 16 KiB host pages.

   Neither touches descriptor or address handling, and the zero PFNs are logged before any discard.
 - QEMU command line (relevant parts):
   ```
   qemu-system-aarch64 -machine virt,highmem=on -accel hvf -cpu host -smp 8 -m 16384M \
     -drive if=pflash,... (EDK2 ArmVirtQemu with Secure Boot) \
     -device tpm-tis-device,... \
     -device nvme,drive=system \
     -device virtio-net-pci,netdev=net0 -device virtio-rng-pci -device virtio-gpu-pci \
     -device virtio-balloon-pci,id=veil-balloon,deflate-on-oom=on,guest-stats-polling-interval=5
   ```
 - No libvirt.

**VM:**
 - Windows 11 ARM64, build 26300.
 - Driver: Balloon (`balloon.sys`, `Balloon\w11\ARM64`).
 - Version: virtio-win 0.1.302 (`DriverVer = 07/22/2026,100.103.104.30200`).

**Additional context**

The NetKVM and viogpudo drivers from the same ISO work on this VM. I have not yet built
Balloon from master to check whether the offset is still there after 9f96702d and d92b9c07. Doing so
needs test signing, and this VM runs with Secure Boot on. If someone can point me to a test build, I can
run the same memory inspection.
