# QEMU patches

Patches Veil applies on top of upstream QEMU. `script/build_patched_qemu.sh` builds
`qemu-system-aarch64` from the release Homebrew ships with every patch here, and
`script/bundle_qemu_runtime.sh` bundles it (with these patches under `Runtime/licenses/qemu-patches/`)
in place of Homebrew's binary. `qemu-img` and the data files stay Homebrew's.

| Patch | Against | Status |
|---|---|---|
| `0001-virtio-balloon-release-discarded-pages-on-darwin.patch` | QEMU 11.1.3 (`qemu-11.1.3.tar.xz`, SHA-256 `5a8289c7…4b22`, the tarball Homebrew pins); also applies cleanly to UTM's `utm-edition` (QEMU 10.0.12) | Built and measured, see below. |

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
