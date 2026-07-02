export const MessageType = Object.freeze({
  AgentHealthRequest: "agent.health.request",
  AgentHealthResponse: "agent.health.response",
  AppListRequest: "app.list.request",
  AppListResponse: "app.list.response",
  AppLaunchRequest: "app.launch.request",
  AppLaunchResponse: "app.launch.response",
  WindowCreated: "window.created",
  ClipboardTextSet: "clipboard.text.set",
  InputMouse: "input.mouse",
  InputKey: "input.key",
  Error: "error"
});

const knownTypes = new Set(Object.values(MessageType));

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
