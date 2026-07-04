import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeAction } from "../src/validate-app-runtime-action.mjs";

test("validates app runtime launch action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime pending launch fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime fulfill-pending fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.fulfill-pending-live.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates quiet runtime readiness action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.quiet-ready.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime stop action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.stop-runtime-live.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime bring-forward action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.bring-forward-demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime restore action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.restore-live.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime close-all action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.close-all-live.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates recommended proof action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.proof-recommended-live.json", import.meta.url), "utf8"));

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

test("rejects accepted launch actions without a foregroundable Mac window", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.status.macWindowIntegration.foregroundableWindowCount = 0;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /foregroundable/
  );
});

test("rejects accepted launch actions without a foreground window title", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  delete report.foregroundWindowTitle;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /foregroundWindowTitle/
  );
});

test("rejects accepted launch actions without a foreground window id", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  delete report.foregroundWindowId;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /foregroundWindowId/
  );
});

test("rejects pending launch actions with a fake window", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.window = {
    type: "window.created",
    windowId: "hwnd:FAKE",
    processId: 4912,
    appId: "winapp_notepad",
    title: "Fake Notepad",
    bounds: {
      x: 80,
      y: 80,
      width: 1180,
      height: 760
    },
    state: "normal",
    focused: true
  };

  assert.throws(
    () => validateAppRuntimeAction(report),
    /rejected launch actions cannot include window/
  );
});

test("rejects pending launch actions whose app id drifts", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.status.launchPlan.pendingLaunchAppId = "winapp_calculator";
  report.status.pendingLaunchAppId = "winapp_calculator";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /pendingLaunchAppId/
  );
});

test("rejects launch actions without top-level launch plan", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  delete report.launchPlan;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /top-level launchPlan/
  );
});

test("rejects accepted fulfill-pending actions that leave pending launch queued", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.fulfill-pending-live.json", import.meta.url), "utf8"));
  report.status.pendingLaunchAppId = "winapp_notepad";
  report.status.pendingLaunch = {
    isQueued: true,
    appId: "winapp_notepad",
    willLaunchOnAgentReconnect: false,
    recommendedAction: "launch-pending-now",
    reason: "The live Windows agent is connected; retry the queued app launch now."
  };
  report.status.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.status.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending";
  report.status.dockIntegration.pendingLaunchCount = 1;
  report.status.actions.find((action) => action.id === "runtime.fulfillPendingLaunch").isAvailable = true;
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /clear status\.pendingLaunch/
  );
});

test("rejects accepted fulfill-pending actions without a window", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.fulfill-pending-live.json", import.meta.url), "utf8"));
  delete report.window;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /window must be an object/
  );
});

test("rejects pending launch actions whose top-level app id drifts", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.pendingLaunchAppId = "winapp_calculator";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /pendingLaunchAppId must match/
  );
});

test("rejects launch actions whose top-level launch plan drifts from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action launch --app-id winapp_calculator";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /top-level launchPlan/
  );
});

test("rejects actions without top-level proof plan", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  delete report.proofPlan;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /proofPlan/
  );
});

test("rejects actions whose top-level proof plan drifts from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.fulfill-pending-live.json", import.meta.url), "utf8"));
  report.proofPlan.recommendedMVPProofCommand = "veil-vmctl mvp-proof --json --app-id winapp_calculator --require-proved";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /top-level proofPlan/
  );
});

test("rejects accepted actions without proof handoff in next actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.fulfill-pending-live.json", import.meta.url), "utf8"));
  report.nextActions = report.nextActions.filter((action) => !action.includes("mvp-proof"));

  assert.throws(
    () => validateAppRuntimeAction(report),
    /nextActions/
  );
});

test("rejects recommended proof actions whose proof command drifts from proof plan", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.proof-recommended-live.json", import.meta.url), "utf8"));
  report.proof.command = "veil-vmctl app-window-proof --json --app-id winapp_notepad";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /proof\.command/
  );
});

test("rejects accepted recommended proof actions without proof evidence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.proof-recommended-live.json", import.meta.url), "utf8"));
  delete report.proof;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /proof-recommended actions must include proof/
  );
});

test("rejects proof evidence on non-proof actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.proof = {
    kind: "windowsAppRuntimeRecommendedProofRun",
    proofKind: "app-window",
    command: "veil-vmctl app-window-proof --json --app-id winapp_notepad",
    appId: "winapp_notepad",
    status: "proved",
    windowId: "hwnd:0003029A",
    windowTitle: "Untitled - Notepad",
    frameSequence: 1,
    nextActions: []
  };

  assert.throws(
    () => validateAppRuntimeAction(report),
    /proof is only allowed/
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

test("rejects quiet runtime actions whose decision drifts from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.quiet-ready.json", import.meta.url), "utf8"));
  report.quietRuntime.reason = "Drifted from nested status.";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /must match report\.status\.quietRuntime/
  );
});

test("rejects quiet-ready actions without a stop command", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.quiet-ready.json", import.meta.url), "utf8"));
  delete report.quietRuntime.recommendedStopCommand;
  delete report.status.quietRuntime.recommendedStopCommand;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /recommendedStopCommand/
  );
});

test("rejects accepted stop-runtime actions without a stopped runtime snapshot", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.stop-runtime-live.json", import.meta.url), "utf8"));
  report.runtimeStop.state = "running";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /runtimeStop\.state stopped/
  );
});

test("rejects runtimeStop evidence on non-stop actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.runtimeStop = {
    state: "stopped"
  };

  assert.throws(
    () => validateAppRuntimeAction(report),
    /only allowed for stop-runtime/
  );
});

test("rejects unavailable quiet runtime status with a stop command", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.status.quietRuntime.recommendedStopCommand = "veil-vmctl app-runtime-action --json --action stop-runtime";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /recommendedStopCommand/
  );
});

