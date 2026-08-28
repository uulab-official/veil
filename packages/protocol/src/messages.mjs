export const MessageType = Object.freeze({
  AgentHealthRequest: "agent.health.request",
  AgentHealthResponse: "agent.health.response",
  AppListRequest: "app.list.request",
  AppListResponse: "app.list.response",
  AppLaunchRequest: "app.launch.request",
  AppLaunchResponse: "app.launch.response",
  FileOpenRequest: "file.open.request",
  FileOpenResponse: "file.open.response",
  WindowCreated: "window.created",
  WindowUpdated: "window.updated",
  WindowClosed: "window.closed",
  WindowFrame: "window.frame",
  WindowFrameUnchanged: "window.frame.unchanged",
  WindowFrameSubscribe: "window.frame.subscribe",
  WindowFrameUnsubscribe: "window.frame.unsubscribe",
  WindowFocusRequest: "window.focus.request",
  WindowFocusResponse: "window.focus.response",
  WindowCloseRequest: "window.close.request",
  WindowCloseResponse: "window.close.response",
  WindowResizeRequest: "window.resize.request",
  WindowResizeResponse: "window.resize.response",
  ClipboardTextSet: "clipboard.text.set",
  NotificationListenerRequest: "notification.listener.request",
  NotificationListenerResponse: "notification.listener.response",
  NotificationReceived: "notification.received",
  SharedFolderRequest: "shared.folder.request",
  SharedFolderResponse: "shared.folder.response",
  InputMouse: "input.mouse",
  InputKey: "input.key",
  InputText: "input.text",
  Error: "error"
});

// One `input.text` message becomes one posted window message per UTF-16 code unit on the guest, so
// the payload is bounded here rather than letting a single message flood the target HWND.
export const MAX_INPUT_TEXT_UTF16_LENGTH = 4096;

const knownTypes = new Set(Object.values(MessageType));
const mouseEvents = new Set(["leftDown", "leftUp", "rightDown", "rightUp", "move", "scroll"]);
const keyEvents = new Set(["keyDown", "keyUp"]);
const clipboardOrigins = new Set(["host", "guest"]);

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

export function validateAgentHealthResponse(response) {
  if (!response || response.type !== MessageType.AgentHealthResponse) {
    throw new TypeError("Agent health response must use type agent.health.response.");
  }

  requireNonEmptyString(response.requestId, "requestId", "Agent health response");
  requirePositiveInteger(response.protocolVersion, "protocolVersion", "Agent health response");
  requireNonEmptyString(response.agentVersion, "agentVersion", "Agent health response");
  requireNonEmptyString(response.os, "os", "Agent health response");

  if (!response.session || typeof response.session !== "object" || Array.isArray(response.session)) {
    throw new TypeError("Agent health response field 'session' must be an object.");
  }
  if (typeof response.session.interactive !== "boolean") {
    throw new TypeError("Agent health response field 'session.interactive' must be a boolean.");
  }
  requireNonEmptyString(response.session.user, "session.user", "Agent health response");

  if (!response.capabilities || typeof response.capabilities !== "object" || Array.isArray(response.capabilities)) {
    throw new TypeError("Agent health response field 'capabilities' must be an object.");
  }
  for (const field of [
    "appList",
    "appLaunch",
    "windowTracking",
    "windowCapture",
    "input",
    "clipboardText",
    "packageIdentity"
  ]) {
    if (typeof response.capabilities[field] !== "boolean") {
      throw new TypeError(`Agent health response field 'capabilities.${field}' must be a boolean.`);
    }
  }

  // Optional so an agent predating the binary frame channel still validates. When absent the host keeps
  // using the JSON frame path rather than opening an endpoint that does not exist.
  if (response.capabilities.binaryFrameChannel !== undefined
    && typeof response.capabilities.binaryFrameChannel !== "boolean") {
    throw new TypeError("Agent health response field 'capabilities.binaryFrameChannel' must be a boolean.");
  }

  // Optional for the same back-compat reason. When absent the host reports that the shared folder
  // cannot be confirmed, which is different from reporting that the share is missing.
  if (response.capabilities.sharedFolder !== undefined
    && typeof response.capabilities.sharedFolder !== "boolean") {
    throw new TypeError("Agent health response field 'capabilities.sharedFolder' must be a boolean.");
  }

  // Optional so a host connected to an older agent can disable the resize affordance instead of
  // sending a message that the agent cannot route.
  if (response.capabilities.windowResize !== undefined
    && typeof response.capabilities.windowResize !== "boolean") {
    throw new TypeError("Agent health response field 'capabilities.windowResize' must be a boolean.");
  }

  if (response.packageIdentityStatus !== undefined) {
    validatePackageIdentityStatus(response.packageIdentityStatus);
  }
  if (response.notificationListener !== undefined) {
    validateNotificationListenerStatus(response.notificationListener);
  }
  if (response.sharedFolder !== undefined) {
    validateSharedFolderStatus(response.sharedFolder);
  }

  return response;
}

