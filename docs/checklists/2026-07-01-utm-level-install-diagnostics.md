# UTM-Level Install Diagnostics Checklist

- [x] Compare Veil's quality bar against UTM as an open-source VM host benchmark.
- [x] Keep Veil's scope narrower than UTM: Windows App Runtime, not generic QEMU VM management.
- [x] Add installer media role validation before Start can become enabled.
- [x] Treat ISO files as installer media candidates.
- [x] Warn when VHD/VHDX files are selected as installer media.
- [x] Keep validation conservative and avoid claiming full Windows ISO bootability proof.
- [x] Update architecture, install flow, roadmap, and README documentation.
- [ ] Validate real Windows 11 Arm ISO boot behavior on Apple Virtualization.framework.
- [x] Add diagnostics bundle export for failed boots and user bug reports.
- [x] Persist the latest Start attempt result, resulting VM state, planned devices, and startup error text.
- [ ] Add import flow for pre-existing Windows disk images only after file-format support is proven.
