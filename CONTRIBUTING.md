# Contributing to Veil

Thanks for helping build Veil.

Veil is early-stage systems software. Small, well-documented changes are more valuable than large opaque rewrites.

## Development Priorities

1. Prove the VM and guest-agent feasibility.
2. Keep the host/guest protocol explicit and testable.
3. Prefer boring, observable implementation over clever shortcuts.
4. Add harness fixtures before optimizing runtime paths.
5. Document known platform, licensing, and support limits.

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
- The local verification command is listed in the PR.
- Known limitations are written down instead of hidden.

## AI-Assisted Work

Codex, Claude, and other agents should follow:

- [AGENTS.md](AGENTS.md)
- [CLAUDE.md](CLAUDE.md)
- [Codex guide](docs/ai/codex.md)
- [Claude guide](docs/ai/claude.md)
- [Harness guide](docs/harness/README.md)