export function validateSharedFolderRequest(request) {
  if (!request || request.type !== MessageType.SharedFolderRequest) {
    throw new TypeError("Shared folder request must use type shared.folder.request.");
  }

  const context = "Shared folder request";
  requireNonEmptyString(request.requestId, "requestId", context);
  requirePositiveInteger(request.protocolVersion, "protocolVersion", context);
  requireNonEmptyString(request.shareName, "shareName", context);
  requireNonEmptyString(request.guestDirectoryPath, "guestDirectoryPath", context);

  // The share name lands in an SMB share name and in an elevated PowerShell command on the guest, so
  // it is restricted here rather than trusted. Same reasoning as the snapshot tag rule.
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(request.shareName)) {
    throw new TypeError(
      "Shared folder request field 'shareName' must be 1-64 characters of letters, digits, dot, dash, or underscore."
    );
  }

  // A bare drive-letter path. Anything with a separator-relative segment could redirect the share
  // somewhere the user did not intend.
  if (!/^[A-Za-z]:\\/.test(request.guestDirectoryPath) || request.guestDirectoryPath.includes("..")) {
    throw new TypeError(
      "Shared folder request field 'guestDirectoryPath' must be an absolute Windows path with no parent-directory traversal."
    );
  }

  return request;
}

export function validateSharedFolderResponse(response) {
  if (!response || response.type !== MessageType.SharedFolderResponse) {
    throw new TypeError("Shared folder response must use type shared.folder.response.");
  }

  const context = "Shared folder response";
  requireNonEmptyString(response.requestId, "requestId", context);
  requirePositiveInteger(response.protocolVersion, "protocolVersion", context);
  validateSharedFolderStatus(response.sharedFolder, context);
  return response;
}

function validateSharedFolderStatus(status, context = "Agent health response") {
  if (!status || typeof status !== "object" || Array.isArray(status)) {
    throw new TypeError(`${context} field 'sharedFolder' must be an object when present.`);
  }

  for (const field of [
    "isSupported",
    "directoryExists",
    "isShared",
    "isWritable",
    "serverListening",
    "requiresElevation",
    "requiresCredentials"
  ]) {
    if (typeof status[field] !== "boolean") {
      throw new TypeError(`${context} field 'sharedFolder.${field}' must be a boolean.`);
    }
  }

  requireNonEmptyString(status.shareName, "sharedFolder.shareName", context);
  requireNonEmptyString(status.guestDirectoryPath, "sharedFolder.guestDirectoryPath", context);
  requireNonEmptyString(status.recommendedAction, "sharedFolder.recommendedAction", context);

  for (const field of ["shareCommand", "message"]) {
    if (status[field] !== undefined && status[field] !== null) {
      requireNonEmptyString(status[field], `sharedFolder.${field}`, context);
    }
  }

  // A share cannot exist inside a directory that does not exist, and a share that does not exist
  // cannot be writable. Catching these here stops a guest bug from being reported as a mount problem.
  if (status.isShared && !status.directoryExists) {
    throw new TypeError(`${context} field 'sharedFolder.isShared' cannot be true while directoryExists is false.`);
  }
  if (status.isWritable && !status.isShared) {
    throw new TypeError(`${context} field 'sharedFolder.isWritable' cannot be true while isShared is false.`);
  }

  // The whole point of reporting elevation is telling the user what to run, so the command is
  // required exactly when elevation is what is blocking the share.
  if (status.requiresElevation && !status.isShared && !status.shareCommand) {
    throw new TypeError(
      `${context} field 'sharedFolder.shareCommand' is required when requiresElevation is true and the share does not exist.`
    );
  }

  // Reporting an unsupported guest and a working share at the same time would let a stub agent look
  // like a real one.
  if (!status.isSupported && (status.isShared || status.serverListening)) {
    throw new TypeError(
      `${context} field 'sharedFolder.isSupported' must be true when the guest reports a share or a listening server.`
    );
  }
}

