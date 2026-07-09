import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeAction } from "../src/validate-app-runtime-action.mjs";

function setReleaseGateStep(report, id, overrides) {
  Object.assign(report.status.releaseGate.steps.find((step) => step.id === id), overrides);
  refreshReleaseGateSummary(report);
}

function refreshReleaseGateSummary(report) {
  const requiredSteps = report.status.releaseGate.steps.filter((step) => step.isRequired);
  report.status.releaseGate.requiredStepCount = requiredSteps.length;
  report.status.releaseGate.passingStepCount = requiredSteps.filter((step) => step.isPassing).length;
  report.status.releaseGate.isPassing = report.status.releaseGate.passingStepCount === report.status.releaseGate.requiredStepCount;
  report.status.releaseGate.recommendedAction = requiredSteps.find((step) => !step.isPassing)?.id ?? "ready-for-release-card";
  refreshPrimaryNextAction(report);
}

function refreshPrimaryNextAction(report) {
  if (report.status.releaseGate.isPassing) {
    report.status.primaryNextAction = {
      id: "ready-for-release-card",
      title: "Review App Flow",
      source: "releaseGate",
      isAvailable: true,
      runsInApp: false,
      command: "veil-vmctl app-runtime-review --json",
      reason: report.status.releaseGate.reason
    };
    refreshOneScreenUX(report);
    refreshLaunchOnboarding(report);
    return;
  }

  const nextStep = report.status.releaseGate.steps.find((step) => step.id === report.status.releaseGate.recommendedAction);
  const actionId = expectedPrimaryNextActionId(nextStep.id, nextStep.nextActionCommand);
  report.status.primaryNextAction = {
    id: nextStep.id,
    title: nextStep.title,
    source: "releaseGate",
    isAvailable: nextStep.nextActionCommand !== undefined,
    runsInApp: actionId !== undefined,
    ...(actionId === undefined ? {} : { actionId }),
    command: nextStep.nextActionCommand,
    reason: nextStep.evidence
  };
  refreshOneScreenUX(report);
  refreshLaunchOnboarding(report);
}

function expectedPrimaryNextActionId(stepId, command) {
  if (command === undefined) {
    return undefined;
  }

  switch (stepId) {
    case "windowsSetup":
      if (command === "veil-vmctl qemu-install-status --json"
        || command === "veil-vmctl app-runtime-status --json") {
        return "runtime.refreshStatus";
      }
      if (command.includes("--action stop-runtime")
        || command.includes("qemu-powerdown")) {
        return "runtime.stopWhenIdle";
      }
      if (command.includes("--action quiet-when-idle")) {
        return "runtime.quietWhenIdle";
      }
      if (command.startsWith("veil-vmctl prepare")) {
        return "runtime.prepareWindows";
      }
      if (command.includes("qemu-start")) {
        return "runtime.startWindowsForApp";
      }
      return undefined;
    case "oneScreenPath":
      return "runtime.refreshStatus";
    case "openWindowsApp":
      if (command.includes("--action fulfill-pending")) {
        return "runtime.fulfillPendingLaunch";
      }
      if (command.includes("--action launch")) {
        return "windowsApps.launchSelected";
      }
      if (command.includes("--action recover-display")) {
        return "runtime.recoverDisplay";
      }
      if (command.includes("--action wait-agent")) {
        return "runtime.waitAgent";
      }
      if (command.includes("qemu-install-agent")) {
        return "runtime.repairGuestAgentForApp";
      }
      if (command.includes("qemu-start")) {
        return "runtime.startWindowsForApp";
      }
      return undefined;
    case "appCheckEvidence":
      return "proof.recommended";
    case "closeOrRestore":
      if (command.includes("--action close-all")) {
        return "windowsApps.closeAll";
      }
      if (command.includes("--action reconnect-restore")
        || command.includes("--action restore")) {
        return "windowsApps.reconnectRestore";
      }
      if (command.includes("--action stop-runtime")
        || command.includes("--action quiet-when-idle")) {
        return "runtime.quietWhenIdle";
      }
      return undefined;
    default:
      return undefined;
  }
}

