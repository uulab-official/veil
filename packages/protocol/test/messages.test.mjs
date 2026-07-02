import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

import {
  MessageType,
  createError,
  parseMessage,
  validateNotepadAcceptance
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

test("validates the Notepad launch acceptance pair", async () => {
  const launch = await readFixture("app.launch.response.json");
  const window = await readFixture("window.created.json");

  assert.deepEqual(validateNotepadAcceptance(launch, window), {
    appId: "winapp_notepad",
    processId: 4912,
    windowId: "hwnd:0003029A",
    title: "Untitled - Notepad"
  });
});

test("rejects Notepad acceptance when the HWND event belongs to another process", async () => {
  const launch = await readFixture("app.launch.response.json");
  const window = {
    ...(await readFixture("window.created.json")),
    processId: 9001
  };

  assert.throws(
    () => validateNotepadAcceptance(launch, window),
    /Notepad window event must match launch process/
  );
});