export function validateNotificationListenerRequest(request) {
  if (!request || request.type !== MessageType.NotificationListenerRequest) {
    throw new TypeError("Notification listener request must use type notification.listener.request.");
  }

  requireNonEmptyString(request.requestId, "requestId", "Notification listener request");
  requirePositiveInteger(request.protocolVersion, "protocolVersion", "Notification listener request");
  return request;
}

export function validateNotificationListenerResponse(response) {
  if (!response || response.type !== MessageType.NotificationListenerResponse) {
    throw new TypeError("Notification listener response must use type notification.listener.response.");
  }

  requireNonEmptyString(response.requestId, "requestId", "Notification listener response");
  requirePositiveInteger(response.protocolVersion, "protocolVersion", "Notification listener response");
  if (typeof response.accepted !== "boolean") {
    throw new TypeError("Notification listener response field 'accepted' must be a boolean.");
  }
  validateNotificationListenerStatus(response.notificationListener, "Notification listener response");
  if (response.accepted !== response.notificationListener.canListen) {
    throw new TypeError("Notification listener response field 'accepted' must match notificationListener.canListen.");
  }
  return response;
}

// Guest-to-host notification event. `appId`/`appName`/`body`/`sourceAumid` stay optional because
// Windows notifications can come from apps Veil never launched, so the host cannot require an
// appId it would recognize. Kept aligned with harness/notification-proof and the host-side
// `notificationBridge.latestNotification` contract so a saved proof and a live event validate the
// same way.
export function validateNotificationReceived(notification) {
  if (!notification || notification.type !== MessageType.NotificationReceived) {
    throw new TypeError("Notification event must use type notification.received.");
  }

  const context = "Notification event";
  requireNonEmptyString(notification.notificationId, "notificationId", context);
  requireNonEmptyString(notification.title, "title", context);
  if (notification.title.trim().length === 0) {
    throw new TypeError("Notification event field 'title' must not be whitespace only.");
  }
  requireNonEmptyString(notification.receivedAt, "receivedAt", context);
  if (Number.isNaN(Date.parse(notification.receivedAt))) {
    throw new TypeError("Notification event field 'receivedAt' must be an ISO date.");
  }

  for (const field of ["appId", "appName", "body", "sourceAumid"]) {
    if (notification[field] !== undefined && notification[field] !== null) {
      requireNonEmptyString(notification[field], field, context);
    }
  }

  return notification;
}

function validateNotificationListenerStatus(status, context = "Agent health response") {
  if (!status || typeof status !== "object" || Array.isArray(status)) {
    throw new TypeError(`${context} field 'notificationListener' must be an object when present.`);
  }

  for (const field of ["isSupported", "canListen", "requiresPackageIdentity"]) {
    if (typeof status[field] !== "boolean") {
      throw new TypeError(`${context} field 'notificationListener.${field}' must be a boolean.`);
    }
  }
  requireNonEmptyString(status.accessStatus, "notificationListener.accessStatus", context);
  requireNonEmptyString(status.recommendedAction, "notificationListener.recommendedAction", context);
  if (status.message !== undefined) {
    requireNonEmptyString(status.message, "notificationListener.message", context);
  }
}

