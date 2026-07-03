import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeStatus } from "../src/validate-app-runtime-status.mjs";

test("validates app runtime status fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeStatus(report), report);
});

test("validates live Mac window integration status fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));

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

test("rejects reports without Mac window integration status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  delete report.macWindowIntegration;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /macWindowIntegration/
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

test("rejects reports without launch plan status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  delete report.launchPlan;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /launchPlan/
  );
});

test("rejects reports without pending launch status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  delete report.pendingLaunch;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /pendingLaunch/
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

test("rejects Dock integration pending launch count drift", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.pendingLaunchAppId = "winapp_notepad";
  report.pendingLaunch.isQueued = true;
  report.pendingLaunch.appId = "winapp_notepad";
  report.pendingLaunch.willLaunchOnAgentReconnect = true;
  report.pendingLaunch.recommendedAction = "auto-launch-on-agent-reconnect";
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.launchPlan.recommendedAction = "start-runtime-for-pending-launch";
  report.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending";
  report.launchPlan.reason = "The selected app launch is queued until Windows starts and the guest agent connects.";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /pendingLaunchCount/
  );
});

test("rejects Mac foregroundable window counts that drift from mirrored sessions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.macWindowIntegration.foregroundableWindowCount = 0;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /foregroundableWindowCount/
  );
});

test("rejects Mac foreground window identity that drifts from mirrored sessions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.macWindowIntegration.foregroundWindowId = "hwnd:DIFFERENT";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /foregroundWindowId/
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

test("rejects quiet-ready reports without a stop command", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.quietRuntime.hasOpenedAppWindowThisSession = true;
  report.quietRuntime.canQuietRuntime = true;
  report.quietRuntime.willQuietAutomatically = true;
  report.quietRuntime.recommendedAction = "stop-or-suspend-runtime";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /recommendedStopCommand/
  );
});

test("rejects unavailable quiet runtime reports with a stop command", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.quietRuntime.recommendedStopCommand = "veil-vmctl qemu-powerdown --json --wait-seconds 30";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /recommendedStopCommand/
  );
});

test("rejects launch plans that drift from selected app readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.launchPlan.canLaunchSelectedAppNow = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /canLaunchSelectedAppNow/
  );
});

test("rejects queued pending launch status without matching app id", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.pendingLaunchAppId = "winapp_notepad";
  report.pendingLaunch.isQueued = true;
  report.pendingLaunch.appId = "winapp_calculator";
  report.pendingLaunch.willLaunchOnAgentReconnect = true;
  report.pendingLaunch.recommendedAction = "auto-launch-on-agent-reconnect";
  report.dockIntegration.pendingLaunchCount = 1;
  report.dockIntegration.badgeLabel = "...";
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.launchPlan.recommendedAction = "start-runtime-for-pending-launch";
  report.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending";
  report.launchPlan.reason = "The selected app launch is queued until Windows starts and the guest agent connects.";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /pendingLaunch\.appId/
  );
});

test("rejects queued pending launch plans without fulfill-pending recovery", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.pendingLaunchAppId = "winapp_notepad";
  report.pendingLaunch.isQueued = true;
  report.pendingLaunch.appId = "winapp_notepad";
  report.pendingLaunch.willLaunchOnAgentReconnect = true;
  report.pendingLaunch.recommendedAction = "auto-launch-on-agent-reconnect";
  report.dockIntegration.pendingLaunchCount = 1;
  report.dockIntegration.badgeLabel = "...";
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.launchPlan.recommendedAction = "start-runtime-for-pending-launch";
  report.launchPlan.reason = "The selected app launch is queued until Windows starts and the guest agent connects.";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /fulfill-pending/
  );
});

test("rejects reconnect auto-launch after live agent connects", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.pendingLaunchAppId = "winapp_notepad";
  report.pendingLaunch.isQueued = true;
  report.pendingLaunch.appId = "winapp_notepad";
  report.pendingLaunch.willLaunchOnAgentReconnect = true;
  report.pendingLaunch.recommendedAction = "auto-launch-on-agent-reconnect";
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /willLaunchOnAgentReconnect/
  );
});

test("rejects start action availability that drifts from launch plan", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "runtime.startWindowsForApp").isAvailable = false;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /runtime\.startWindowsForApp/
  );
});

test("rejects fulfill-pending action availability that drifts from queued launch readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.pendingLaunchAppId = "winapp_notepad";
  report.pendingLaunch = {
    isQueued: true,
    appId: "winapp_notepad",
    willLaunchOnAgentReconnect: false,
    recommendedAction: "launch-pending-now",
    reason: "The live Windows agent is connected; retry the queued app launch now."
  };
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.launchPlan.recommendedAction = "fulfill-pending-now";
  report.dockIntegration.pendingLaunchCount = 1;
  report.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending";
  report.launchPlan.reason = "The live Windows agent can fulfill the queued app launch now.";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /runtime\.fulfillPendingLaunch/
  );
});

test("rejects launcher hiding without live mirrored windows", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.macWindowIntegration.hidesLauncherWhenMirroring = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /hidesLauncherWhenMirroring/
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
