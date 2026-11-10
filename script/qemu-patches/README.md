# QEMU patches

Patches Veil needs on top of upstream QEMU. The bundled runtime still comes from Homebrew's
`qemu` formula (`script/bundle_qemu_runtime.sh`), so none of these ship yet. A Veil that bundles a
patched QEMU must ship these patches next to the binary's source pointers (GPL-2.0).

| Patch | Against | Status |
|---|---|---|
| `0001-virtio-balloon-release-discarded-pages-on-darwin.patch` | QEMU 11.1.3 (`qemu-11.1.3.tar.xz`, SHA-256 `5a8289c7…4b22`, the tarball Homebrew pins) | Applies with `patch -p1`. Not built yet: building QEMU from source was blocked by this machine's agent permission policy. |

## 0001: the memory balloon gives memory back to macOS

On Darwin `MADV_DONTNEED` does not free a page: the page stays resident, keeps its contents, and still
counts in the process footprint. A 1 GiB anonymous mapping, touched and then advised, kept its
1026 MB footprint; `MADV_FREE_REUSABLE` on half of it dropped the footprint to 514 MB. QEMU discards
balloon pages through `ram_block_discard_range()`, which uses `MADV_DONTNEED`, so an inflated
balloon returned nothing to macOS. The patch adds `MADV_FREE_REUSABLE` after the discard on the
balloon paths only, and `MADV_FREE_REUSE` before a deflated page is reused. Other discard users
(migration, virtio-mem) are left alone because they may rely on discarded pages reading back as zero.

The host side is `QEMUMemoryBalloon` in `apps/mac-host/Sources/VeilHostCore`.
