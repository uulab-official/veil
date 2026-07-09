import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeStatus } from "../src/validate-app-runtime-status.mjs";

function setQueuedMenuBarState(report, overrides = {}) {
  report.menuBarIntegration.statusTitle = "Notepad Waiting";
  report.menuBarIntegration.symbolName = "clock.fill";
  report.menuBarIntegration.primaryActionId = overrides.primaryActionId ?? "runtime.startWindowsForApp";
  report.menuBarIntegration.primaryActionTitle = overrides.primaryActionTitle ?? "Open Windows for Notepad";
  report.menuBarIntegration.primaryActionAvailable = overrides.primaryActionAvailable ?? true;
  report.menuBarIntegration.canFulfillPendingLaunch = overrides.canFulfillPendingLaunch ?? false;
}

function setReconnectMenuBarState(report) {
  report.menuBarIntegration.statusTitle = "Notepad Can Reconnect";
  report.menuBarIntegration.symbolName = "arrow.counterclockwise.circle.fill";
  report.menuBarIntegration.primaryActionId = "windowsApps.reconnectRestore";
  report.menuBarIntegration.primaryActionTitle = "Reconnect Notepad";
  report.menuBarIntegration.primaryActionAvailable = true;
  report.menuBarIntegration.canReconnectPreviousApps = true;
}

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

test("rejects reports without menu bar integration status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  delete report.menuBarIntegration;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /menuBarIntegration/
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

test("rejects reports without proof plan status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  delete report.proofPlan;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proofPlan/
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
  setQueuedMenuBarState(report);

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /pendingLaunchCount/
  );
});

test("accepts Dock previous-app restore readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.restorableAppIds = ["winapp_notepad"];
  report.dockIntegration.restorableAppCount = 1;
  report.dockIntegration.badgeLabel = "R";
  report.dockIntegration.canReconnectPreviousApps = true;
  report.actions.find((action) => action.id === "windowsApps.reconnectRestore").isAvailable = true;
  setReconnectMenuBarState(report);

  assert.equal(validateAppRuntimeStatus(report), report);
});

test("rejects Dock previous-app restore badge drift", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.restorableAppIds = ["winapp_notepad"];
  report.dockIntegration.restorableAppCount = 1;
  report.dockIntegration.badgeLabel = "1";
  report.dockIntegration.canReconnectPreviousApps = true;
  report.actions.find((action) => action.id === "windowsApps.reconnectRestore").isAvailable = true;
  setReconnectMenuBarState(report);

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /badgeLabel/
  );
});

test("rejects menu bar primary action drift", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.menuBarIntegration.primaryActionId = "runtime.fulfillPendingLaunch";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /primaryActionAvailable/
  );
});

test("rejects menu bar symbol drift", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.menuBarIntegration.symbolName = "display";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /symbolName/
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

test("rejects launcher visibility that drifts from mirrored app windows", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.launcherVisibility.shouldHideMainWindow = false;
  report.launcherVisibility.recommendedAction = "show-launcher";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /launcherVisibility/
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
  report.quietRuntime.recommendedStopCommand = "veil-vmctl app-runtime-action --json --action stop-runtime";

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
  setQueuedMenuBarState(report);

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
  setQueuedMenuBarState(report);

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /fulfill-pending/
  );
});

test("accepts queued pending launch repair while local Windows is already running", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.pendingLaunchAppId = "winapp_notepad";
  report.pendingLaunch.isQueued = true;
  report.pendingLaunch.appId = "winapp_notepad";
  report.pendingLaunch.willLaunchOnAgentReconnect = true;
  report.pendingLaunch.recommendedAction = "auto-launch-on-agent-reconnect";
  report.dockIntegration.pendingLaunchCount = 1;
  report.dockIntegration.badgeLabel = "...";
  report.localRuntime.state = "running";
  report.localRuntime.canStart = false;
  report.localRuntime.isRunning = true;
  report.localRuntime.windowsInstalled = true;
  report.localRuntime.recommendedAction = "wait-for-guest-agent";
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.launchPlan.requiresRuntimeStart = false;
  report.launchPlan.recommendedAction = "repair-guest-agent-for-pending-launch";
  delete report.launchPlan.recommendedStartCommand;
  report.launchPlan.recommendedRepairCommand = "veil-vmctl qemu-install-agent --json --wait-seconds 120";
  report.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending";
  report.launchPlan.reason = "Windows is running and the selected app launch is queued; repair or start the guest agent, then open the app automatically.";
  report.actions.find((action) => action.id === "runtime.startWindowsForApp").isAvailable = false;
  report.actions.find((action) => action.id === "runtime.repairGuestAgentForApp").isAvailable = true;
  setQueuedMenuBarState(report, {
    primaryActionId: "runtime.repairGuestAgentForApp",
    primaryActionTitle: "Continue Notepad"
  });

  assert.doesNotThrow(() => validateAppRuntimeStatus(report));
});

test("accepts stale running console preview with recovery commands", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.localRuntime.state = "running";
  report.localRuntime.canStart = false;
  report.localRuntime.isRunning = true;
  report.localRuntime.windowsInstalled = true;
  report.localRuntime.recommendedAction = "recover-runtime-display";
  report.localRuntime.consolePreviewStatus = "stale";
  report.localRuntime.recommendedDisplayCommand = "veil-vmctl qemu-display-smoke --json";
  report.localRuntime.recommendedRecoveryCommand = "veil-vmctl qemu-capture --json";
  report.localRuntime.reason = "The local Windows runtime is running, but the embedded console preview is stale; refresh or validate display evidence before relying on app launch recovery.";
  report.launchPlan.requiresRuntimeStart = false;
  report.launchPlan.recommendedAction = "repair-guest-agent-for-app-launch";
  delete report.launchPlan.recommendedStartCommand;
  report.launchPlan.recommendedRepairCommand = "veil-vmctl qemu-install-agent --json --wait-seconds 120";
  report.launchPlan.reason = "Windows is running; repair or start the guest agent, then launch the selected app.";
  report.actions.find((action) => action.id === "runtime.startWindowsForApp").isAvailable = false;
  report.actions.find((action) => action.id === "runtime.repairGuestAgentForApp").isAvailable = true;
  report.actions.find((action) => action.id === "runtime.recoverDisplay").isAvailable = true;
  report.menuBarIntegration.symbolName = "display";
  report.menuBarIntegration.primaryActionId = "windowsApps.launchSelected";
  report.menuBarIntegration.primaryActionTitle = "Open Notepad";

  assert.doesNotThrow(() => validateAppRuntimeStatus(report));
});

