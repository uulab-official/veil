import assert from "node:assert/strict";
import test from "node:test";
import { validateAppLaunchAcceptance, validateWindowCloseResponse } from "@veil/protocol";

import { createSession } from "../src/session.mjs";

test("responds to agent health requests with fixture capability data", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "agent.health.request",
    requestId: "req_001",
    protocolVersion: 1
  });

  assert.equal(replies.length, 1);
  assert.equal(replies[0].type, "agent.health.response");
  assert.equal(replies[0].requestId, "req_001");
  assert.equal(replies[0].capabilities.appLaunch, true);
  assert.equal(replies[0].capabilities.windowCapture, true);
});

test("launches Notepad and emits a tracked window event", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "app.launch.request",
    requestId: "req_003",
    appId: "winapp_notepad",
    args: []
  });

  assert.equal(replies.length, 2);
  assert.equal(replies[0].type, "app.launch.response");
  assert.equal(replies[0].accepted, true);
  assert.equal(replies[1].type, "window.created");
  assert.equal(replies[1].windowId, "hwnd:0003029A");
  assert.deepEqual(validateAppLaunchAcceptance(replies[0], replies[1]), {
    appId: "winapp_notepad",
    processId: 4912,
    windowId: "hwnd:0003029A",
    title: "Untitled - Notepad"
  });
});

test("launches Calculator and emits a distinct tracked window event", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "app.launch.request",
    requestId: "req_calc",
    appId: "winapp_calculator",
    args: []
  });

  assert.equal(replies.length, 2);
  assert.deepEqual(validateAppLaunchAcceptance(replies[0], replies[1]), {
    appId: "winapp_calculator",
    processId: 4930,
    windowId: "hwnd:0004029B",
    title: "Calculator"
  });
});

test("returns the fixture app list", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "app.list.request",
    requestId: "req_002",
    protocolVersion: 1
  });

  assert.equal(replies.length, 1);
  assert.equal(replies[0].type, "app.list.response");
  assert.equal(replies[0].apps[0].id, "winapp_notepad");
});

test("accepts a window close request for a tracked HWND", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "window.close.request",
    requestId: "req_close_notepad",
    windowId: "hwnd:0003029A"
  });

  assert.equal(replies.length, 1);
  const response = validateWindowCloseResponse(replies[0]);
  assert.equal(response.requestId, "req_close_notepad");
  assert.equal(response.windowId, "hwnd:0003029A");
  assert.equal(response.accepted, true);
});

test("rejects window close requests without a HWND", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "window.close.request",
    requestId: "req_bad_close"
  });

  assert.deepEqual(replies, [
    {
      type: "error",
      requestId: "req_bad_close",
      code: "invalid_message",
      message: "window.close.request requires windowId."
    }
  ]);
});

test("accepts mouse input events without a reply", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "input.mouse",
    windowId: "hwnd:0003029A",
    event: "leftDown",
    x: 240,
    y: 130,
    modifiers: []
  });

  assert.deepEqual(replies, []);
});

test("accepts key input events without a reply", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "input.key",
    windowId: "hwnd:0003029A",
    event: "keyDown",
    key: "c",
    windowsVirtualKey: 67,
    modifiers: ["ctrl"]
  });

  assert.deepEqual(replies, []);
});

test("accepts host clipboard text without a reply", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "clipboard.text.set",
    requestId: "req_clipboard_1",
    origin: "host",
    sequence: 1,
    text: "hello from macOS"
  });

  assert.deepEqual(replies, []);
});

test("broadcasts a fixture frame when a capture stream is subscribed", async () => {
  const broadcastEvents = [];
  const session = createSession({
    broadcast: async (event) => {
      broadcastEvents.push(event);
    }
  });

  const subscribeReplies = await session.handle({
    type: "window.frame.subscribe",
    requestId: "req_frame_subscribe_notepad",
    windowId: "hwnd:0003029A",
    format: "png"
  });

  assert.deepEqual(subscribeReplies, []);
  assert.equal(broadcastEvents.length, 1);
  assert.equal(broadcastEvents[0].type, "window.frame");
  assert.equal(broadcastEvents[0].windowId, "hwnd:0003029A");
  assert.equal(broadcastEvents[0].format, "png");
});

test("accepts frame stream unsubscribe without a reply", async () => {
  const session = createSession();

  const unsubscribeReplies = await session.handle({
    type: "window.frame.unsubscribe",
    requestId: "req_frame_unsubscribe_notepad",
    windowId: "hwnd:0003029A"
  });

  assert.deepEqual(unsubscribeReplies, []);
});

test("does not echo host clipboard text back as a guest event", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "clipboard.text.set",
    requestId: "req_clipboard_2",
    origin: "host",
    sequence: 2,
    text: "do not echo"
  });

  assert.equal(replies.some((reply) => reply.origin === "guest"), false);
});

test("returns a structured error for unknown apps", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "app.launch.request",
    requestId: "req_bad",
    appId: "winapp_unknown",
    args: []
  });

  assert.deepEqual(replies, [
    {
      type: "error",
      requestId: "req_bad",
      code: "app_not_found",
      message: "No app exists for id winapp_unknown"
    }
  ]);
});

test("returns a structured error for unknown message types", async () => {
  const session = createSession();

  const replies = await session.handle({
    type: "made.up.request",
    requestId: "req_unknown"
  });

  assert.deepEqual(replies, [
    {
      type: "error",
      requestId: "req_unknown",
      code: "unknown_message_type",
      message: "Unsupported message type made.up.request"
    }
  ]);
});