test("rejects bring-forward actions whose windows drift from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.bring-forward-demo.json", import.meta.url), "utf8"));
  report.broughtForwardWindowIds = ["hwnd:DIFFERENT"];

  assert.throws(
    () => validateAppRuntimeAction(report),
    /broughtForwardWindowIds/
  );
});

test("rejects bring-forward actions whose foreground title drifts from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.bring-forward-demo.json", import.meta.url), "utf8"));
  report.foregroundWindowTitle = "Different Window";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /foreground Windows app window title/
  );
});

test("rejects bring-forward actions whose foreground id drifts from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.bring-forward-demo.json", import.meta.url), "utf8"));
  report.foregroundWindowId = "hwnd:DIFFERENT";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /foreground Windows app window id/
  );
});

test("rejects close-all actions that leave mirrored sessions open", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.close-all-live.json", import.meta.url), "utf8"));
  report.status.mirrorSessions = [
    {
      windowId: "hwnd:STILL_OPEN",
      appId: "winapp_notepad",
      title: "Untitled - Notepad",
      captureState: "pending",
      canFocus: true,
      canClose: true,
      canSendInput: true
    }
  ];
  report.status.dockIntegration.openWindowCount = 1;
  report.status.dockIntegration.badgeLabel = "1";
  report.status.dockIntegration.canBringWindowsAppsForward = true;
  report.status.macWindowIntegration.mirroredWindowCount = 1;
  report.status.macWindowIntegration.foregroundableWindowCount = 1;
  report.status.macWindowIntegration.foregroundWindowId = "hwnd:STILL_OPEN";
  report.status.macWindowIntegration.foregroundWindowTitle = "Untitled - Notepad";
  report.status.macWindowIntegration.pendingFrameWindowCount = 1;
  report.status.macWindowIntegration.hidesLauncherWhenMirroring = true;
  report.status.launcherVisibility.shouldHideMainWindow = true;
  report.status.launcherVisibility.recommendedAction = "hide-main-window-use-app-windows";
  report.status.quietRuntime.openWindowCount = 1;
  report.status.quietRuntime.canQuietRuntime = false;
  report.status.quietRuntime.willQuietAutomatically = false;
  delete report.status.quietRuntime.recommendedStopCommand;
  report.status.actions.find((action) => action.id === "runtime.quietWhenIdle").isAvailable = false;
  report.status.actions.find((action) => action.id === "runtime.stopWhenIdle").isAvailable = false;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /must leave no mirrored/
  );
});

test("rejects close-all actions with rejected close responses", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.close-all-live.json", import.meta.url), "utf8"));
  report.closedWindows[1].accepted = false;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /rejected close responses/
  );
});

test("rejects restore actions whose app ids drift from request", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.restore-live.json", import.meta.url), "utf8"));
  report.restoredWindows[0].appId = "winapp_paint";

  assert.throws(
    () => validateAppRuntimeAction(report),
    /restoredWindows appIds/
  );
});

test("allows rejected restore actions to keep requested app ids", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.restore-live.json", import.meta.url), "utf8"));
  report.accepted = false;
  report.restoredWindows = [];
  report.status.mirrorSessions = [];
  report.status.dockIntegration.openWindowCount = 0;
  report.status.dockIntegration.badgeLabel = undefined;
  report.status.dockIntegration.canBringWindowsAppsForward = false;
  report.status.macWindowIntegration.hidesLauncherWhenMirroring = false;
  report.status.macWindowIntegration.mirroredWindowCount = 0;
  report.status.macWindowIntegration.foregroundableWindowCount = 0;
  delete report.status.macWindowIntegration.foregroundWindowId;
  delete report.status.macWindowIntegration.foregroundWindowTitle;
  report.status.macWindowIntegration.pendingFrameWindowCount = 0;
  report.status.launcherVisibility.shouldHideMainWindow = false;
  report.status.launcherVisibility.recommendedAction = "show-launcher-or-restore-apps";
  report.status.quietRuntime.openWindowCount = 0;

  assert.equal(validateAppRuntimeAction(report), report);
});

test("rejects restore actions whose windows are absent from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.restore-live.json", import.meta.url), "utf8"));
  report.status.mirrorSessions = [];
  report.status.dockIntegration.openWindowCount = 0;
  report.status.dockIntegration.badgeLabel = undefined;
  report.status.dockIntegration.canBringWindowsAppsForward = false;
  report.status.macWindowIntegration.hidesLauncherWhenMirroring = false;
  report.status.macWindowIntegration.mirroredWindowCount = 0;
  report.status.macWindowIntegration.foregroundableWindowCount = 0;
  delete report.status.macWindowIntegration.foregroundWindowId;
  delete report.status.macWindowIntegration.foregroundWindowTitle;
  report.status.macWindowIntegration.pendingFrameWindowCount = 0;
  report.status.launcherVisibility.shouldHideMainWindow = false;
  report.status.launcherVisibility.recommendedAction = "show-launcher-or-restore-apps";
  report.status.quietRuntime.openWindowCount = 0;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /restoredWindows must be present/
  );
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

test("validates app runtime click actions", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  report.action = "click";
  report.accepted = true;
  delete report.launch;
  delete report.window;
  report.windowId = "hwnd:0003029A";
  report.mouseInputs = [
    {
      type: "input.mouse",
      windowId: "hwnd:0003029A",
      event: "leftDown",
      x: 240,
      y: 130,
      modifiers: []
    },
    {
      type: "input.mouse",
      windowId: "hwnd:0003029A",
      event: "leftUp",
      x: 240,
      y: 130,
      modifiers: []
    }
  ];

  assert.equal(validateAppRuntimeAction(report), report);
});
