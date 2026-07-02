import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

import {
  MessageType,
  createError,
  parseMessage,
  validateClipboardTextSet,
  validateInputKey,
  validateNotepadAcceptance,
  validateInputMouse,
  validateWindowCloseRequest,
  validateWindowCloseResponse,
  validateWindowFrame
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
    "window.frame.json",
    "window.close.request.json",
    "window.close.response.json",
    "input.mouse.left-down.json",
    "input.key.copy.json",
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

test("validates one captured window frame fixture", async () => {
  const frame = validateWindowFrame(await readFixture("window.frame.json"));

  assert.equal(frame.type, MessageType.WindowFrame);
  assert.equal(frame.windowId, "hwnd:0003029A");
  assert.equal(frame.frameId, "frame_000001");
  assert.equal(frame.format, "png");
  assert.equal(frame.width, 1);
  assert.equal(frame.height, 1);
});

test("validates window close request and response fixtures", async () => {
  const request = validateWindowCloseRequest(await readFixture("window.close.request.json"));
  const response = validateWindowCloseResponse(await readFixture("window.close.response.json"));

  assert.equal(request.type, MessageType.WindowCloseRequest);
  assert.equal(request.requestId, "req_close_notepad");
  assert.equal(request.windowId, "hwnd:0003029A");
  assert.equal(response.type, MessageType.WindowCloseResponse);
  assert.equal(response.requestId, request.requestId);
  assert.equal(response.windowId, request.windowId);
  assert.equal(response.accepted, true);
});

test("validates one host mouse input fixture", async () => {
  const input = validateInputMouse(await readFixture("input.mouse.left-down.json"));

  assert.equal(input.type, MessageType.InputMouse);
  assert.equal(input.windowId, "hwnd:0003029A");
  assert.equal(input.event, "leftDown");
  assert.equal(input.x, 240);
  assert.equal(input.y, 130);
  assert.deepEqual(input.modifiers, []);
});

test("validates one host key input fixture", async () => {
  const input = validateInputKey(await readFixture("input.key.copy.json"));

  assert.equal(input.type, MessageType.InputKey);
  assert.equal(input.windowId, "hwnd:0003029A");
  assert.equal(input.event, "keyDown");
  assert.equal(input.key, "c");
  assert.equal(input.windowsVirtualKey, 67);
  assert.deepEqual(input.modifiers, ["ctrl"]);
});

test("validates host clipboard text fixture", async () => {
  const clipboard = validateClipboardTextSet(await readFixture("clipboard.text.set.host.json"));

  assert.equal(clipboard.type, MessageType.ClipboardTextSet);
  assert.equal(clipboard.requestId, "req_004");
  assert.equal(clipboard.origin, "host");
  assert.equal(clipboard.sequence, 42);
  assert.equal(clipboard.text, "hello from macOS");
});
