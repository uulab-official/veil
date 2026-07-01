# Auto Installer Assistant Checklist

Goal: move Veil toward the Parallels-style install assistant flow while keeping Windows media and license boundaries user-owned.

- [x] Confirm Parallels-style expectation: Windows can be downloaded/installed through an assistant, but licensing remains user-provided.
- [x] Auto-detect Windows Arm ISO files from `~/Downloads` during `Prepare VM`.
- [x] Preserve manually configured installer media instead of overwriting it.
- [x] Keep detection conservative: Windows/Win naming plus Arm/AArch64 naming plus `.iso`.
- [x] Update VM Runtime UI copy to describe Auto Prepare.
- [x] Update the roadmap with download-folder ISO detection.
- [x] Add regression tests for ISO auto-detection and manual path preservation.

Verification:

```sh
swift build --product veil-host-shell
swift test
git diff --check
```
