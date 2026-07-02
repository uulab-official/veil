export const MessageType = Object.freeze({
  AgentHealthRequest: "agent.health.request",
  AgentHealthResponse: "agent.health.response",
  AppListRequest: "app.list.request",
  AppListResponse: "app.list.response",
  AppLaunchRequest: "app.launch.request",
  AppLaunchResponse: "app.launch.response",
  WindowCreated: "window.created",
  WindowFrame: "window.frame",
  WindowCloseRequest: "window.close.request",
  WindowCloseResponse: "window.close.response",
  ClipboardTextSet: "clipboard.text.set",
  InputMouse: "input.mouse",
  InputKey: "input.key",
  Error: "error"
});

const knownTypes = new Set(Object.values(MessageType));
const mouseEvents = new Set(["leftDown", "leftUp", "rightDown", "rightUp", "move", "scroll"]);

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

export function validateNotepadAcceptance(launch, window) {
  if (!launch || launch.type !== MessageType.AppLaunchResponse || launch.accepted !== true) {
    throw new TypeError("Notepad launch response must be accepted.");
  }

  if (!window || window.type !== MessageType.WindowCreated) {
    throw new TypeError("Notepad launch must emit a window.created event.");
  }

  if (window.appId !== "winapp_notepad") {
    throw new TypeError("Notepad window event must reference winapp_notepad.");
  }

  if (window.processId !== launch.processId) {
    throw new TypeError("Notepad window event must match launch process.");
  }

  return {
    appId: window.appId,
    processId: launch.processId,
    windowId: window.windowId,
    title: window.title
  };
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

function requireNonEmptyString(value, fieldName, context = "Window frame") {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`${context} field '${fieldName}' must be a non-empty string.`);
  }
}

function requirePositiveInteger(value, fieldName) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new TypeError(`Window frame field '${fieldName}' must be a positive integer.`);
  }
}

function requireNonNegativeInteger(value, fieldName, context) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`${context} field '${fieldName}' must be a non-negative integer.`);
  }
}