function installedRuntimeHeroSupports(actionId) {
  return [
    "windowsApps.launchSelected",
    "runtime.fulfillPendingLaunch",
    "runtime.recoverDisplay",
    "runtime.waitAgent",
    "runtime.repairGuestAgentForApp",
    "runtime.startWindowsForApp",
    "runtime.prepareWindows",
    "runtime.refreshStatus",
    "windowsApps.reconnectRestore",
    "windowsApps.restorePrevious",
    "windowsApps.closeAll",
    "runtime.quietWhenIdle",
    "runtime.stopWhenIdle",
    "proof.recommended"
  ].includes(actionId);
}

function refreshOneScreenUX(report) {
  const status = report.status;
  const mode = status.visibleSurfacePolicy.primarySurface;
  const hidesLauncherDuringAppMirroring = mode === "windows-app-windows"
    ? status.launcherVisibility.shouldHideMainWindow && status.macWindowIntegration.hidesLauncherWhenMirroring
    : !status.launcherVisibility.shouldHideMainWindow;
  const canRecoverFromMenuOrDock = mode === "windows-app-windows"
    ? status.menuBarIntegration.canBringWindowsAppsForward && status.launcherVisibility.keepsDockMenuAvailable
    : status.menuBarIntegration.canOpenMainWindow || status.launcherVisibility.canOpenMainWindow;
  const returnsToLauncherWhenNoAppWindows = mode === "windows-app-windows"
    || (mode === "launcher"
      && status.visibleSurfacePolicy.expectedVisibleSurfaceCount === 1
      && status.launcherVisibility.shouldHideMainWindow === false);
  const primaryActionId = status.primaryNextAction.actionId ?? status.menuBarIntegration.primaryActionId;
  const heroRunsPrimaryAction = status.primaryNextAction.runsInApp
    && installedRuntimeHeroSupports(status.primaryNextAction.actionId);

  status.oneScreenUX = {
    isEnabled: true,
    mode,
    expectedVisibleSurfaceCount: status.visibleSurfacePolicy.expectedVisibleSurfaceCount,
    usesSinglePrimarySurfaceFamily: true,
    hidesLauncherDuringAppMirroring,
    keepsMenuBarControlAvailable: status.menuBarIntegration.isEnabled,
    keepsDockControlAvailable: status.launcherVisibility.keepsDockMenuAvailable,
    canRecoverFromMenuOrDock,
    returnsToLauncherWhenNoAppWindows,
    keepsDisplayRecoveryManual: status.visibleSurfacePolicy.keepsRecoveryDisplayManual,
    primaryActionId,
    heroRunsPrimaryAction,
    reason: mode === "windows-app-windows"
      ? "Mirrored Windows app windows become the only normal surface while menu and Dock recovery stay available."
      : "The Veil launcher remains the single setup surface until a Windows app window is ready."
  };
}

function refreshLaunchOnboarding(report) {
  const status = report.status;
  const canContinueInApp = status.primaryNextAction.runsInApp
    && status.primaryNextAction.isAvailable
    && status.oneScreenUX.heroRunsPrimaryAction;
  const state = status.releaseGate.isPassing
    ? "ready-for-review"
    : (canContinueInApp
      ? "continue-in-app"
      : (status.primaryNextAction.isAvailable ? "external-check" : "blocked"));
  const reason = status.releaseGate.isPassing
    ? "The app-first launch flow is ready for review evidence."
    : (canContinueInApp
      ? "Continue from the single Veil launcher action without opening a separate VM manager surface."
      : (status.primaryNextAction.isAvailable
        ? "The next app-flow check is available, but it should run as a review or CLI handoff instead of an in-app launcher button."
        : "The one-screen Windows app launch flow needs setup or recovery before it can continue."));

  status.launchOnboarding = {
    isEnabled: true,
    state,
    currentStepId: status.primaryNextAction.id,
    currentStepTitle: status.primaryNextAction.title,
    usesSinglePrimarySurface: status.oneScreenUX.usesSinglePrimarySurfaceFamily,
    expectedVisibleSurfaceCount: status.oneScreenUX.expectedVisibleSurfaceCount,
    canContinueInApp,
    heroRunsPrimaryAction: status.oneScreenUX.heroRunsPrimaryAction,
    keepsRecoveryInMenuOrDock: status.oneScreenUX.canRecoverFromMenuOrDock,
    keepsVMDisplayManual: status.oneScreenUX.keepsDisplayRecoveryManual,
    pendingLiveProof: !status.releaseGate.isPassing,
    ...(status.primaryNextAction.actionId === undefined ? {} : { primaryActionId: status.primaryNextAction.actionId }),
    ...(status.primaryNextAction.command === undefined ? {} : { primaryCommand: status.primaryNextAction.command }),
    reason
  };
}

