import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";
import { MessageType, validateWindowFrame } from "@veil/protocol";

import { createFakeAgentServer } from "../../fake-agent/src/fake-agent-server.mjs";
import { collectEventAfter, collectReplies, sendMessage } from "../src/client.mjs";
import { summarizeNotepadLaunch } from "../src/notepad-acceptance.mjs";

test("launches Notepad and receives a subscribed capture frame from fake-agent", async (t) => {
  const server = createFakeAgentServer({ host: "127.0.0.1", port: 0 });
  t.after(() => {
    server.close();
  });
  await once(server, "listening");
  const address = server.address();
  const url = `ws://${address.address}:${address.port}`;

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
  const frame = await collectEventAfter(
    url,
    () => sendMessage(url, {
      type: MessageType.WindowFrameSubscribe,
      requestId: "req_frame_subscribe_notepad",
      windowId: acceptance.windowId,
      format: "png"
    }),
    {
      predicate: (event) => event.type === MessageType.WindowFrame && event.windowId === acceptance.windowId
    }
  );

  assert.equal(health[0].capabilities.windowCapture, true);
  assert.equal(appList[0].apps[0].id, "winapp_notepad");
  assert.equal(acceptance.accepted, true);
  assert.equal(validateWindowFrame(frame).windowId, "hwnd:0003029A");
});
