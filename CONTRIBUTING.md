# Contributing to Veil

Thanks for helping build Veil.

Veil is early-stage systems software. Small, well-documented changes are more valuable than large opaque rewrites.

## Development Priorities

VM boot and guest-agent connection are proven — see [MVP](docs/mvp.md) for the dated evidence. What is
scarce now is verification, not features.

1. Verify what already exists before adding to it. A feature with unit tests and a harness contract but no
   run against real Windows is not finished.
2. Keep the host/guest protocol explicit and testable, in both directions. The host must not trust guest
   values: the guest runs Windows, which the user may have infected.
3. Prefer boring, observable implementation over clever shortcuts.
4. Add harness fixtures before optimizing runtime paths.
5. Write limitations down where the user will meet them, not only in docs. A refusal the product cannot
   explain is a bug even when the refusal is correct.

## Verifying a Change

Run the complete regression gate before calling a cross-component change done:

```bash
./script/test_all.sh
```

It installs locked Node dependencies, then verifies the Swift host, Windows agent, protocol and harness
packages, the signed macOS app launch contract, and an isolated install, guarded replacement, uninstall,
user-data preservation, and reinstall cycle. All required tools are checked before any test starts,
so a missing SDK cannot leave a misleading partial-success log. Use `./script/test_all.sh --list` to inspect
the exact scope. Skip flags are only for an explicitly documented platform limitation and do not count as
full release evidence.

For focused iteration, run the targets your change touches in this order — the Swift build first because
everything else is independent of it:

```bash
# macOS host: library, app shell, and CLI
cd apps/mac-host && swift build && swift test

# Windows guest agent (needs the .NET 8 SDK; not present on every dev Mac)
cd apps/windows-agent && dotnet test

# Shared protocol helpers
cd packages/protocol && npm test

# Harness validators — run the ones whose contract your change affects
cd harness/app-runtime-status && npm test
cd harness/app-runtime-action && npm test
cd harness/shared-folder && npm test
cd harness/device-passthrough && npm test
cd harness/qemu-boot-plan && npm test
cd harness/vm-session && npm test
cd harness/vm-snapshots && npm test
cd harness/frame-pipeline-report && npm test
cd harness/mvp-proof && npm test
```

Each harness directory is a standalone npm package with its own `npm test`; see
[harness/README.md](harness/README.md) for the full list and what each one validates.

If a change alters any JSON a `veil-vmctl` command emits, the matching harness validator has to change
with it, and its fixtures usually do too. That coupling is deliberate: it is what stops a report shape from
drifting silently.

Anything that needs a running Windows VM cannot be verified by the harness, and saying so in the PR is
expected rather than a weakness. `docs/checklists/` records that distinction per slice.

## Contribution Flow

1. Open an issue for design-impacting changes.
2. Keep PRs focused on one component or one protocol slice.
3. Include test or harness evidence where possible.
4. Update docs when behavior, protocol messages, or setup steps change.
5. Do not include Windows images, product keys, private SDKs, or proprietary assets.

## Commit Style

Use concise Conventional Commit style:

```text
feat: add guest app list message schema
fix: correct host window bounds scaling
docs: document Windows licensing constraints
test: add protocol fixture for window.created
```

## Definition of Done

A change is done when:

- The behavior is documented.
- The protocol impact is documented or explicitly absent.
- The verification commands that were actually run are listed in the PR, and so is anything that could
  **not** be verified without a running Windows VM. "Untested against real Windows" is an acceptable state
  to land in; claiming otherwise is not.
- Known limitations are written down instead of hidden, and surfaced to the user where they will meet them.

## AI-Assisted Work

Codex, Claude, and other agents should follow:

- [AGENTS.md](AGENTS.md)
- [CLAUDE.md](CLAUDE.md)
- [Codex guide](docs/ai/codex.md)
- [Claude guide](docs/ai/claude.md)
- [Harness guide](docs/harness/README.md)