function configureRunningStaleGuestToolsMedia(report) {
  const rebuildCommand = "veil-vmctl prepare --installer /Users/test/Downloads/Win11_25H2_Korean_Arm64_v2.iso --drivers /Users/test/Downloads/virtio-win.iso";
  const stopCommand = "veil-vmctl app-runtime-action --json --action stop-runtime";

  report.status.localRuntime.state = "running";
  report.status.localRuntime.bootReady = true;
  report.status.localRuntime.canStart = false;
  report.status.localRuntime.isRunning = true;
  report.status.localRuntime.windowsInstalled = true;
  report.status.localRuntime.requiresGuestToolsMediaRebuild = true;
  report.status.localRuntime.recommendedAction = "rebuild-guest-tools-media";
  report.status.localRuntime.recommendedMediaRebuildCommand = rebuildCommand;
  report.status.localRuntime.recommendedPowerDownCommand = stopCommand;
  report.status.localRuntime.reason = "The local Windows runtime is running with stale guest tools media attached; power down Windows, rebuild VeilAutoInstall.iso, then restart before repairing the app connection.";
  delete report.status.localRuntime.recommendedPrepareCommand;
  delete report.status.localRuntime.recommendedRecoveryCommand;
  report.status.localRuntime.automaticInstallMediaStatus = {
    state: "stale",
    isCurrent: false,
    mediaPath: "/Users/test/Virtual Machines/Veil Shared/VeilAutoInstall.iso",
    sourcePath: "/Users/test/Virtual Machines/Veil Shared",
    mediaModifiedAt: "2026-07-03T11:55:00Z",
    sourceModifiedAt: "2026-07-03T11:56:00Z",
    recommendedAction: "rebuild-media-and-relaunch",
    rebuildCommand,
    requiresRelaunch: true,
    detail: "VeilAutoInstall.iso is older than the staged Autounattend or guest-agent bundle."
  };

  report.status.launchPlan.requiresRuntimeStart = false;
  report.status.launchPlan.requiresGuestAgent = true;
  report.status.launchPlan.willOpenAppAutomatically = false;
  report.status.launchPlan.recommendedAction = "rebuild-guest-tools-media-before-launch";
  report.status.launchPlan.reason = "The selected Windows app can be requested, but guest tools media must be rebuilt before Veil can repair the app connection.";
  delete report.status.launchPlan.recommendedStartCommand;
  delete report.status.launchPlan.recommendedWaitCommand;
  delete report.status.launchPlan.recommendedRepairCommand;
  if (report.launchPlan !== undefined) {
    report.launchPlan = { ...report.status.launchPlan };
  }

  report.status.actions.find((action) => action.id === "runtime.startWindowsForApp").isAvailable = false;
  report.status.actions.find((action) => action.id === "runtime.repairGuestAgentForApp").isAvailable = false;
  report.status.actions.find((action) => action.id === "runtime.stopWhenIdle").isAvailable = true;
  report.status.menuBarIntegration.primaryActionId = "runtime.stopWhenIdle";
  report.status.menuBarIntegration.primaryActionTitle = "Stop Windows";
  report.status.menuBarIntegration.primaryActionAvailable = true;

  setReleaseGateStep(report, "windowsSetup", {
    state: "blocked",
    isPassing: false,
    evidence: report.status.localRuntime.reason,
    nextActionCommand: stopCommand
  });
  setReleaseGateStep(report, "openWindowsApp", {
    state: "blocked",
    isPassing: false,
    evidence: report.status.launchPlan.reason,
    nextActionCommand: report.status.launchPlan.recommendedLaunchCommand
  });

  report.nextActions = [
    `Run \`${stopCommand}\` to stop Windows before rebuilding the attached guest tools media.`,
    `Run \`${rebuildCommand}\` after Windows stops so the next launch attaches a current VeilAutoInstall.iso.`,
    "Run `veil-vmctl app-runtime-status --json` after rebuilding media, then start Windows and retry the app connection."
  ];
}

