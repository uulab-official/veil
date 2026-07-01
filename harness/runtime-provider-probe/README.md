# Runtime Provider Probe Harness

This harness validates the JSON shape emitted by the local VM runtime provider probe.

Veil has no cloud or server VM backend. The expected providers are local Mac runtime options:

- `appleVirtualization`: the active Apple Virtualization feasibility provider.
- `qemuHypervisor`: the planned or detected UTM-style QEMU/HVF compatibility provider.

Run the fixture tests:

```bash
cd harness/runtime-provider-probe
npm test
```

Validate live CLI output:

```bash
cd apps/mac-host
swift run veil-vmctl providers --json | node ../../harness/runtime-provider-probe/src/validate-provider-output.mjs
```
