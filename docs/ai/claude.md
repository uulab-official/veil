# Claude Guide

This guide mirrors `CLAUDE.md` but lives under `docs/ai` so contributors can find all agent documentation in one place.

## First Context Pass

Read:

1. `AGENTS.md`
2. `docs/project-brief.md`
3. `docs/architecture.md`
4. `docs/protocol.md`
5. `docs/harness/README.md`

## Decision Rules

- If a decision affects legal/support wording, update `docs/legal-support-notes.md`.
- If a decision affects message shape, update `docs/protocol.md`.
- If a decision affects testing strategy, update `docs/harness/README.md`.
- If a decision affects milestone order, update `docs/roadmap.md`.

## Preferred First Implementation Path

1. Fake guest-agent harness.
2. Protocol schema package.
3. macOS host connection to fake agent.
4. Real Windows agent health endpoint.
5. VM boot spike.

This lets contributors build and test host UI/protocol work before every developer has a working Windows VM.