test("validates app runtime launch action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime pending launch fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates pending launch repair action while local Windows is running", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.launchPlan.requiresRuntimeStart = false;
  report.launchPlan.recommendedAction = "repair-guest-agent-for-pending-launch";
  delete report.launchPlan.recommendedStartCommand;
  report.launchPlan.recommendedRepairCommand = "veil-vmctl qemu-install-agent --json --wait-seconds 120";
  report.launchPlan.reason = "Windows is running and the selected app launch is queued; repair or start the guest agent, then open the app automatically.";
  report.nextActions = [
    "Run `veil-vmctl guest-agent-wait --json --wait-seconds 30` to wait for the Windows guest agent.",
    "Run `veil-vmctl qemu-install-agent --json --wait-seconds 120` to repair or start the Windows guest agent from attached media.",
    "Run `veil-vmctl app-runtime-action --json --action fulfill-pending` after the guest agent connects."
  ];
  report.status.launchPlan = { ...report.launchPlan };
  report.status.localRuntime.state = "running";
  report.status.localRuntime.canStart = false;
  report.status.localRuntime.isRunning = true;
  report.status.localRuntime.windowsInstalled = true;
  report.status.localRuntime.recommendedAction = "wait-for-guest-agent";
  report.status.localRuntime.reason = "The local Windows runtime is already running; wait for the guest agent before opening Windows apps.";
  report.status.actions.find((action) => action.id === "runtime.startWindowsForApp").isAvailable = false;
  report.status.actions.find((action) => action.id === "runtime.repairGuestAgentForApp").isAvailable = true;
  report.status.menuBarIntegration.primaryActionId = "runtime.repairGuestAgentForApp";
  report.status.menuBarIntegration.primaryActionTitle = "Continue Notepad";
  setReleaseGateStep(report, "windowsSetup", {
    state: "passed",
    isPassing: true
  });
  setReleaseGateStep(report, "openWindowsApp", {
    nextActionCommand: "veil-vmctl app-runtime-action --json --action fulfill-pending"
  });

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates pending launch recovery when guest tools media must be rebuilt first", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  configureRunningStaleGuestToolsMedia(report);

  assert.equal(validateAppRuntimeAction(report), report);
});

test("rejects stale guest tools media action guidance that still recommends repair", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  configureRunningStaleGuestToolsMedia(report);
  report.nextActions = [
    "Run `veil-vmctl qemu-install-agent --json --wait-seconds 120` to repair or start the Windows guest agent from attached media.",
    "Run `veil-vmctl app-runtime-action --json --action fulfill-pending` after the guest agent connects."
  ];

  assert.throws(
    () => validateAppRuntimeAction(report),
    /stop Windows first/
  );
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

test("validates accepted display recovery action with fresh console evidence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.action = "recover-display";
  report.accepted = true;
  delete report.appId;
  delete report.windowId;
  delete report.launchPlan;
  delete report.launch;
  delete report.window;
  report.displayRecovery = {
    kind: "windowsAppRuntimeDisplayRecovery",
    command: "veil-vmctl qemu-capture --json",
    beforePreviewStatus: "stale",
    afterPreviewStatus: "fresh",
    beforeScreenshotPath: "/tmp/qemu-console.png",
    afterScreenshotPath: "/tmp/qemu-console.png",
    capture: {
      kind: "qemuConsoleCapture",
      monitorSocketPath: "/tmp/qemu-monitor.sock",
      consoleScreenshotPath: "/tmp/qemu-console.png",
      capturedAt: "2026-07-04T16:00:00Z"
    }
  };
  report.status.localRuntime.consolePreviewStatus = "fresh";
  report.status.localRuntime.recommendedAction = "wait-for-guest-agent";
  delete report.status.localRuntime.recommendedRecoveryCommand;
  report.status.actions.find((action) => action.id === "runtime.recoverDisplay").isAvailable = false;
  report.nextActions = [
    "Run `veil-vmctl qemu-display-smoke --json` to validate the embedded Windows display frame.",
    "Run `veil-vmctl app-runtime-status --json` before retrying the queued Windows app launch."
  ];

  assert.equal(validateAppRuntimeAction(report), report);
});

