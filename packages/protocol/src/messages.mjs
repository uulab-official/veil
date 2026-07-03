export const MessageType = Object.freeze({
  AgentHealthRequest: "agent.health.request",
  AgentHealthResponse: "agent.health.response",
  AppListRequest: "app.list.request",
  AppListResponse: "app.list.response",
  AppLaunchRequest: "app.launch.request",
  AppLaunchResponse: "app.launch.response",
  WindowCreated: "window.created",
  WindowUpdated: "window.updated",
  WindowClosed: "window.closed",
  WindowFrame: "window.frame",
  WindowFrameSubscribe: "window.frame.subscribe",
  WindowFrameUnsubscribe: "window.frame.unsubscribe",
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
