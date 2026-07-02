import assert from "node:assert/strict";
import { once } from "node:events";
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
