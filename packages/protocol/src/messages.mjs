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
  WindowFrameSubscribe: "window.frame.subscribe",
  WindowFrameUnsubscribe: "window.frame.unsubscribe",
  WindowFocusRequest: "window.focus.request",
  WindowFocusResponse: "window.focus.response",
  WindowCloseRequest: "window.close.request",
  WindowCloseResponse: "window.close.response",
  ClipboardTextSet: "clipboard.text.set",
  InputMouse: "input.mouse",
  InputKey: "input.key",
  Error: "error"
});

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

  return response;
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
