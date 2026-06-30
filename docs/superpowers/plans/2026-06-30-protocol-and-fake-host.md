# Protocol and Fake Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the documented host/guest protocol into executable JavaScript schemas and add a fake host CLI that verifies the fake Windows agent over WebSocket.

**Architecture:** Keep protocol definitions in `packages/protocol` so the host app, Windows agent, fake agent, and fake host share one contract. Keep the fake host in `harness/fake-host` as a small CLI that exercises the same launch flow the future macOS app will run: health, app list, app launch, window created.

**Tech Stack:** Node.js 24, ESM modules, `node:test`, `ws` WebSocket client/server, JSON fixtures, no TypeScript until a larger package structure needs generated types.

---

## File Structure

- `packages/protocol/package.json`: package metadata and test scripts for protocol validation.
- `packages/protocol/src/messages.mjs`: protocol constants, message builders, and validators.
- `packages/protocol/test/messages.test.mjs`: unit tests that prove fixtures parse and invalid messages fail.
- `harness/fake-agent/package.json`: add dependency on the local protocol package.
- `harness/fake-agent/src/session.mjs`: use protocol constants and error builders instead of handwritten strings.
- `harness/fake-agent/test/session.test.mjs`: keep existing session behavior green after protocol package adoption.
- `harness/fake-host/package.json`: fake host CLI metadata and dependencies.
- `harness/fake-host/src/client.mjs`: WebSocket client helper that sends JSON and waits for replies.
- `harness/fake-host/src/launch-notepad.mjs`: CLI scenario for health, app list, launch, and window event.
- `harness/fake-host/test/client.test.mjs`: unit tests for client timeout and message collection behavior.
- `harness/README.md`: add fake-host run instructions.
- `docs/protocol.md`: note that `packages/protocol` is the executable source for validation.
- `README.md`: add fake agent/fake host smoke test commands.

### Task 1: Protocol Package

**Files:**
- Create: `packages/protocol/package.json`
- Create: `packages/protocol/src/messages.mjs`
- Create: `packages/protocol/test/messages.test.mjs`

- [ ] **Step 1: Write failing protocol tests**

Create `packages/protocol/test/messages.test.mjs`:

```javascript
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

import {
  MessageType,
  createError,
  parseMessage
} from "../src/messages.mjs";

const fixtures = resolve(import.meta.dirname, "../../../harness/protocol-fixtures");

async function readFixture(name) {
  return JSON.parse(await readFile(resolve(fixtures, name), "utf8"));
}

test("parses every stable fixture", async () => {
  const names = [
    "agent.health.request.json",
    "agent.health.response.json",
    "app.list.request.json",
    "app.list.response.json",
    "app.launch.request.json",
    "app.launch.response.json",
    "window.created.json",
    "clipboard.text.set.host.json",
    "error.app_not_found.json"
  ];

  for (const name of names) {
    const parsed = parseMessage(await readFixture(name));
    assert.equal(parsed.ok, true, name);
  }
});

test("rejects messages without a type", () => {
  const parsed = parseMessage({ requestId: "req_missing" });

  assert.deepEqual(parsed, {
    ok: false,
    error: {
      type: "error",
      requestId: "req_missing",
      code: "invalid_message",
      message: "Message type must be a non-empty string"
    }
  });
});

test("rejects unknown message types", () => {
  const parsed = parseMessage({ type: "made.up", requestId: "req_unknown" });

  assert.deepEqual(parsed, {
    ok: false,
    error: {
      type: "error",
      requestId: "req_unknown",
      code: "unknown_message_type",
      message: "Unsupported message type made.up"
    }
  });
});

test("creates structured errors", () => {
  assert.deepEqual(createError("req_1", "app_not_found", "No app exists for id x"), {
    type: MessageType.Error,
    requestId: "req_1",
    code: "app_not_found",
    message: "No app exists for id x"
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd packages/protocol
npm test
```

Expected: FAIL with `Cannot find module ... src/messages.mjs`.

- [ ] **Step 3: Add package metadata**

Create `packages/protocol/package.json`:

```json
{
  "name": "@veil/protocol",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/messages.mjs"
  },
  "scripts": {
    "test": "node --test"
  }
}
```

- [ ] **Step 4: Add minimal protocol implementation**

Create `packages/protocol/src/messages.mjs`:

```javascript
export const MessageType = Object.freeze({
  AgentHealthRequest: "agent.health.request",
  AgentHealthResponse: "agent.health.response",
  AppListRequest: "app.list.request",
  AppListResponse: "app.list.response",
  AppLaunchRequest: "app.launch.request",
  AppLaunchResponse: "app.launch.response",
  WindowCreated: "window.created",
  ClipboardTextSet: "clipboard.text.set",
  InputMouse: "input.mouse",
  InputKey: "input.key",
  Error: "error"
});

const knownTypes = new Set(Object.values(MessageType));

export function parseMessage(message) {
  if (!message || typeof message.type !== "string" || message.type.length === 0) {
    return {
      ok: false,
      error: createError(message?.requestId, "invalid_message", "Message type must be a non-empty string")
    };
  }

  if (!knownTypes.has(message.type)) {
    return {
      ok: false,
      error: createError(message.requestId, "unknown_message_type", `Unsupported message type ${message.type}`)
    };
  }

  return {
    ok: true,
    message
  };
}

export function createError(requestId, code, message) {
  return {
    type: MessageType.Error,
    requestId,
    code,
    message
  };
}
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
cd packages/protocol
npm test
```

