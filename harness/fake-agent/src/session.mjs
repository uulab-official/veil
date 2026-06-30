import { MessageType, createError, parseMessage } from "@veil/protocol";

import { readFixture } from "./fixtures.mjs";

export function createSession() {
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

function withRequestId(message, requestId) {
  return {
    ...message,
    requestId
  };
}