function validatePackageIdentityStatus(status) {
  if (!status || typeof status !== "object" || Array.isArray(status)) {
    throw new TypeError("Agent health response field 'packageIdentityStatus' must be an object when present.");
  }

  requireNonEmptyString(status.statusPath, "packageIdentityStatus.statusPath", "Agent health response");
  requireNonEmptyString(status.stage, "packageIdentityStatus.stage", "Agent health response");
  if (typeof status.succeeded !== "boolean") {
    throw new TypeError("Agent health response field 'packageIdentityStatus.succeeded' must be a boolean.");
  }

  for (const field of ["message", "updatedAt", "packagePath", "certificatePath"]) {
    if (status[field] !== undefined) {
      requireNonEmptyString(status[field], `packageIdentityStatus.${field}`, "Agent health response");
    }
  }
}

export function validateAppLaunchAcceptance(launch, window) {
  if (!launch || launch.type !== MessageType.AppLaunchResponse || launch.accepted !== true) {
    throw new TypeError("App launch response must be accepted.");
  }

  if (!window || window.type !== MessageType.WindowCreated) {
    throw new TypeError("App launch must emit a window.created event.");
  }

  requireNonEmptyString(window.appId, "appId", "Window created event");

  if (window.processId !== launch.processId) {
    throw new TypeError("Window created event must match launch process.");
  }

  return {
    appId: window.appId,
    processId: launch.processId,
    windowId: window.windowId,
    title: window.title
  };
}

export const validateNotepadAcceptance = validateAppLaunchAcceptance;

export function validateWindowLifecycleMetadata(window, expectedType = MessageType.WindowCreated) {
  if (!window || window.type !== expectedType) {
    throw new TypeError(`Window lifecycle event must use type ${expectedType}.`);
  }

  requireNonEmptyString(window.windowId, "windowId", "Window lifecycle event");
  requirePositiveInteger(window.processId, "processId", "Window lifecycle event");
  requireNonEmptyString(window.appId, "appId", "Window lifecycle event");
  requireNonEmptyString(window.title, "title", "Window lifecycle event");
  requireWindowBounds(window.bounds, "Window lifecycle event");
  requireNonEmptyString(window.state, "state", "Window lifecycle event");
  if (typeof window.focused !== "boolean") {
    throw new TypeError("Window lifecycle event field 'focused' must be a boolean.");
  }

  return window;
}

// Windows reserves these names for device files regardless of extension ("CON.txt" still resolves
// to the CON device) -- mirrors AgentSession.cs's ReservedWindowsDeviceNames on the guest so this
// pre-flight validator actually predicts what the guest will accept.
const reservedWindowsDeviceNames = new Set([
  "CON", "PRN", "AUX", "NUL",
  "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
  "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
]);

export function validateFileOpenRequest(request) {
  if (!request || request.type !== MessageType.FileOpenRequest) {
    throw new TypeError("File open request must use type file.open.request.");
  }

  requireNonEmptyString(request.requestId, "requestId", "File open request");
  requireNonEmptyString(request.appId, "appId", "File open request");
  requireNonEmptyString(request.fileName, "fileName", "File open request");

  // Matches AgentSession.cs's TryResolveSafeFileName: trim first (the guest rejects
  // whitespace-only names via IsNullOrWhiteSpace before ever comparing to "."/".."), then check
  // separators/traversal, then reserved device names.
  const fileName = request.fileName.trim();
  const nameWithoutExtension = fileName.includes(".") ? fileName.slice(0, fileName.lastIndexOf(".")) : fileName;
  if (
    fileName.length === 0
    || /[\\/]/.test(fileName)
    || fileName === "."
    || fileName === ".."
    || reservedWindowsDeviceNames.has(nameWithoutExtension.toUpperCase())
  ) {
    throw new TypeError(
      "File open request field 'fileName' must be a bare, non-reserved file name with no path separators."
    );
  }

  requireNonEmptyString(request.contentBase64, "contentBase64", "File open request");
  return request;
}

