# Open Source Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap Veil as an open-source Windows App Runtime for macOS with clear documentation, agent instructions, a harness strategy, and a staged roadmap.

**Architecture:** Start documentation-first because the project has high platform, legal, and host/guest boundary risk. Separate source ownership into macOS host, Windows guest agent, protocol package, and harness so future code can land in small testable slices.

**Tech Stack:** Markdown docs, Apache-2.0 licensing, Swift/SwiftUI/AppKit/Metal for future host work, C#/.NET 8 for the first Windows agent, WebSocket JSON for the MVP protocol.

---

### Task 1: Repository Identity and Open Source Metadata

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `CONTRIBUTING.md`
- Create: `CODE_OF_CONDUCT.md`
- Create: `SECURITY.md`
- Create: `.gitignore`
- Create: `.editorconfig`

- [ ] **Step 1: Create the README**

Write `README.md` with project definition, status, architecture sketch, repository map, open-source principles, and read-next links.

- [ ] **Step 2: Add Apache-2.0 license**

Write the standard Apache License 2.0 text to `LICENSE`.

- [ ] **Step 3: Add contributor docs**

Write `CONTRIBUTING.md` with contribution flow, commit style, definition of done, and AI-assisted work links.

- [ ] **Step 4: Add conduct and security docs**

Write `CODE_OF_CONDUCT.md` and `SECURITY.md` with pre-alpha security boundaries.

- [ ] **Step 5: Add local ignore and editor rules**

Write `.gitignore` for macOS, Xcode, .NET, logs, local state, and VM artifacts. Write `.editorconfig` with UTF-8, LF endings, final newline, and trailing-whitespace trimming.

- [ ] **Step 6: Verify files exist**

Run:

```bash
test -f README.md && test -f LICENSE && test -f CONTRIBUTING.md && test -f SECURITY.md
```

Expected: command exits with status 0.

### Task 2: Product and Architecture Documentation

**Files:**
- Create: `docs/project-brief.md`
- Create: `docs/architecture.md`
- Create: `docs/mvp.md`
- Create: `docs/protocol.md`
- Create: `docs/roadmap.md`
- Create: `docs/legal-support-notes.md`

- [ ] **Step 1: Write project brief**

Write `docs/project-brief.md` around the core promise: Windows apps as macOS windows, not a generic VM manager.

- [ ] **Step 2: Write architecture document**

Write `docs/architecture.md` with macOS host, Windows guest agent, protocol package, window bridge, capture strategy, security boundaries, and feasibility questions.

- [ ] **Step 3: Write MVP acceptance criteria**

Write `docs/mvp.md` with v0.1 through v0.5 milestones and explicit exit criteria.

- [ ] **Step 4: Write protocol draft**

Write `docs/protocol.md` with WebSocket JSON envelope, health, app list, app launch, window created, input, clipboard, and error messages.

- [ ] **Step 5: Write roadmap**

Write `docs/roadmap.md` from v0.1 to v3.0, with the next engineering step focused on fake agent, schemas, and VM feasibility.

- [ ] **Step 6: Write legal/support notes**

Write `docs/legal-support-notes.md` with official Apple and Microsoft links and wording constraints.

- [ ] **Step 7: Verify doc links**

Run:

```bash
rg -n "docs/(project-brief|architecture|mvp|protocol|roadmap|legal-support-notes)" README.md
```

Expected: all linked docs are referenced in `README.md`.

### Task 3: Agent and Harness Documentation

**Files:**
- Create: `AGENTS.md`
- Create: `CLAUDE.md`
- Create: `docs/ai/codex.md`
- Create: `docs/ai/claude.md`
- Create: `docs/harness/README.md`

- [ ] **Step 1: Write shared agent guide**

Write `AGENTS.md` with mission, non-negotiables, documentation sources of truth, expected workflow, and component boundaries.

- [ ] **Step 2: Write Claude guide**

Write `CLAUDE.md` with Claude-specific style, first files to read, implementation bias, and review bias.

- [ ] **Step 3: Write Codex guide**

Write `docs/ai/codex.md` with Codex editing workflow, verification expectations, and final response shape.

- [ ] **Step 4: Mirror Claude guide under docs**

Write `docs/ai/claude.md` so contributor-facing AI docs are grouped together.

- [ ] **Step 5: Write harness strategy**

Write `docs/harness/README.md` with fake agent, fake host, protocol fixture, and scenario plan.

- [ ] **Step 6: Verify agent links**

Run:

```bash
rg -n "AGENTS.md|CLAUDE.md|docs/ai/codex.md|docs/harness/README.md" CONTRIBUTING.md
```

Expected: contributor guide links to the agent and harness docs.

### Task 4: Executable Fake Agent Harness

**Files:**
- Create: `harness/README.md`
- Create: `harness/protocol-fixtures/*.json`
- Create: `harness/protocol-fixtures/README.md`
- Create: `harness/fake-agent/package.json`
- Create: `harness/fake-agent/package-lock.json`
- Create: `harness/fake-agent/src/fixtures.mjs`
- Create: `harness/fake-agent/src/session.mjs`
- Create: `harness/fake-agent/src/server.mjs`
- Create: `harness/fake-agent/test/session.test.mjs`

- [ ] **Step 1: Write the failing fake-agent session tests**

Create `harness/fake-agent/test/session.test.mjs` with tests for health response, app list response, Notepad launch, unknown app error, and unknown message error.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd harness/fake-agent
npm test
```

Expected: FAIL because `src/session.mjs` does not exist yet.

- [ ] **Step 3: Add fixture-backed session implementation**

Create `src/fixtures.mjs` to read JSON from `harness/protocol-fixtures`. Create `src/session.mjs` with `createSession().handle(message)` that returns fixture-backed responses and structured errors.

- [ ] **Step 4: Add WebSocket server**

Create `src/server.mjs` using the `ws` package. The server listens on `127.0.0.1:18444` by default, parses JSON messages, calls the session handler, and sends every reply as JSON.

- [ ] **Step 5: Install dependencies and run tests**

Run:

```bash
cd harness/fake-agent
npm install
npm test
```

Expected: PASS with five session tests and zero vulnerabilities from npm audit.

- [ ] **Step 6: Verify WebSocket health round trip**

Run:

```bash
cd harness/fake-agent
npm start
```

In another shell, run:

```bash
node -e 'const timer = setTimeout(() => { console.error("timed out"); process.exit(1); }, 3000); const ws = new WebSocket("ws://127.0.0.1:18444"); ws.onopen = () => ws.send(JSON.stringify({type:"agent.health.request", requestId:"req_probe", protocolVersion:1})); ws.onmessage = (event) => { clearTimeout(timer); console.log(event.data); ws.close(); process.exit(0); }; ws.onerror = (error) => { clearTimeout(timer); console.error(error.message); process.exit(1); };'
```

Expected: JSON response with `"type":"agent.health.response"` and `"requestId":"req_probe"`.

### Task 5: Bootstrap Review

**Files:**
- Inspect: all created Markdown files

- [ ] **Step 1: List repository files**

Run:

```bash
find . -maxdepth 3 -type f | sort
```

Expected: created docs and metadata files are listed.

- [ ] **Step 2: Search for placeholder language**

Run:

```bash
rg -n "TBD|TODO|fill[[:space:]]+in|implement[[:space:]]+later" README.md CONTRIBUTING.md AGENTS.md CLAUDE.md docs harness --glob '!docs/superpowers/plans/**'
```

Expected: no matches in committed documentation.

- [ ] **Step 3: Review git status**

Run:

```bash
git status --short
```

Expected: new files are untracked and ready for review or staging.
