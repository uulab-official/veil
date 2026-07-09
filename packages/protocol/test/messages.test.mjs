import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import test from "node:test";

import {
  MessageType,
  createError,
  parseMessage,
  validateAgentHealthResponse,
  validateAppLaunchAcceptance,
  validateClipboardTextSet,
  validateFileOpenRequest,
  validateFileOpenResponse,
  validateInputKey,
  validateInputMouse,
  validateWindowClosed,
  validateWindowCloseRequest,
  validateWindowCloseResponse,
  validateWindowFrame,
  validateWindowFrameSubscribeRequest,
  validateWindowFrameUnsubscribeRequest,
  validateWindowFocusRequest,
  validateWindowFocusResponse,
  validateWindowUpdated
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
    "file.open.request.json",
    "file.open.response.json",
    "window.created.json",
    "window.updated.json",
    "window.closed.json",
    "window.frame.json",
    "window.frame.subscribe.json",
    "window.frame.unsubscribe.json",
    "window.focus.request.json",
    "window.focus.response.json",
    "window.close.request.json",
    "window.close.response.json",
    "input.mouse.left-down.json",
    "input.key.copy.json",
    "clipboard.text.set.host.json",
    "clipboard.text.set.guest.json",
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

test("validates agent health capability readiness", async () => {
  const health = validateAgentHealthResponse(await readFixture("agent.health.response.json"));

  assert.equal(health.capabilities.windowCapture, true);
  assert.equal(health.capabilities.packageIdentity, false);
  assert.equal(health.packageIdentityStatus.stage, "packageSigned");
  assert.equal(health.packageIdentityStatus.succeeded, false);
  assert.match(health.packageIdentityStatus.statusPath, /sparse-package-status\.json/);
});

test("rejects malformed package identity status", async () => {
  const health = await readFixture("agent.health.response.json");
  health.packageIdentityStatus.succeeded = "false";

  assert.throws(
    () => validateAgentHealthResponse(health),
    /packageIdentityStatus\.succeeded/
  );
});

test("rejects agent health without package identity readiness", async () => {
  const health = await readFixture("agent.health.response.json");
  delete health.capabilities.packageIdentity;

  assert.throws(
    () => validateAgentHealthResponse(health),
    /capabilities\.packageIdentity/
  );
});

test("validates an app launch acceptance pair", async () => {
  const launch = await readFixture("app.launch.response.json");
  const window = await readFixture("window.created.json");

  assert.deepEqual(validateAppLaunchAcceptance(launch, window), {
    appId: "winapp_notepad",
    processId: 4912,
    windowId: "hwnd:0003029A",
    title: "Untitled - Notepad"
  });
});

test("validates launch acceptance for non-Notepad windows", async () => {
  const launch = {
    ...(await readFixture("app.launch.response.json")),
    processId: 4930
  };
  const window = {
    ...(await readFixture("window.created.json")),
    windowId: "hwnd:0004029B",
    processId: 4930,
    appId: "winapp_calculator",
    title: "Calculator"
  };

  assert.deepEqual(validateAppLaunchAcceptance(launch, window), {
    appId: "winapp_calculator",
    processId: 4930,
    windowId: "hwnd:0004029B",
    title: "Calculator"
  });
});

test("rejects launch acceptance when the HWND event belongs to another process", async () => {
  const launch = await readFixture("app.launch.response.json");
  const window = {
    ...(await readFixture("window.created.json")),
    processId: 9001
  };

  assert.throws(
    () => validateAppLaunchAcceptance(launch, window),
    /Window created event must match launch process/
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

test("validates one window closed fixture", async () => {
  const closed = validateWindowClosed(await readFixture("window.closed.json"));

  assert.equal(closed.type, MessageType.WindowClosed);
  assert.equal(closed.windowId, "hwnd:0003029A");
});

test("validates one window updated fixture", async () => {
  const updated = validateWindowUpdated(await readFixture("window.updated.json"));

  assert.equal(updated.type, MessageType.WindowUpdated);
  assert.equal(updated.windowId, "hwnd:0003029A");
  assert.equal(updated.title, "Notes.txt - Notepad");
  assert.equal(updated.bounds.width, 1360);
});

test("validates window frame stream subscribe and unsubscribe fixtures", async () => {
  const subscribe = validateWindowFrameSubscribeRequest(await readFixture("window.frame.subscribe.json"));
  const unsubscribe = validateWindowFrameUnsubscribeRequest(await readFixture("window.frame.unsubscribe.json"));

  assert.equal(subscribe.type, MessageType.WindowFrameSubscribe);
  assert.equal(subscribe.requestId, "req_frame_subscribe_notepad");
  assert.equal(subscribe.windowId, "hwnd:0003029A");
  assert.equal(subscribe.format, "png");
  assert.equal(unsubscribe.type, MessageType.WindowFrameUnsubscribe);
  assert.equal(unsubscribe.requestId, "req_frame_unsubscribe_notepad");
  assert.equal(unsubscribe.windowId, "hwnd:0003029A");
});

test("validates window focus request and response fixtures", async () => {
  const request = validateWindowFocusRequest(await readFixture("window.focus.request.json"));
  const response = validateWindowFocusResponse(await readFixture("window.focus.response.json"));

  assert.equal(request.type, MessageType.WindowFocusRequest);
  assert.equal(request.requestId, "req_focus_notepad");
  assert.equal(request.windowId, "hwnd:0003029A");
  assert.equal(response.type, MessageType.WindowFocusResponse);
  assert.equal(response.requestId, request.requestId);
  assert.equal(response.windowId, request.windowId);
  assert.equal(response.accepted, true);
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

test("validates guest clipboard text fixture", async () => {
  const clipboard = validateClipboardTextSet(await readFixture("clipboard.text.set.guest.json"));

  assert.equal(clipboard.type, MessageType.ClipboardTextSet);
  assert.equal(clipboard.requestId, "evt_clipboard_43");
  assert.equal(clipboard.origin, "guest");
  assert.equal(clipboard.sequence, 43);
  assert.equal(clipboard.text, "hello from Windows");
});

test("validates file open request and response fixtures", async () => {
  const request = validateFileOpenRequest(await readFixture("file.open.request.json"));
  assert.equal(request.appId, "winapp_notepad");
  assert.equal(request.fileName, "hello.txt");
  assert.equal(request.contentBase64, "SGVsbG8gZnJvbSBtYWNPUw==");

  const response = validateFileOpenResponse(await readFixture("file.open.response.json"));
  assert.equal(response.accepted, true);
  assert.equal(response.processId, 4931);
});

test("rejects a file open request whose fileName carries a path", () => {
  assert.throws(() => validateFileOpenRequest({
    type: MessageType.FileOpenRequest,
    requestId: "req_bad",
    appId: "winapp_notepad",
    fileName: "../../Windows/System32/evil.exe",
    contentBase64: "AA=="
  }), TypeError);
});

test("rejects a file open request whose fileName is a reserved Windows device name", () => {
  for (const fileName of ["CON", "con.txt", "NUL", "COM1.log", "LPT1"]) {
    assert.throws(() => validateFileOpenRequest({
      type: MessageType.FileOpenRequest,
      requestId: "req_bad",
      appId: "winapp_notepad",
      fileName,
      contentBase64: "AA=="
    }), TypeError, fileName);
  }
});

test("rejects a file open request whose fileName is whitespace only", () => {
  assert.throws(() => validateFileOpenRequest({
    type: MessageType.FileOpenRequest,
    requestId: "req_bad",
    appId: "winapp_notepad",
    fileName: "   ",
    contentBase64: "AA=="
  }), TypeError);
});

test("rejects a file open response missing processId when accepted", () => {
  assert.throws(() => validateFileOpenResponse({
    type: MessageType.FileOpenResponse,
    requestId: "req_bad",
    accepted: true
  }), TypeError);
});