export function validateFileOpenResponse(response) {
  if (!response || response.type !== MessageType.FileOpenResponse) {
    throw new TypeError("File open response must use type file.open.response.");
  }

  requireNonEmptyString(response.requestId, "requestId", "File open response");
  if (typeof response.accepted !== "boolean") {
    throw new TypeError("File open response field 'accepted' must be a boolean.");
  }

  if (response.accepted) {
    requirePositiveInteger(response.processId, "processId", "File open response");
  }

  return response;
}

export function validateWindowUpdated(updated) {
  return validateWindowLifecycleMetadata(updated, MessageType.WindowUpdated);
}

export function validateWindowClosed(closed) {
  if (!closed || closed.type !== MessageType.WindowClosed) {
    throw new TypeError("Window closed event must use type window.closed.");
  }

  requireNonEmptyString(closed.windowId, "windowId", "Window closed event");
  return closed;
}

export function validateWindowFrame(frame) {
  if (!frame || frame.type !== MessageType.WindowFrame) {
    throw new TypeError("Window frame must use type window.frame.");
  }

  requireNonEmptyString(frame.windowId, "windowId");
  requireNonEmptyString(frame.frameId, "frameId");
  requireNonEmptyString(frame.format, "format");
  requirePositiveInteger(frame.sequence, "sequence");
  requirePositiveInteger(frame.width, "width");
  requirePositiveInteger(frame.height, "height");

  if (typeof frame.scale !== "number" || frame.scale <= 0) {
    throw new TypeError("Window frame field 'scale' must be a positive number.");
  }

  requireNonEmptyString(frame.encodedData, "encodedData");
  return frame;
}

// Proof that a frame stream is alive with nothing new to draw.
//
// Without this the host cannot distinguish an idle window from broken capture: freshness is derived
// from when the last frame arrived, so a guest that stopped re-sending identical pixels would be
// marked stale and escalated into subscription restart, capture recovery, and app reopen. That forced
// the guest to re-encode a full-window PNG several times a second for a completely static window.
//
// Deliberately carries no image payload. It updates liveness, never the displayed frame.
export function validateWindowFrameUnchanged(event) {
  if (!event || event.type !== MessageType.WindowFrameUnchanged) {
    throw new TypeError("Unchanged window frame event must use type window.frame.unchanged.");
  }

  requireNonEmptyString(event.windowId, "windowId", "Unchanged window frame event");
  requirePositiveInteger(event.sequence, "sequence", "Unchanged window frame event");
  requireNonEmptyString(event.capturedAt, "capturedAt", "Unchanged window frame event");
  if (Number.isNaN(Date.parse(event.capturedAt))) {
    throw new TypeError("Unchanged window frame event field 'capturedAt' must be an ISO date.");
  }

  if (event.encodedData !== undefined) {
    throw new TypeError("Unchanged window frame event must not carry image data.");
  }

  return event;
}

export function validateWindowFrameSubscribeRequest(request) {
  if (!request || request.type !== MessageType.WindowFrameSubscribe) {
    throw new TypeError("Window frame subscribe request must use type window.frame.subscribe.");
  }

  requireNonEmptyString(request.requestId, "requestId", "Window frame subscribe request");
  requireNonEmptyString(request.windowId, "windowId", "Window frame subscribe request");
  requireNonEmptyString(request.format, "format", "Window frame subscribe request");
  if (request.format !== "png") {
    throw new TypeError("Window frame subscribe request field 'format' must be png.");
  }

  return request;
}

export function validateWindowFrameUnsubscribeRequest(request) {
  if (!request || request.type !== MessageType.WindowFrameUnsubscribe) {
    throw new TypeError("Window frame unsubscribe request must use type window.frame.unsubscribe.");
  }

  requireNonEmptyString(request.requestId, "requestId", "Window frame unsubscribe request");
  requireNonEmptyString(request.windowId, "windowId", "Window frame unsubscribe request");
  return request;
}

