import assert from "node:assert/strict";
import test from "node:test";

import { summarizeNotepadLaunch } from "../src/notepad-acceptance.mjs";

test("summarizes a valid Notepad acceptance flow", () => {
  const summary = summarizeNotepadLaunch({
    launch: {
      type: "app.launch.response",
      requestId: "req_launch_notepad",
      accepted: true,
      processId: 4912
    },
    window: {
      type: "window.created",
      windowId: "hwnd:0003029A",
      processId: 4912,
      appId: "winapp_notepad",
      title: "Untitled - Notepad"
    }
  });

  assert.deepEqual(summary, {
    accepted: true,
    appId: "winapp_notepad",
    processId: 4912,
    windowId: "hwnd:0003029A",
    title: "Untitled - Notepad"
  });
});
