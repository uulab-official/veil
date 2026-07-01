# Auto Install Simulation Checklist

Goal: make the prepared Windows VM path feel like a Parallels-style automatic install flow without claiming real unattended Windows installation is implemented.

## Completed

- [x] Added an in-app automatic install simulation state machine.
- [x] Changed the ready-state primary action to `Simulate Auto Install`.
- [x] Added staged progress for ISO check, unattended setup planning, installer boot, file copy, configuration, restart, guest tools, and readiness.
- [x] Disabled refresh while the simulation is running to keep the card state stable.
- [x] Added a reset affordance after the simulation completes.
- [x] Kept the simulation separate from real VM start and Windows licensing/distribution claims.

## Still Open

- [ ] Replace the timer-driven simulation with real VM boot events once the installer console path is stable.
- [ ] Add an explicit unattended-install plan document before generating any `autounattend.xml`.
- [ ] Add a harness fixture for simulated install events if the state machine moves into `VeilHostCore`.
- [ ] Keep user-provided Windows media and license boundaries visible in release notes.

## Notes

- This is a UX and harness spike. It does not install Windows, activate Windows, generate a product key, or distribute Windows media.
- The future real implementation should translate VM boot reports and guest-agent readiness into the same visible phases.