test("rejects accepted display recovery without fresh console evidence", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.action = "recover-display";
  report.accepted = true;
  delete report.appId;
  delete report.windowId;
  delete report.launchPlan;
  delete report.launch;
  delete report.window;
  report.displayRecovery = {
    kind: "windowsAppRuntimeDisplayRecovery",
    command: "veil-vmctl qemu-capture --json",
    beforePreviewStatus: "stale",
    afterPreviewStatus: "stale",
    capture: {
      kind: "qemuConsoleCapture",
      monitorSocketPath: "/tmp/qemu-monitor.sock",
      consoleScreenshotPath: "/tmp/qemu-console.png",
      capturedAt: "2026-07-04T16:00:00Z"
    }
  };

  assert.throws(
    () => validateAppRuntimeAction(report),
    /fresh afterPreviewStatus/
  );
});

test("validates app runtime restore action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.restore-live.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates app runtime reconnect restore from restored windows", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.restore-live.json", import.meta.url), "utf8"));
  report.action = "reconnect-restore";
  report.nextActions = [
    "Open or focus reconnected Windows app windows from the menu bar.",
    "Run `veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved` to verify the full Windows app runtime loop.",
    "Run `veil-vmctl app-runtime-status --json` to inspect restored sessions."
  ];

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

test("validates wait-agent unavailable action fixture", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.wait-agent-unavailable.json", import.meta.url), "utf8"));

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates wait-agent stale media guidance before guest-agent repair", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.wait-agent-unavailable.json", import.meta.url), "utf8"));
  configureRunningStaleGuestToolsMedia(report);

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates connected wait-agent action reports", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.proof-recommended-live.json", import.meta.url), "utf8"));
  const agentWait = JSON.parse(readFileSync(new URL("../../guest-agent-wait/fixtures/guest-agent-wait.connected.json", import.meta.url), "utf8"));
  report.action = "wait-agent";
  report.accepted = true;
  delete report.appId;
  delete report.windowId;
  delete report.foregroundWindowId;
  delete report.foregroundWindowTitle;
  delete report.proof;
  report.agentWait = agentWait;
  report.nextActions = [
    "Run `veil-vmctl app-runtime-status --json` to inspect launch, restore, and proof readiness.",
    "Run `veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved` to verify the full Windows app runtime loop."
  ];

  assert.equal(validateAppRuntimeAction(report), report);
});

test("validates unavailable wait-agent action reports", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  const agentWait = unavailableAgentWaitFixture();
  report.action = "wait-agent";
  report.accepted = false;
  delete report.appId;
  report.agentWait = agentWait;
  report.nextActions = [
    "Run `veil-vmctl qemu-install-agent --json --wait-seconds 120` to send the attached guest-agent repair path.",
    "Run `veil-host-probe --diagnose-agent` to inspect host-forward TCP and WebSocket health.",
    "Run `veil-vmctl app-runtime-status --json` before retrying app launch or reconnect-restore."
  ];

  assert.equal(validateAppRuntimeAction(report), report);
});

test("rejects wait-agent action reports whose accepted flag drifts", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  report.action = "wait-agent";
  report.accepted = true;
  report.agentWait = unavailableAgentWaitFixture();

  assert.throws(
    () => validateAppRuntimeAction(report),
    /accepted/
  );
});

test("rejects accepted launch actions without a window", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-demo.json", import.meta.url), "utf8"));
  delete report.window;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /window must be an object/
  );
});