Expected: PASS with four protocol tests.

- [ ] **Step 6: Commit protocol package**

Run:

```bash
git add packages/protocol harness/protocol-fixtures
git commit -m "feat: add executable protocol package"
```

Expected: commit succeeds after maintainers decide to commit.

### Task 2: Fake Agent Uses Protocol Package

**Files:**
- Modify: `harness/fake-agent/package.json`
- Modify: `harness/fake-agent/src/session.mjs`
- Modify: `harness/fake-agent/test/session.test.mjs`

- [ ] **Step 1: Add local protocol dependency**

Modify `harness/fake-agent/package.json`:

```json
{
  "name": "@veil/fake-agent",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node src/server.mjs",
    "test": "node --test"
  },
  "dependencies": {
    "@veil/protocol": "file:../../packages/protocol",
    "ws": "^8.18.0"
  }
}
```

- [ ] **Step 2: Run install**

Run:

```bash
cd harness/fake-agent
npm install
```

Expected: `package-lock.json` includes `@veil/protocol`.

- [ ] **Step 3: Update session implementation**

Modify `harness/fake-agent/src/session.mjs`:

```javascript
import { MessageType, createError, parseMessage } from "@veil/protocol";

import { readFixture } from "./fixtures.mjs";

export function createSession() {
  return {
    async handle(message) {
      const parsed = parseMessage(message);
      if (!parsed.ok) {
        return [parsed.error];
      }

      switch (message.type) {
        case MessageType.AgentHealthRequest:
          return [withRequestId(await readFixture("agent.health.response.json"), message.requestId)];
        case MessageType.AppListRequest:
          return [withRequestId(await readFixture("app.list.response.json"), message.requestId)];
        case MessageType.AppLaunchRequest:
          return handleAppLaunch(message);
        default:
          return [createError(message.requestId, "unsupported_in_fake_agent", `Fake agent cannot handle ${message.type}`)];
      }
    }
  };
}

async function handleAppLaunch(message) {
  if (message.appId !== "winapp_notepad") {
    return [createError(message.requestId, "app_not_found", `No app exists for id ${message.appId}`)];
  }

  return [
    withRequestId(await readFixture("app.launch.response.json"), message.requestId),
    await readFixture("window.created.json")
  ];
}

function withRequestId(message, requestId) {
  return {
    ...message,
    requestId
  };
}
```

- [ ] **Step 4: Run fake agent tests**

Run:

```bash
cd harness/fake-agent
npm test
```

Expected: PASS with five session tests.

- [ ] **Step 5: Commit protocol adoption**

Run:

```bash
git add harness/fake-agent packages/protocol
git commit -m "refactor: share protocol helpers with fake agent"
```

Expected: commit succeeds after maintainers decide to commit.

### Task 3: Fake Host Client

**Files:**
- Create: `harness/fake-host/package.json`
- Create: `harness/fake-host/src/client.mjs`
- Create: `harness/fake-host/test/client.test.mjs`

- [ ] **Step 1: Write failing client tests**

Create `harness/fake-host/test/client.test.mjs`:

```javascript
import assert from "node:assert/strict";
import test from "node:test";
import { WebSocketServer } from "ws";

import { collectReplies } from "../src/client.mjs";

test("collects replies until the expected count is reached", async () => {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();

  server.on("connection", (socket) => {
    socket.on("message", () => {
      socket.send(JSON.stringify({ type: "first" }));
      socket.send(JSON.stringify({ type: "second" }));
    });
  });

  const replies = await collectReplies(`ws://127.0.0.1:${address.port}`, { type: "probe" }, {
    expectedCount: 2,
    timeoutMs: 500
  });

  assert.deepEqual(replies.map((reply) => reply.type), ["first", "second"]);
  await new Promise((resolve) => server.close(resolve));
});