export function validateWindowFocusRequest(request) {
  if (!request || request.type !== MessageType.WindowFocusRequest) {
    throw new TypeError("Window focus request must use type window.focus.request.");
  }

  requireNonEmptyString(request.requestId, "requestId", "Window focus request");
  requireNonEmptyString(request.windowId, "windowId", "Window focus request");
  return request;
}

export function validateWindowFocusResponse(response) {
  if (!response || response.type !== MessageType.WindowFocusResponse) {
    throw new TypeError("Window focus response must use type window.focus.response.");
  }

  requireNonEmptyString(response.requestId, "requestId", "Window focus response");
  requireNonEmptyString(response.windowId, "windowId", "Window focus response");
  if (typeof response.accepted !== "boolean") {
    throw new TypeError("Window focus response field 'accepted' must be a boolean.");
  }

  return response;
}

export function validateWindowCloseRequest(request) {
  if (!request || request.type !== MessageType.WindowCloseRequest) {
    throw new TypeError("Window close request must use type window.close.request.");
  }

  requireNonEmptyString(request.requestId, "requestId", "Window close request");
  requireNonEmptyString(request.windowId, "windowId", "Window close request");
  return request;
}

export function validateWindowCloseResponse(response) {
  if (!response || response.type !== MessageType.WindowCloseResponse) {
    throw new TypeError("Window close response must use type window.close.response.");
  }

  requireNonEmptyString(response.requestId, "requestId", "Window close response");
  requireNonEmptyString(response.windowId, "windowId", "Window close response");
  if (typeof response.accepted !== "boolean") {
    throw new TypeError("Window close response field 'accepted' must be a boolean.");
  }

  return response;
}

export function validateWindowResizeRequest(request) {
  if (!request || request.type !== MessageType.WindowResizeRequest) {
    throw new TypeError("Window resize request must use type window.resize.request.");
  }

  requireNonEmptyString(request.requestId, "requestId", "Window resize request");
  requireNonEmptyString(request.windowId, "windowId", "Window resize request");
  requireResizeDimension(request.width, "width");
  requireResizeDimension(request.height, "height");
  if (request.width > 32_000_000 / request.height) {
    throw new TypeError("Window resize request dimensions must contain at most 32000000 pixels.");
  }

  return request;
}

export function validateWindowResizeResponse(response) {
  if (!response || response.type !== MessageType.WindowResizeResponse) {
    throw new TypeError("Window resize response must use type window.resize.response.");
  }

  requireNonEmptyString(response.requestId, "requestId", "Window resize response");
  requireNonEmptyString(response.windowId, "windowId", "Window resize response");
  if (typeof response.accepted !== "boolean") {
    throw new TypeError("Window resize response field 'accepted' must be a boolean.");
  }

  if (response.accepted) {
    requireWindowBounds(response.bounds, "Window resize response");
  } else if (response.bounds !== undefined && response.bounds !== null) {
    throw new TypeError("Window resize response must not include bounds when accepted is false.");
  }

  return response;
}

function requireResizeDimension(value, fieldName) {
  if (!Number.isInteger(value) || value < 320 || value > 8_192) {
    throw new TypeError(`Window resize request field '${fieldName}' must be between 320 and 8192.`);
  }
}

export function validateInputMouse(input) {
  if (!input || input.type !== MessageType.InputMouse) {
    throw new TypeError("Mouse input must use type input.mouse.");
  }

  requireNonEmptyString(input.windowId, "windowId", "Mouse input");
  requireNonEmptyString(input.event, "event", "Mouse input");
  if (!mouseEvents.has(input.event)) {
    throw new TypeError(`Mouse input event '${input.event}' is not supported.`);
  }

  requireNonNegativeInteger(input.x, "x", "Mouse input");
  requireNonNegativeInteger(input.y, "y", "Mouse input");
  if (!Array.isArray(input.modifiers) || input.modifiers.some((modifier) => typeof modifier !== "string")) {
    throw new TypeError("Mouse input field 'modifiers' must be an array of strings.");
  }

  return input;
}

