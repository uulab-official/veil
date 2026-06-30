# VM Stop Control Checklist

Goal: make the boot spike operable during real Windows trials by letting the host stop an active VM cleanly from the same runtime boundary.

## Checklist

- [x] Add `VMRuntimeService.stop()` and `VMRuntimeBooting.stop()`.
- [x] Add `VMRuntimeModel.stop()` and `canStop`.
- [x] Add tests for model stop handoff and running-state stop availability.
- [x] Add tests proving the local service calls the boot runner stop path.
- [x] Implement `VZVirtualMachine.stop` bridging in the Virtualization runner.
- [x] Add Stop controls to toolbar, commands, hero, and quick actions.
- [x] Close the VM console window after Stop reports stopped.
- [x] Update README, install flow, MVP, and roadmap docs.
- [x] Run Swift, harness, bundle, entitlement, and diff verification.
- [x] Commit and push to `main`.

## Out of Scope

- Guest-requested graceful shutdown inside Windows.
- Suspend/resume save-state support.
- Snapshot management.
- Automatic recovery from a failed Windows installer boot.
