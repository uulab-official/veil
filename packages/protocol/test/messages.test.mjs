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
  MAX_INPUT_TEXT_UTF16_LENGTH,
  validateInputKey,
  validateInputMouse,
  validateInputText,
  validateNotificationListenerRequest,
  validateNotificationListenerResponse,
  validateNotificationReceived,
  validateSharedFolderRequest,
  validateSharedFolderResponse,
  validateWindowClosed,
  validateWindowCloseRequest,
  validateWindowCloseResponse,
  validateWindowFrame,
  validateWindowFrameUnchanged,
  validateWindowFrameSubscribeRequest,
  validateWindowFrameUnsubscribeRequest,
  validateWindowFocusRequest,
  validateWindowFocusResponse,
  validateWindowResizeRequest,
  validateWindowResizeResponse,
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
    "window.frame.unchanged.json",
    "window.frame.subscribe.json",
    "window.frame.unsubscribe.json",
    "window.focus.request.json",
    "window.focus.response.json",
    "window.close.request.json",
    "window.close.response.json",
    "window.resize.request.json",
    "window.resize.response.json",
    "input.mouse.left-down.json",
    "input.key.copy.json",
    "input.text.json",
    "clipboard.text.set.host.json",
    "clipboard.text.set.guest.json",
    "notification.listener.request.json",
    "notification.listener.response.json",
    "notification.received.json",
    "shared.folder.request.json",
    "shared.folder.response.json",
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
  assert.equal(health.capabilities.windowResize, true);
  assert.equal(health.capabilities.packageIdentity, false);
  assert.equal(health.packageIdentityStatus.stage, "packageSigned");
  assert.equal(health.packageIdentityStatus.succeeded, false);
  assert.match(health.packageIdentityStatus.statusPath, /sparse-package-status\.json/);
  assert.equal(health.notificationListener.accessStatus, "packageIdentityRequired");
  assert.equal(health.notificationListener.recommendedAction, "prepare-sparse-package");
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

test("rejects a malformed optional window resize capability", async () => {
  const health = await readFixture("agent.health.response.json");
  health.capabilities.windowResize = "true";

  assert.throws(
    () => validateAgentHealthResponse(health),
    /capabilities\.windowResize/
  );
});

test("validates notification listener consent request and response", async () => {
  const request = validateNotificationListenerRequest(await readFixture("notification.listener.request.json"));
  const response = validateNotificationListenerResponse(await readFixture("notification.listener.response.json"));

  assert.equal(request.requestId, "req_notification_listener");
  assert.equal(response.accepted, false);
  assert.equal(response.notificationListener.accessStatus, "unspecified");
  assert.equal(response.notificationListener.recommendedAction, "request-notification-listener-consent");
});

test("validates a bounded window resize request and applied response", async () => {
  const request = validateWindowResizeRequest(await readFixture("window.resize.request.json"));
  const response = validateWindowResizeResponse(await readFixture("window.resize.response.json"));

  assert.equal(request.windowId, "hwnd:0003029A");
  assert.equal(request.width, 1440);
  assert.equal(request.height, 900);
  assert.equal(response.accepted, true);
  assert.deepEqual(response.bounds, { x: 10, y: 10, width: 1440, height: 900 });
});

test("rejects an unsafe window resize request", () => {
  assert.throws(
    () => validateWindowResizeRequest({
      type: MessageType.WindowResizeRequest,
      requestId: "req_resize_invalid",
      windowId: "hwnd:0003029A",
      width: 8_193,
      height: 900
    }),
    /width.*between 320 and 8192/
  );
});

test("rejects notification listener response accepted drift", async () => {
  const response = await readFixture("notification.listener.response.json");
  response.accepted = true;

  assert.throws(
    () => validateNotificationListenerResponse(response),
    /accepted/
  );
});

