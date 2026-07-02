import { pathToFileURL } from "node:url";
import { MessageType, validateWindowFrame } from "@veil/protocol";

import { collectEventAfter, collectReplies, sendMessage } from "./client.mjs";
import { summarizeNotepadLaunch } from "./notepad-acceptance.mjs";

const defaultClick = Object.freeze({ x: 240, y: 130 });

export async function runNotepadInputSmoke(options = {}) {
  const url = options.url ?? process.env.VEIL_AGENT_URL ?? "ws://127.0.0.1:18444";
  const text = options.text ?? process.env.VEIL_INPUT_TEXT ?? "veil";
  const click = options.click ?? defaultClick;

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

  validateWindowFrame(frame);
  let keyInputs = [];
  const postInputFrame = await collectEventAfter(
    url,
    async () => {
      await sendClick(url, acceptance.windowId, click);
      keyInputs = await sendText(url, acceptance.windowId, text);
    },
    {
      predicate: (event) => event.type === MessageType.WindowFrame
        && event.windowId === acceptance.windowId
        && event.sequence > frame.sequence
    }
  );
  validateWindowFrame(postInputFrame);

  return {
    url,
    health: health[0],
    apps: appList[0].apps,
    launch: launch[0],
    window: launch[1],
    frame,
    postInputFrame,
    click,
    text,
    keyInputs,
    acceptance
  };
}

async function sendClick(url, windowId, click) {
  await sendMessage(url, {
    type: MessageType.InputMouse,
    windowId,
    event: "leftDown",
    x: click.x,
    y: click.y,
    modifiers: []
  });
  await sendMessage(url, {
    type: MessageType.InputMouse,
    windowId,
    event: "leftUp",
    x: click.x,
    y: click.y,
    modifiers: []
  });
}

async function sendText(url, windowId, text) {
  const inputs = [];
  for (const character of text) {
    const key = character.toLowerCase();
    const windowsVirtualKey = key.toUpperCase().codePointAt(0);
    if (!windowsVirtualKey) {
      continue;
    }

    for (const event of ["keyDown", "keyUp"]) {
      const input = {
        type: MessageType.InputKey,
        windowId,
        event,
        key,
        windowsVirtualKey,
        modifiers: []
      };
      await sendMessage(url, input);
      inputs.push(input);
    }
  }

  return inputs;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const report = await runNotepadInputSmoke();
  console.log(JSON.stringify(report, null, 2));
}
