import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, readFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import test from "node:test";

import { createFakeAgentServer } from "../../fake-agent/src/fake-agent-server.mjs";
import { runNotepadInputSmoke } from "../src/notepad-input-smoke.mjs";

test("launches Notepad, receives a frame, and sends click plus keyboard input", async (t) => {
  const inputs = [];
  const server = createFakeAgentServer({
    host: "127.0.0.1",
    port: 0,
    onInput: async (message) => {
      inputs.push(message);
    }
  });
  t.after(() => {
    server.close();
  });
  await once(server, "listening");
  const address = server.address();
  const url = `ws://${address.address}:${address.port}`;

  const report = await runNotepadInputSmoke({
    url,
    text: "veil",
    click: { x: 240, y: 130 }
  });

  assert.equal(report.acceptance.windowId, "hwnd:0003029A");
  assert.equal(report.frame.type, "window.frame");
  assert.equal(report.postInputFrame.type, "window.frame");
  assert.ok(report.postInputFrame.sequence > report.frame.sequence);
  assert.deepEqual(inputs.map((input) => input.type), [
    "input.mouse",
    "input.mouse",
    "input.key",
    "input.key",
    "input.key",
    "input.key",
    "input.key",
    "input.key",
    "input.key",
    "input.key"
  ]);
  assert.deepEqual(inputs.filter((input) => input.type === "input.key").map((input) => input.key), [
    "v",
    "v",
    "e",
    "e",
    "i",
    "i",
    "l",
    "l"
  ]);
});

test("writes initial and post-input frame PNG evidence when an output directory is provided", async (t) => {
  const outputDir = await mkdtemp(join(tmpdir(), "veil-notepad-smoke-"));
  const server = createFakeAgentServer({ host: "127.0.0.1", port: 0 });
  t.after(() => {
    server.close();
  });
  await once(server, "listening");
  const address = server.address();
  const url = `ws://${address.address}:${address.port}`;

  const report = await runNotepadInputSmoke({
    url,
    outputDir
  });

  assert.equal(report.evidence.initialFramePath, join(outputDir, "notepad-initial-frame.png"));
  assert.equal(report.evidence.postInputFramePath, join(outputDir, "notepad-post-input-frame.png"));
  assert.deepEqual(
    await readFile(report.evidence.initialFramePath),
    Buffer.from(report.frame.encodedData, "base64")
  );
  assert.deepEqual(
    await readFile(report.evidence.postInputFramePath),
    Buffer.from(report.postInputFrame.encodedData, "base64")
  );
});
