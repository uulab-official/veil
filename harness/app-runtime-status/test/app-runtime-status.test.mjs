import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeStatus } from "../src/validate-app-runtime-status.mjs";

test("validates app runtime status fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeStatus(report), report);
});

test("rejects reports without required actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.actions = report.actions.filter((action) => action.id !== "clipboard.setText");

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /clipboard\.setText/
  );
});

test("rejects reports without Dock integration status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  delete report.dockIntegration;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /dockIntegration/
  );
});

test("rejects reports without quiet runtime policy status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  delete report.quietRuntime;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /quietRuntime/
  );
});

test("rejects Dock integration counts that drift from mirrored sessions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.mirrorSessions.push({
    windowId: "hwnd:0003029A",
    appId: "winapp_notepad",
    title: "Untitled - Notepad",
    captureState: "streaming",
    canFocus: true,
    canClose: true,
    canSendInput: true
  });

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /openWindowCount/
  );
});

test("rejects quiet runtime counts that drift from mirrored sessions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.quietRuntime.openWindowCount = 1;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /quietRuntime\.openWindowCount/
  );
});

test("rejects live agent reports outside agent mode", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.connection.hasLiveAgentConnection = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /Only agent mode/
  );
});
