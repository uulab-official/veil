# VM Diagnostics Bundle Checklist

- [x] Add `VMRuntimeDiagnosticBundle` with host metadata, runtime snapshot, setup checks, and profile metadata.
- [x] Add `LocalVMRuntimeService.exportDiagnostics(to:)`.
- [x] Write diagnostics as pretty-printed sorted JSON with ISO-8601 dates.
- [x] Keep diagnostics metadata-only: no installer bytes, no disk bytes, no product keys, no guest data.
- [x] Add model state for the last exported diagnostics URL.
- [x] Add a VM Runtime quick action for diagnostics export.
- [x] Save shell-triggered diagnostics to `~/Library/Application Support/Veil/Diagnostics` to avoid routine Downloads-folder permission prompts.
- [x] Update README, install flow, roadmap, and UTM-level checklist.
- [ ] Include Virtualization.framework boot error payloads after real Windows boot failures are captured.
- [ ] Add a one-click issue report template after the project has public issue triage rules.
