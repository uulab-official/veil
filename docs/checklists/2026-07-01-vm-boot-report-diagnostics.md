# VM Boot Report Diagnostics Checklist

Goal: make real Windows boot spikes debuggable without collecting Windows media or disk contents.

- [x] Add a metadata-only `VMRuntimeBootReport` model.
- [x] Persist the latest Start attempt as pretty-printed JSON.
- [x] Record successful Start attempts with timestamps, resulting state, profile, and planned devices.
- [x] Record failed Start attempts with timestamps, resulting state, profile, planned devices, and error text.
- [x] Include the latest boot report in diagnostics bundles.
- [x] Keep boot reports metadata-only: no installer bytes, no disk bytes, no product keys, no guest data.
- [x] Add host-core tests for success and failure reports.
- [x] Update README, install flow, roadmap, and UTM-level diagnostics checklist.

Next:

- [ ] Add a UI surface for the last boot error after real ISO boot validation.
- [ ] Keep a bounded local boot history once repeated Windows installer testing begins.
