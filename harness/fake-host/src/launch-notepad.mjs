import { MessageType } from "@veil/protocol";

import { collectEventAfter, collectReplies, sendMessage } from "./client.mjs";
import { summarizeNotepadLaunch } from "./notepad-acceptance.mjs";

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

const acceptance = summarizeNotepadLaunch({
  launch: launch[0],
  window: launch[1]
});

let frame = null;
if (health[0].capabilities.windowCapture) {
  frame = await collectEventAfter(
    url,
    () => sendMessage(url, {
      type: MessageType.WindowFrameSubscribe,
      requestId: "req_frame_subscribe_notepad",
      windowId: launch[1].windowId,
      format: "png"
    }),
    {
      predicate: (event) => event.type === MessageType.WindowFrame && event.windowId === launch[1].windowId
    }
  );
}

console.log(JSON.stringify({
  url,
  health: health[0],
  apps: appList[0].apps,
  launch: launch[0],
  window: launch[1],
  frame,
  acceptance
}, null, 2));
