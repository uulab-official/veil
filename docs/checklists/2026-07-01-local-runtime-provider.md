# Local Runtime Provider Checklist

Goal: make Veil's UTM-style, serverless local VM architecture explicit in code and docs.

- [x] Add a typed local runtime provider summary to `VMRuntimeSnapshot`.
- [x] Mark Apple Virtualization as the active local provider.
- [x] Mark provider summaries as not server-backed.
- [x] Update capability wording to say local provider.
- [x] Replace product-facing backend wording with local runtime provider wording.
- [x] Document QEMU/HVF as a possible local provider, not a server backend.
- [x] Keep the project scope narrower than UTM: Windows App Runtime, not generic VM management.

Next:

- [ ] Add a QEMU/HVF provider probe without bundling QEMU binaries yet.
- [ ] Add provider selection rules once real Windows installer testing proves the better path.
