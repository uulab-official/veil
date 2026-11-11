# QEMU patches

Patches Veil applies on top of upstream QEMU. `script/build_patched_qemu.sh` builds
`qemu-system-aarch64` from the release Homebrew ships with every patch here, and
`script/bundle_qemu_runtime.sh` bundles it (with these patches under `Runtime/licenses/qemu-patches/`)
in place of Homebrew's binary. `qemu-img` and the data files stay Homebrew's.

| Patch | Against | Status |
|---|---|---|
| `0001-virtio-balloon-release-discarded-pages-on-darwin.patch` | QEMU 11.1.3 (`qemu-11.1.3.tar.xz`, SHA-256 `5a8289c7…4b22`, the tarball Homebrew pins); also applies cleanly to UTM's `utm-edition` (QEMU 10.0.12) | Built and measured, see below. |
| `0002-virtio-balloon-track-partial-host-pages-across-the-guest.patch` | QEMU 11.1.3 after 0001 | Built; no regression on Linux. Its effect on Windows is not measured yet (see below). |
| `0003-ui-add-a-shared-memory-display-listener.patch` | QEMU 11.1.3 after 0002 | Built; an Alpine guest's console arrived in shared memory (1280x800, 42 frames in 8 s of boot). |

## 0001: the memory balloon gives memory back to macOS

On Darwin `MADV_DONTNEED` does not free a page: the page stays resident, keeps its contents, and still
counts in the process footprint. A 1 GiB anonymous mapping, touched and then advised, kept its
1026 MB footprint; `MADV_FREE_REUSABLE` on half of it dropped the footprint to 514 MB. QEMU discards
balloon pages through `ram_block_discard_range()`, which uses `MADV_DONTNEED`, so an inflated
balloon returned nothing to macOS. Measured with an Alpine 3.24 guest (2 GiB, 900 MB touched and
freed, then ballooned to 512 MB): QEMU's footprint went from 1229 MB to 1843 MB unpatched and to
329 MB patched; deflating and touching 600 MB again left the guest working. The patch adds `MADV_FREE_REUSABLE` after the discard on the
balloon paths only, and `MADV_FREE_REUSE` before a deflated page is reused. Other discard users
(migration, virtio-mem) are left alone because they may rely on discarded pages reading back as zero.

The host side is `QEMUMemoryBalloon` and `QEMUMemoryBalloonPolicy` in
`apps/mac-host/Sources/VeilHostCore`; the host sizes the balloon only on a QEMU bundled with this
patch. Linux's free page reporting (`free-page-reporting=on`) returned nothing in 20 s with either
build and the Windows driver does not implement it, so Veil does not enable it.

### Windows guest, first live run (2026-11-10)

Not yet effective for Windows. With the patched runtime, Windows 11 Arm 26300 bound the virtio-win
0.1.302 Balloon driver and began inflating (QEMU logged its "backing page size > 4kiB" warning on
the first inflated page), but:

- QEMU's footprint rose from 17.1 GB to 21.3 GB instead of falling. Apple silicon backs guest RAM
  with 16 KiB host pages, and QEMU discards one only after all four of its 4 KiB balloon pages
  arrive while it is still the single partially ballooned page it tracks. Windows hands back
  scattered 4 KiB pages, so the tracking restarts on nearly every page and almost nothing is
  discarded. 0002 tracks partially ballooned host pages across the whole guest instead.
- `query-balloon` kept reporting 16 GiB and every `guest-stats` value stayed unset (QEMU prints
  them as 2^64-1), so `QEMUMemoryBalloonPolicy` sees no statistics and leaves Windows at full size.
  The driver appears to fill statistics only through its user-mode service, `blnsvr.exe`.

QEMU's `virtio_balloon_*` trace events then showed the deeper problem. Asked for 1 GiB, Windows
updated `actual` in 512-page steps exactly as the driver source says, but every one of the 353,280
page frame numbers it queued arrived as 0 (`virtio_balloon_bad_addr 0x0`), so QEMU discarded
nothing. The statistics buffer likewise always reads as the -1 fill the driver writes when it
allocates it. In both cases QEMU sees the driver's DMA buffer as first initialised and never the
values written later. NetKVM, on the same machine, works. Until the ARM64 Balloon driver's buffers
reach QEMU, the balloon cannot return Windows memory, and `QEMUMemoryBalloonPolicy` leaves Windows
at full size because it never gets statistics. No public report of this was found.

## 0003: the guest display in shared memory

Adds `-object veil-shm-display,id=veilfb,path=<socket>`. A display change listener on the default console
copies the surface into a POSIX shared-memory object and copies each dirty rectangle into it as the
guest flushes. It tells one client over a Unix socket, as newline-terminated JSON, which object holds
the display (`surface`) and which rectangles changed (`update`). A client that falls behind gets one
full update once its socket drains.

The point is to replace QEMU's loopback VNC server as the source of the Coherence framebuffer
(`docs/superpowers/specs/2026-11-10-coherence-framebuffer-design.md`, stage 4). VNC sends on a 30 ms
refresh tick and copies every frame through a socket.

QEMU's own `-display dbus` already has a shared-map listener interface, but it allocates surfaces with
`qemu_memfd_alloc`, which is Linux-only, so on macOS it falls back to copying through D-Bus.

The object is declared in `qapi/qom.json`, as every user-creatable type must be, and builds wherever
pixman does. The host adds it only for a bundled QEMU that carries this patch
(`QEMUSharedFramebuffer.isSupported`).

### Why the Windows Balloon driver's pages never arrive (2026-11-11)

Reading the guest's memory through QMP (`x-query-virtio-queue-element`, `xp`, `pmemsave`) showed that
virtio-win 0.1.302's ARM64 `balloon.sys` gives the device the wrong guest physical address for its
two DMA buffers. The inflate descriptor pointed at `0x11B4A0000`, which held zeros. The PFN array the
driver had filled was at `0x11B495000`, 512 64-bit PFNs such as `0x23d952`. The statistics buffer
was announced at `0x11B49F000`, which held unrelated kernel data, while its `-1` initial fill sat at
`0x11B494000`. Both are off by the same `0xB000`. The virtqueue rings themselves are read correctly.

Two more defects of 0.1.302 are fixed upstream but not yet in a signed release:

- Its PFNs are 64-bit. The virtio spec and QEMU read 32-bit entries. This is
  virtio-win/kvm-guest-drivers-windows `9f96702d`, 2026-10-07.
- It has no MSI-X support. That matches the statistics queue never being answered after its first
  buffer. This is `d92b9c07`, 2026-10-09.

0.1.302 is still the newest release on fedorapeople.org. QEMU cannot work around the address offset
safely, so ballooning Windows waits for a fixed driver.