test("rejects stale running console preview without recovery command", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.localRuntime.state = "running";
  report.localRuntime.canStart = false;
  report.localRuntime.isRunning = true;
  report.localRuntime.windowsInstalled = true;
  report.localRuntime.recommendedAction = "recover-runtime-display";
  report.localRuntime.consolePreviewStatus = "stale";
  report.localRuntime.reason = "The local Windows runtime is running, but the embedded console preview is stale.";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /recommendedRecoveryCommand/
  );
});

test("rejects repair action availability that drifts from launch plan", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "runtime.repairGuestAgentForApp").isAvailable = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /runtime\.repairGuestAgentForApp/
  );
});

test("rejects display recovery action availability that drifts from local runtime", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "runtime.recoverDisplay").isAvailable = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /runtime\.recoverDisplay/
  );
});

test("rejects reconnect restore action availability that drifts from restorable apps", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "windowsApps.reconnectRestore").isAvailable = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /windowsApps\.reconnectRestore/
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

test("rejects start action availability when local runtime is not boot ready", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.localRuntime.bootReady = false;
  report.localRuntime.canStart = false;
  report.localRuntime.recommendedAction = "prepare-local-runtime";
  report.localRuntime.recommendedPrepareCommand = "veil-vmctl prepare --installer /path/to/Windows.iso";
  report.localRuntime.reason = "Installer media must be re-selected before boot.";
  report.launchPlan.recommendedAction = "prepare-local-runtime";
  delete report.launchPlan.recommendedStartCommand;
  delete report.launchPlan.recommendedWaitCommand;

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
  report.menuBarIntegration.canFulfillPendingLaunch = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /runtime\.fulfillPendingLaunch/
  );
});

test("rejects wait-agent action availability that drifts from live connection readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "runtime.waitAgent").isAvailable = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /runtime\.waitAgent/
  );
});

test("rejects stop action availability that drifts from quiet runtime readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.demo.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "runtime.stopWhenIdle").isAvailable = true;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /runtime\.stopWhenIdle/
  );
});

test("rejects live agent reports without structured capabilities", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  delete report.connection.capabilities.windowCapture;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /connection\.capabilities\.windowCapture/
  );
});

test("rejects guest-agent diagnostics that drift from live connection readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.guestAgentDiagnostics.isConnected = false;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /guestAgentDiagnostics\.isConnected/
  );
});

test("rejects proof action availability that drifts from capture readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "proof.appWindow").isAvailable = false;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proof\.appWindow/
  );
});

test("rejects coherence proof availability that drifts from input readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "proof.coherence").isAvailable = false;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proof\.coherence/
  );
});

test("rejects MVP proof availability that drifts from coherence readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "proof.mvp").isAvailable = false;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proof\.mvp/
  );
});

test("rejects recommended proof availability that drifts from proof plan", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.actions.find((action) => action.id === "proof.recommended").isAvailable = false;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proof\.recommended/
  );
});

test("rejects proof plan availability that drifts from capture readiness", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.connection.capabilities.windowCapture = false;
  delete report.proofPlan.recommendedAppWindowProofCommand;
  delete report.proofPlan.recommendedCoherenceProofCommand;
  delete report.proofPlan.recommendedMVPProofCommand;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proofPlan\.canRunAppWindowProof/
  );
});

test("rejects proof plan commands that drift from selected app", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.proofPlan.recommendedAppWindowProofCommand = "veil-vmctl app-window-proof --json --app-id winapp_calculator";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /recommendedAppWindowProofCommand/
  );
});

test("rejects proof plans whose recommended proof kind is not strongest available", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.proofPlan.recommendedProofKind = "app-window";
  report.proofPlan.recommendedProofCommand = report.proofPlan.recommendedAppWindowProofCommand;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /recommendedProofKind/
  );
});

test("rejects proof plans whose recommended proof command drifts from strongest available", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.proofPlan.recommendedProofCommand = report.proofPlan.recommendedCoherenceProofCommand;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /recommendedProofCommand/
  );
});

test("rejects proof plans without the selected app id", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  delete report.proofPlan.selectedAppId;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proofPlan\.selectedAppId/
  );
});

test("rejects MVP proof plans without require-proved", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.proofPlan.recommendedMVPProofCommand = "veil-vmctl mvp-proof --json --app-id winapp_notepad";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /recommendedMVPProofCommand/
  );
});

test("rejects proof artifact paths that do not point to JSON", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.proofArtifacts.latestProofPath = "/Users/test/Library/Application Support/Veil/Diagnostics/Recommended Proof/mvp-proof-latest.txt";

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /proofArtifacts latest artifact/
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

test("rejects visible surface counts that drift from mirrored app windows", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-status.mac-window-live.json", import.meta.url), "utf8"));
  report.visibleSurfacePolicy.expectedVisibleSurfaceCount = 2;

  assert.throws(
    () => validateAppRuntimeStatus(report),
    /visibleSurfacePolicy expected surface count/
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