function unavailableAgentWaitFixture() {
  const agentWait = JSON.parse(readFileSync(new URL("../../guest-agent-wait/fixtures/guest-agent-wait.connected.json", import.meta.url), "utf8"));
  const nextActions = [
    "Inside Windows, run Veil Shared\\Veil Guest Agent\\Install Veil Agent.cmd.",
    "If macOS can open the forwarded port but health still times out, run Veil Shared\\Veil Guest Agent\\Repair Veil Agent Connectivity.cmd and approve the Windows administrator prompt."
  ];
  agentWait.status = "unavailable";
  agentWait.waitedSeconds = 1;
  agentWait.attempts = 2;
  delete agentWait.connectedAt;
  agentWait.nextActions = nextActions;
  agentWait.diagnostic.status = "unavailable";
  delete agentWait.diagnostic.health;
  agentWait.diagnostic.errorMessage = "Timed out waiting for agent.health.response.";
  agentWait.diagnostic.hostForwardProbe = {
    endpoint: "ws://127.0.0.1:18444",
    host: "127.0.0.1",
    port: 18444,
    status: "tcpOpen",
    detail: "TCP opened but WebSocket health did not respond."
  };
  agentWait.diagnostic.nextActions = nextActions;
  return agentWait;
}

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
  report.status.menuBarIntegration.canFulfillPendingLaunch = true;
  report.launchPlan.pendingLaunchAppId = "winapp_notepad";
  report.launchPlan.recommendedLaunchCommand = "veil-vmctl app-runtime-action --json --action fulfill-pending";
  setReleaseGateStep(report, "openWindowsApp", {
    nextActionCommand: "veil-vmctl app-runtime-action --json --action fulfill-pending"
  });

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

test("rejects pending launch actions without start or repair recovery", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.launch-pending.json", import.meta.url), "utf8"));
  delete report.launchPlan.recommendedStartCommand;
  delete report.status.launchPlan.recommendedStartCommand;
  report.status.actions.find((action) => action.id === "runtime.startWindowsForApp").isAvailable = false;

  assert.throws(
    () => validateAppRuntimeAction(report),
    /recommendedStartCommand/
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
  report.status.menuBarIntegration.statusTitle = "1 Windows App Open";
  report.status.menuBarIntegration.symbolName = "rectangle.stack.fill";
  report.status.menuBarIntegration.primaryActionId = "dock.bringWindowsAppsForward";
  report.status.menuBarIntegration.primaryActionTitle = "Bring Notepad Forward";
  report.status.menuBarIntegration.canBringWindowsAppsForward = true;
  report.status.macWindowIntegration.mirroredWindowCount = 1;
  report.status.macWindowIntegration.foregroundableWindowCount = 1;
  report.status.macWindowIntegration.foregroundWindowId = "hwnd:STILL_OPEN";
  report.status.macWindowIntegration.foregroundWindowTitle = "Untitled - Notepad";
  report.status.macWindowIntegration.pendingFrameWindowCount = 1;
  report.status.macWindowIntegration.hidesLauncherWhenMirroring = true;
  report.status.launcherVisibility.shouldHideMainWindow = true;
  report.status.launcherVisibility.recommendedAction = "hide-main-window-use-app-windows";
  report.status.visibleSurfacePolicy.primarySurface = "windows-app-windows";
  report.status.visibleSurfacePolicy.expectedVisibleSurfaceCount = 1;
  report.status.visibleSurfacePolicy.shouldHideLauncher = true;
  report.status.quietRuntime.openWindowCount = 1;
  report.status.quietRuntime.canQuietRuntime = false;
  report.status.quietRuntime.willQuietAutomatically = false;
  delete report.status.quietRuntime.recommendedStopCommand;
  report.status.actions.find((action) => action.id === "runtime.quietWhenIdle").isAvailable = false;
  report.status.actions.find((action) => action.id === "runtime.stopWhenIdle").isAvailable = false;
  report.status.actions.find((action) => action.id === "dock.bringWindowsAppsForward").isAvailable = true;
  setReleaseGateStep(report, "closeOrRestore", {
    state: "ready",
    isPassing: true,
    nextActionCommand: "veil-vmctl app-runtime-action --json --action close-all"
  });

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
  report.status.dockIntegration.badgeLabel = "R";
  report.status.dockIntegration.canBringWindowsAppsForward = false;
  report.status.dockIntegration.canReconnectPreviousApps = true;
  report.status.dockIntegration.canRestorePreviousApps = true;
  report.status.menuBarIntegration.statusTitle = "Notepad Ready";
  report.status.menuBarIntegration.symbolName = "arrow.counterclockwise.circle.fill";
  report.status.menuBarIntegration.primaryActionId = "windowsApps.restorePrevious";
  report.status.menuBarIntegration.primaryActionTitle = "Restore Notepad";
  report.status.menuBarIntegration.canBringWindowsAppsForward = false;
  report.status.menuBarIntegration.canReconnectPreviousApps = true;
  report.status.menuBarIntegration.canRestorePreviousApps = true;
  report.status.macWindowIntegration.hidesLauncherWhenMirroring = false;
  report.status.macWindowIntegration.mirroredWindowCount = 0;
  report.status.macWindowIntegration.foregroundableWindowCount = 0;
  delete report.status.macWindowIntegration.foregroundWindowId;
  delete report.status.macWindowIntegration.foregroundWindowTitle;
  report.status.macWindowIntegration.pendingFrameWindowCount = 0;
  report.status.launcherVisibility.shouldHideMainWindow = false;
  report.status.launcherVisibility.recommendedAction = "show-launcher-or-restore-apps";
  report.status.visibleSurfacePolicy.primarySurface = "launcher";
  report.status.visibleSurfacePolicy.expectedVisibleSurfaceCount = 1;
  report.status.visibleSurfacePolicy.shouldHideLauncher = false;
  report.status.quietRuntime.openWindowCount = 0;
  report.status.actions.find((action) => action.id === "windowsApps.restorePrevious").isAvailable = true;
  report.status.actions.find((action) => action.id === "windowsApps.reconnectRestore").isAvailable = true;
  setReleaseGateStep(report, "closeOrRestore", {
    state: "ready",
    isPassing: true,
    nextActionCommand: "veil-vmctl app-runtime-action --json --action reconnect-restore"
  });

  assert.equal(validateAppRuntimeAction(report), report);
});