test("validates one received Windows notification fixture", async () => {
  const notification = validateNotificationReceived(await readFixture("notification.received.json"));

  assert.equal(notification.type, MessageType.NotificationReceived);
  assert.equal(notification.notificationId, "toast:winapp_notepad:0001");
  assert.equal(notification.appId, "winapp_notepad");
  assert.equal(notification.title, "Notepad");
  assert.equal(notification.body, "Autosaved Notes.txt");
  assert.equal(notification.receivedAt, "2026-07-10T12:15:00Z");
  assert.equal(notification.sourceAumid, "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App");
});

test("accepts a received notification from an app Veil never launched", () => {
  const notification = validateNotificationReceived({
    type: MessageType.NotificationReceived,
    notificationId: "toast:unknown:0007",
    title: "Windows Update",
    receivedAt: "2026-07-10T12:20:00Z"
  });

  assert.equal(notification.appId, undefined);
  assert.equal(notification.body, undefined);
});

test("accepts explicit nulls for optional notification metadata", () => {
  const notification = validateNotificationReceived({
    type: MessageType.NotificationReceived,
    notificationId: "toast:unknown:0008",
    appId: null,
    appName: null,
    body: null,
    sourceAumid: null,
    title: "Windows Update",
    receivedAt: "2026-07-10T12:21:00Z"
  });

  assert.equal(notification.appName, null);
});

test("rejects a received notification with a whitespace-only title", async () => {
  const notification = await readFixture("notification.received.json");
  notification.title = "   ";

  assert.throws(() => validateNotificationReceived(notification), /title/);
});

test("rejects a received notification without an ISO receivedAt", async () => {
  const notification = await readFixture("notification.received.json");
  notification.receivedAt = "not-a-date";

  assert.throws(() => validateNotificationReceived(notification), /receivedAt/);
});

