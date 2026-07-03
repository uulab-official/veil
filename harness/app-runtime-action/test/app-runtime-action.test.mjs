import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeAction } from "../src/validate-app-runtime-action.mjs";

test("validates app runtime launch action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("rejects accepted launch actions without a window", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  delete report.window;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /window must be an object/
  );
});

test("rejects unsupported app runtime actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.action = "teleport";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /Unsupported app runtime action/
  );
});

test("validates app runtime clipboard actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.action = "clipboard";
  report.accepted = true;
  delete report.launch;
  delete report.window;
  report.clipboard = {
    type: "clipboard.text.set",
    requestId: "req_app_runtime_clipboard",
    origin: "host",
    sequence: 1,
    text: "hello from macOS"
  };

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime type-text actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.action = "type-text";
  report.accepted = true;
  delete report.launch;
  delete report.window;
  report.windowId = "hwnd:0003029A";
  report.typedTextCharacterCount = 1;
  report.keyInputs = [
    {
      type: "input.key",
      windowId: "hwnd:0003029A",
      event: "keyDown",
      key: "v",
      windowsVirtualKey: 86,
      modifiers: []
    },
    {
      type: "input.key",
      windowId: "hwnd:0003029A",
      event: "keyUp",
      key: "v",
      windowsVirtualKey: 86,
      modifiers: []
    }
  ];

  assert.equal(validateAppRuntimeAction(report), report);
});
