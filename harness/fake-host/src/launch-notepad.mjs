import { MessageType } from "@veil/protocol";

import { collectReplies } from "./client.mjs";

const url = process.env.VEIL_AGENT_URL ?? "ws://127.0.0.1:18444";

const health = await collectReplies(url, {
  type: MessageType.AgentHealthRequest,
  requestId: "req_health",
  protocolVersion: 1
});

const appList = await collectReplies(url, {
  type: MessageType.AppListRequest,
  requestId: "req_apps",
  protocolVersion: 1
});

const launch = await collectReplies(url, {
  type: MessageType.AppLaunchRequest,
  requestId: "req_launch_notepad",
  appId: "winapp_notepad",
  args: []
}, {
  expectedCount: 2
});

console.log(JSON.stringify({
  url,
  health: health[0],
  apps: appList[0].apps,
  launch: launch[0],
  window: launch[1]
}, null, 2));