test("rejects a received notification missing its notificationId", async () => {
  const notification = await readFixture("notification.received.json");
  delete notification.notificationId;

  assert.throws(() => validateNotificationReceived(notification), /notificationId/);
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

test("validates one unchanged window frame heartbeat fixture", async () => {
  const event = validateWindowFrameUnchanged(await readFixture("window.frame.unchanged.json"));

  assert.equal(event.type, MessageType.WindowFrameUnchanged);
  assert.equal(event.windowId, "hwnd:0003029A");
  assert.equal(event.sequence, 42);
  assert.equal(event.capturedAt, "2026-07-31T09:14:02Z");
});

test("rejects an unchanged frame heartbeat that smuggles image data", async () => {
  const event = await readFixture("window.frame.unchanged.json");
  event.encodedData = "iVBORw0KGgo=";

  assert.throws(() => validateWindowFrameUnchanged(event), /must not carry image data/);
});

test("rejects an unchanged frame heartbeat without a capture timestamp", async () => {
  const event = await readFixture("window.frame.unchanged.json");
  event.capturedAt = "not-a-date";

  assert.throws(() => validateWindowFrameUnchanged(event), /capturedAt/);
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

test("validates committed Unicode text input fixture", async () => {
  const input = validateInputText(await readFixture("input.text.json"));

  assert.equal(input.type, MessageType.InputText);
  assert.equal(input.windowId, "hwnd:0003029A");
  assert.equal(input.text, "안녕하세요");
});

test("accepts text that no Windows virtual key can express", () => {
  for (const text of ["안녕하세요", "こんにちは", "你好", "café", "emoji 😀"]) {
    const input = validateInputText({
      type: MessageType.InputText,
      windowId: "hwnd:0003029A",
      text
    });

    assert.equal(input.text, text, text);
  }
});

test("rejects empty committed text", () => {
  assert.throws(
    () => validateInputText({ type: MessageType.InputText, windowId: "hwnd:0003029A", text: "" }),
    /text/
  );
});

test("rejects committed text beyond the posted-message bound", () => {
  assert.throws(
    () => validateInputText({
      type: MessageType.InputText,
      windowId: "hwnd:0003029A",
      text: "a".repeat(MAX_INPUT_TEXT_UTF16_LENGTH + 1)
    }),
    /UTF-16 code units/
  );
});

test("rejects newlines and tabs in committed text", () => {
  for (const text of ["line\nbreak", "tab\there", "carriage\rreturn"]) {
    assert.throws(
      () => validateInputText({ type: MessageType.InputText, windowId: "hwnd:0003029A", text }),
      /input\.key/,
      text
    );
  }
});

test("rejects committed text without a tracked window id", () => {
  assert.throws(
    () => validateInputText({ type: MessageType.InputText, text: "안녕" }),
    /windowId/
  );
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

test("validates shared folder request and response fixtures", async () => {
  const request = validateSharedFolderRequest(await readFixture("shared.folder.request.json"));
  const response = validateSharedFolderResponse(await readFixture("shared.folder.response.json"));

  assert.equal(request.type, MessageType.SharedFolderRequest);
  assert.equal(request.shareName, "VeilShared");
  assert.equal(request.guestDirectoryPath, "C:\\VeilShared");
  assert.equal(response.type, MessageType.SharedFolderResponse);
  assert.equal(response.sharedFolder.directoryExists, true);
  assert.equal(response.sharedFolder.isShared, false);
  assert.equal(response.sharedFolder.requiresElevation, true);
  assert.match(response.sharedFolder.shareCommand, /New-SmbShare/);
});

test("rejects a shared folder share name that could not be a share name", async () => {
  for (const shareName of ["", "has space", "semi;colon", "quote\"mark", "a".repeat(65), "dollar$sign"]) {
    const request = await readFixture("shared.folder.request.json");
    request.shareName = shareName;

    assert.throws(() => validateSharedFolderRequest(request), TypeError, shareName);
  }
});

test("rejects a shared folder guest path that is relative or traverses upward", async () => {
  for (const guestDirectoryPath of ["VeilShared", "\\VeilShared", "C:\\Veil\\..\\Windows", "/Users/me"]) {
    const request = await readFixture("shared.folder.request.json");
    request.guestDirectoryPath = guestDirectoryPath;

    assert.throws(() => validateSharedFolderRequest(request), TypeError, guestDirectoryPath);
  }
});

test("rejects a shared folder status claiming a share inside a missing directory", async () => {
  const response = await readFixture("shared.folder.response.json");
  response.sharedFolder.directoryExists = false;
  response.sharedFolder.isShared = true;

  assert.throws(() => validateSharedFolderResponse(response), /directoryExists is false/);
});

test("rejects a shared folder status that is writable without being shared", async () => {
  const response = await readFixture("shared.folder.response.json");
  response.sharedFolder.isWritable = true;

  assert.throws(() => validateSharedFolderResponse(response), /isShared is false/);
});

test("rejects an elevation-blocked shared folder status with no command to run", async () => {
  const response = await readFixture("shared.folder.response.json");
  delete response.sharedFolder.shareCommand;

  assert.throws(() => validateSharedFolderResponse(response), /shareCommand/);
});

test("allows an elevation-capable agent to omit the command once the share exists", async () => {
  const response = await readFixture("shared.folder.response.json");
  response.sharedFolder.isShared = true;
  response.sharedFolder.isWritable = true;
  delete response.sharedFolder.shareCommand;

  assert.equal(validateSharedFolderResponse(response), response);
});

test("rejects an unsupported guest that still claims a working share", async () => {
  const response = await readFixture("shared.folder.response.json");
  response.sharedFolder.isSupported = false;

  assert.throws(() => validateSharedFolderResponse(response), /isSupported/);
});

test("accepts an optional sharedFolder capability and status on agent health", async () => {
  const health = await readFixture("agent.health.response.json");
  health.capabilities.sharedFolder = true;
  health.sharedFolder = (await readFixture("shared.folder.response.json")).sharedFolder;

  assert.equal(validateAgentHealthResponse(health), health);
});

test("validates agent health from an agent predating the shared folder", async () => {
  const health = await readFixture("agent.health.response.json");

  assert.equal(health.capabilities.sharedFolder, undefined);
  assert.equal(validateAgentHealthResponse(health), health);
});

test("rejects a non-boolean sharedFolder capability", async () => {
  const health = await readFixture("agent.health.response.json");
  health.capabilities.sharedFolder = "true";

  assert.throws(() => validateAgentHealthResponse(health), /capabilities\.sharedFolder/);
});