test("times out when expected replies do not arrive", async () => {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise((resolve) => server.once("listening", resolve));
  const address = server.address();

  server.on("connection", () => {});

  await assert.rejects(
    collectReplies(`ws://127.0.0.1:${address.port}`, { type: "probe" }, {
      expectedCount: 1,
      timeoutMs: 20
    }),
    /Timed out waiting for 1 reply/
  );

  await new Promise((resolve) => server.close(resolve));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd harness/fake-host
npm test
```

Expected: FAIL with `Cannot find module ... src/client.mjs`.

- [ ] **Step 3: Add fake-host package metadata**

Create `harness/fake-host/package.json`:

```json
{
  "name": "@veil/fake-host",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "launch:notepad": "node src/launch-notepad.mjs",
    "test": "node --test"
  },
  "dependencies": {
    "@veil/protocol": "file:../../packages/protocol",
    "ws": "^8.18.0"
  }
}
```

- [ ] **Step 4: Implement WebSocket reply collection**

Create `harness/fake-host/src/client.mjs`:

```javascript
import WebSocket from "ws";

export function collectReplies(url, message, options = {}) {
  const expectedCount = options.expectedCount ?? 1;
  const timeoutMs = options.timeoutMs ?? 2000;

  return new Promise((resolve, reject) => {
    const replies = [];
    const socket = new WebSocket(url);
    const timer = setTimeout(() => {
      socket.close();
      reject(new Error(`Timed out waiting for ${expectedCount} reply/replies from ${url}`));
    }, timeoutMs);

    socket.on("open", () => {
      socket.send(JSON.stringify(message));
    });

    socket.on("message", (data) => {
      replies.push(JSON.parse(data.toString("utf8")));
      if (replies.length >= expectedCount) {
        clearTimeout(timer);
        socket.close();
        resolve(replies);
      }
    });

    socket.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
cd harness/fake-host
npm install
npm test
```

Expected: PASS with two fake-host client tests.

- [ ] **Step 6: Commit fake-host client**

Run:

```bash
git add harness/fake-host packages/protocol
git commit -m "feat: add fake host websocket client"
```

Expected: commit succeeds after maintainers decide to commit.

### Task 4: Launch Notepad Scenario

**Files:**
- Create: `harness/fake-host/src/launch-notepad.mjs`
- Modify: `harness/README.md`
- Modify: `README.md`

- [ ] **Step 1: Write launch scenario CLI**

Create `harness/fake-host/src/launch-notepad.mjs`:

```javascript
import { MessageType } from "@veil/protocol";

import { collectReplies } from "./client.mjs";

const url = process.env.VEIL_AGENT_URL ?? "ws://127.0.0.1:18444";

const health = await collectReplies(url, {
  type: MessageType.AgentHealthRequest,
  requestId: "req_health",
  protocolVersion: 1
});

const appList = await collectReplies(url, {
  type: MessageType.AppListRequest,
  requestId: "req_apps",
  protocolVersion: 1
});

const launch = await collectReplies(url, {
  type: MessageType.AppLaunchRequest,
  requestId: "req_launch_notepad",
  appId: "winapp_notepad",
  args: []
}, {
  expectedCount: 2
});

console.log(JSON.stringify({
  url,
  health: health[0],
  apps: appList[0].apps,
  launch: launch[0],
  window: launch[1]
}, null, 2));
```

- [ ] **Step 2: Run fake agent**

Run:

```bash
cd harness/fake-agent
npm start
```

Expected: prints `Veil fake agent listening on ws://127.0.0.1:18444`.

- [ ] **Step 3: Run launch scenario**

In a second shell, run:

```bash
cd harness/fake-host
npm run launch:notepad
```

Expected: JSON output includes `agent.health.response`, one `winapp_notepad`, `app.launch.response`, and `window.created`.

- [ ] **Step 4: Document smoke test**

Update `harness/README.md` with:

```markdown
## Fake Host Smoke Test

Terminal 1:

```bash
cd harness/fake-agent
npm start
```

Terminal 2:

```bash
cd harness/fake-host
npm install
npm run launch:notepad
```

Expected: JSON output includes `window.created` for `hwnd:0003029A`.
```

- [ ] **Step 5: Add README quick check**

Update `README.md` with a short "Local harness smoke test" section that links to `harness/README.md`.

- [ ] **Step 6: Commit launch scenario**

Run:

```bash
git add README.md harness
git commit -m "feat: add fake host launch scenario"
```

Expected: commit succeeds after maintainers decide to commit.

### Task 5: Final Verification

**Files:**
- Inspect: `packages/protocol`
- Inspect: `harness/fake-agent`
- Inspect: `harness/fake-host`
- Inspect: `README.md`
- Inspect: `harness/README.md`

- [ ] **Step 1: Run protocol tests**

Run:

```bash
cd packages/protocol
npm test
```

Expected: PASS with four protocol tests.

- [ ] **Step 2: Run fake-agent tests**

Run:

```bash
cd harness/fake-agent
npm test
```

Expected: PASS with five session tests.

- [ ] **Step 3: Run fake-host tests**

Run:

```bash
cd harness/fake-host
npm test
```

Expected: PASS with two client tests.

- [ ] **Step 4: Validate fixtures**

Run:

```bash
for f in harness/protocol-fixtures/*.json; do jq empty "$f" || exit 1; done
```

Expected: command exits with status 0.

- [ ] **Step 5: Search for placeholder language**

Run:

```bash
rg -n "TBD|TODO|fill[[:space:]]+in|implement[[:space:]]+later" README.md CONTRIBUTING.md AGENTS.md CLAUDE.md docs harness packages --glob '!docs/superpowers/plans/**' --glob '!**/node_modules/**'
```

Expected: no matches.

- [ ] **Step 6: Review git status**

Run:

```bash
git status --short
```

Expected: only intentional new and modified files are present.
