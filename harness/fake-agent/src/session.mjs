import { MessageType, createError, parseMessage } from "@veil/protocol";

import { readFixture } from "./fixtures.mjs";

export function createSession(options = {}) {
  const broadcast = options.broadcast ?? (async () => {});
  const onInput = options.onInput ?? (async () => {});
  const nextFrameSequence = options.nextFrameSequence ?? (() => 1);

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
          await broadcastInputFrame(message, broadcast, nextFrameSequence);
          return [];
        case MessageType.InputKey:
          await onInput(message);
          await broadcastInputFrame(message, broadcast, nextFrameSequence);
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
  const catalog = await readFixture("app.list.response.json");
  const app = catalog.apps.find((candidate) => candidate.id === message.appId);
  if (!app) {
    return [createError(message.requestId, "app_not_found", `No app exists for id ${message.appId}`)];
  }

  const launch = await readFixture("app.launch.response.json");
  const window = await readFixture("window.created.json");
  const windowMetadata = windowMetadataForApp(app.id);

  return [
    {
      ...withRequestId(launch, message.requestId),
      processId: windowMetadata.processId
    },
    {
      ...window,
      ...windowMetadata,
      appId: app.id,
      title: windowMetadata.title ?? app.name
    }
  ];
}

function windowMetadataForApp(appId) {
  switch (appId) {
    case "winapp_calculator":
      return {
        windowId: "hwnd:0004029B",
        processId: 4930,
        title: "Calculator",
        bounds: { x: 80, y: 80, width: 520, height: 720 }
      };
    case "winapp_paint":
      return {
        windowId: "hwnd:0005029C",
        processId: 4948,
        title: "Untitled - Paint",
        bounds: { x: 40, y: 40, width: 1280, height: 800 }
      };
    case "winapp_notepad":
    default:
      return {
        windowId: "hwnd:0003029A",
        processId: 4912,
        title: "Untitled - Notepad",
        bounds: { x: 10, y: 10, width: 1280, height: 800 }
      };
  }
}

async function handleWindowFrameSubscribe(message, broadcast) {
  if (!message.windowId) {
    return [createError(message.requestId, "invalid_message", "window.frame.subscribe requires windowId.")];
  }

  const frame = await readFixture("window.frame.json");
  await broadcast({
    ...frame,
    windowId: message.windowId,
    frameId: `frame_${String(1).padStart(6, "0")}`,
    sequence: 1
  });
  return [];
}

async function broadcastInputFrame(message, broadcast, nextFrameSequence) {
  if (!message.windowId) {
    return;
  }

  const sequence = nextFrameSequence();
  const frame = await readFixture("window.frame.json");
  await broadcast({
    ...frame,
    windowId: message.windowId,
    frameId: `frame_${String(sequence).padStart(6, "0")}`,
    sequence
  });
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
