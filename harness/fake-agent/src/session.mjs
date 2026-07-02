import { MessageType, createError, parseMessage } from "@veil/protocol";

import { readFixture } from "./fixtures.mjs";

export function createSession(options = {}) {
  const broadcast = options.broadcast ?? (async () => {});
  const onInput = options.onInput ?? (async () => {});

  return {
    async handle(message) {
      const parsed = parseMessage(message);
      if (!parsed.ok) {
        return [parsed.error];
      }

      switch (message.type) {
        case MessageType.AgentHealthRequest:
          return [withRequestId(await readFixture("agent.health.response.json"), message.requestId)];
        case MessageType.AppListRequest:
          return [withRequestId(await readFixture("app.list.response.json"), message.requestId)];
        case MessageType.AppLaunchRequest:
          return handleAppLaunch(message);
        case MessageType.WindowFrameSubscribe:
          return handleWindowFrameSubscribe(message, broadcast);
        case MessageType.WindowFrameUnsubscribe:
          return [];
        case MessageType.WindowCloseRequest:
          return handleWindowClose(message);
        case MessageType.InputMouse:
          await onInput(message);
          return [];
        case MessageType.InputKey:
          await onInput(message);
          return [];
        case MessageType.ClipboardTextSet:
          return [];
        default:
          return [createError(message.requestId, "unsupported_in_fake_agent", `Fake agent cannot handle ${message.type}`)];
      }
    }
  };
}

async function handleAppLaunch(message) {
  if (message.appId !== "winapp_notepad") {
    return [createError(message.requestId, "app_not_found", `No app exists for id ${message.appId}`)];
  }

  return [
    withRequestId(await readFixture("app.launch.response.json"), message.requestId),
    await readFixture("window.created.json")
  ];
}

async function handleWindowFrameSubscribe(message, broadcast) {
  if (!message.windowId) {
    return [createError(message.requestId, "invalid_message", "window.frame.subscribe requires windowId.")];
  }

  const frame = await readFixture("window.frame.json");
  await broadcast({
    ...frame,
    windowId: message.windowId
  });
  return [];
}

async function handleWindowClose(message) {
  if (!message.windowId) {
    return [createError(message.requestId, "invalid_message", "window.close.request requires windowId.")];
  }

  return [
    {
      ...(await readFixture("window.close.response.json")),
      requestId: message.requestId,
      windowId: message.windowId
    }
  ];
}

function withRequestId(message, requestId) {
  return {
    ...message,
    requestId
  };
}