test("rejects restore actions whose windows are absent from status", () => {
  const report = JSON.parse(readFileSync(new URL("../fixtures/app-runtime-action.restore-live.json", import.meta.url), "utf8"));
  report.status.mirrorSessions = [];
  report.status.dockIntegration.openWindowCount = 0;
  report.status.dockIntegration.badgeLabel = "R";
  report.status.dockIntegration.canBringWindowsAppsForward = false;
  report.status.dockIntegration.canReconnectPreviousApps = true;
  report.status.dockIntegration.canRestorePreviousApps = true;
  report.status.menuBarIntegration.statusTitle = "Notepad Ready";
  report.status.menuBarIntegration.symbolName = "arrow.counterclockwise.circle.fill";
  report.status.menuBarIntegration.primaryActionId = "windowsApps.restorePrevious";
  report.status.menuBarIntegration.primaryActionTitle = "Restore Notepad";
  report.status.menuBarIntegration.canBringWindowsAppsForward = false;
  report.status.menuBarIntegration.canReconnectPreviousApps = true;
  report.status.menuBarIntegration.canRestorePreviousApps = true;
  report.status.macWindowIntegration.hidesLauncherWhenMirroring = false;
  report.status.macWindowIntegration.mirroredWindowCount = 0;
  report.status.macWindowIntegration.foregroundableWindowCount = 0;
  delete report.status.macWindowIntegration.foregroundWindowId;
  delete report.status.macWindowIntegration.foregroundWindowTitle;
  report.status.macWindowIntegration.pendingFrameWindowCount = 0;
  report.status.launcherVisibility.shouldHideMainWindow = false;
  report.status.launcherVisibility.recommendedAction = "show-launcher-or-restore-apps";
  report.status.visibleSurfacePolicy.primarySurface = "launcher";
  report.status.visibleSurfacePolicy.expectedVisibleSurfaceCount = 1;
  report.status.visibleSurfacePolicy.shouldHideLauncher = false;
  report.status.quietRuntime.openWindowCount = 0;
  report.status.actions.find((action) => action.id === "windowsApps.restorePrevious").isAvailable = true;
  report.status.actions.find((action) => action.id === "windowsApps.reconnectRestore").isAvailable = true;
  setReleaseGateStep(report, "closeOrRestore", {
    state: "ready",
    isPassing: true,
    nextActionCommand: "veil-vmctl app-runtime-action --json --action reconnect-restore"
  });

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