export function validateInputKey(input) {
  if (!input || input.type !== MessageType.InputKey) {
    throw new TypeError("Key input must use type input.key.");
  }

  requireNonEmptyString(input.windowId, "windowId", "Key input");
  requireNonEmptyString(input.event, "event", "Key input");
  if (!keyEvents.has(input.event)) {
    throw new TypeError(`Key input event '${input.event}' is not supported.`);
  }

  requireNonEmptyString(input.key, "key", "Key input");
  requirePositiveInteger(input.windowsVirtualKey, "windowsVirtualKey", "Key input");
  if (!Array.isArray(input.modifiers) || input.modifiers.some((modifier) => typeof modifier !== "string")) {
    throw new TypeError("Key input field 'modifiers' must be an array of strings.");
  }

  return input;
}

// Committed Unicode text for a tracked HWND.
//
// This exists because `input.key` carries a Windows *virtual key*, and characters outside the virtual
// key map -- every Hangul syllable, kana, and Han character -- have no representation there. macOS
// owns the IME: it composes, and only finished text is sent here. There is deliberately no marked or
// in-progress text on the wire, so the guest never has to render a candidate window over a mirrored
// bitmap.
export function validateInputText(input) {
  if (!input || input.type !== MessageType.InputText) {
    throw new TypeError("Text input must use type input.text.");
  }

  requireNonEmptyString(input.windowId, "windowId", "Text input");
  if (typeof input.text !== "string" || input.text.length === 0) {
    throw new TypeError("Text input field 'text' must be a non-empty string.");
  }
  if (input.text.length > MAX_INPUT_TEXT_UTF16_LENGTH) {
    throw new TypeError(
      `Text input field 'text' must be at most ${MAX_INPUT_TEXT_UTF16_LENGTH} UTF-16 code units.`
    );
  }

  // Newlines and tabs are real keys with virtual-key equivalents and different guest semantics
  // (Enter submits, Tab moves focus). Routing them through committed text would bypass that, so they
  // stay on the `input.key` path.
  if (/[\r\n\t]/.test(input.text)) {
    throw new TypeError("Text input field 'text' must not contain newlines or tabs; send those as input.key.");
  }

  return input;
}

export function validateClipboardTextSet(clipboard) {
  if (!clipboard || clipboard.type !== MessageType.ClipboardTextSet) {
    throw new TypeError("Clipboard text must use type clipboard.text.set.");
  }

  requireNonEmptyString(clipboard.requestId, "requestId", "Clipboard text");
  requireNonEmptyString(clipboard.origin, "origin", "Clipboard text");
  if (!clipboardOrigins.has(clipboard.origin)) {
    throw new TypeError(`Clipboard text origin '${clipboard.origin}' is not supported.`);
  }

  requirePositiveInteger(clipboard.sequence, "sequence", "Clipboard text");
  if (typeof clipboard.text !== "string") {
    throw new TypeError("Clipboard text field 'text' must be a string.");
  }

  return clipboard;
}

function requireNonEmptyString(value, fieldName, context = "Window frame") {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`${context} field '${fieldName}' must be a non-empty string.`);
  }
}

function requirePositiveInteger(value, fieldName, context = "Window frame") {
  if (!Number.isInteger(value) || value <= 0) {
    throw new TypeError(`${context} field '${fieldName}' must be a positive integer.`);
  }
}

function requireNonNegativeInteger(value, fieldName, context) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`${context} field '${fieldName}' must be a non-negative integer.`);
  }
}

function requireWindowBounds(bounds, context) {
  if (!bounds || typeof bounds !== "object") {
    throw new TypeError(`${context} field 'bounds' must be an object.`);
  }

  requireNonNegativeInteger(bounds.x, "bounds.x", context);
  requireNonNegativeInteger(bounds.y, "bounds.y", context);
  requirePositiveInteger(bounds.width, "bounds.width", context);
  requirePositiveInteger(bounds.height, "bounds.height", context);
}
