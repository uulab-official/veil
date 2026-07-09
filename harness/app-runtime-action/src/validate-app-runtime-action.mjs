import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { validateAppRuntimeStatus } from "../../app-runtime-status/src/validate-app-runtime-status.mjs";
import { validateGuestAgentWait } from "../../guest-agent-wait/src/validate-guest-agent-wait.mjs";

const VALID_ACTIONS = new Set(["launch", "fulfill-pending", "focus", "close", "close-all", "restore", "reconnect-restore", "bring-forward", "recover-display", "wait-agent", "quiet-when-idle", "stop-runtime", "clipboard", "type-text", "click", "proof-recommended"]);
const VALID_CONNECTION_MODES = new Set(["agent", "demo"]);
const VALID_CONSOLE_PREVIEW_STATES = new Set(["fresh", "stale", "unavailable"]);

export function validateAppRuntimeAction(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("App runtime action report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "windowsAppRuntimeAction") {
    throw new TypeError(`Unsupported app runtime action kind: ${report.kind}`);
  }

  requireString(report.action, "action");
  if (!VALID_ACTIONS.has(report.action)) {
    throw new TypeError(`Unsupported app runtime action: ${report.action}`);
  }

  requireString(report.requestedAt, "requestedAt");
  if (Number.isNaN(Date.parse(report.requestedAt))) {
    throw new TypeError("requestedAt must be an ISO date.");
  }

  requireString(report.endpoint, "endpoint");
  requireString(report.connectionMode, "connectionMode");
  if (!VALID_CONNECTION_MODES.has(report.connectionMode)) {
    throw new TypeError(`Unsupported connection mode: ${report.connectionMode}`);
  }

  requireBoolean(report.accepted, "accepted");
  validateAppRuntimeStatus(report.status);
  validateActionLaunchPlan(report);
  validateActionProofPlan(report);

  if (!Array.isArray(report.restoredWindows)) {
    throw new TypeError("restoredWindows must be an array.");
  }

  if (report.action !== "stop-runtime" && report.runtimeStop !== undefined && report.runtimeStop !== null) {
    throw new TypeError("runtimeStop is only allowed for stop-runtime actions.");
  }

  if (report.action !== "proof-recommended" && report.proof !== undefined && report.proof !== null) {
    throw new TypeError("proof is only allowed for proof-recommended actions.");
  }

  if (report.action !== "recover-display" && report.displayRecovery !== undefined && report.displayRecovery !== null) {
    throw new TypeError("displayRecovery is only allowed for recover-display actions.");
  }

  if (report.action !== "wait-agent" && report.agentWait !== undefined && report.agentWait !== null) {
    throw new TypeError("agentWait is only allowed for wait-agent actions.");
  }

  switch (report.action) {
    case "launch":
      validateLaunchAction(report);
      break;
    case "fulfill-pending":
      validateFulfillPendingAction(report);
      break;
    case "focus":
      validateFocusAction(report);
      break;
    case "close":
      validateCloseAction(report);
      break;
    case "close-all":
      validateCloseAllAction(report);
      break;
    case "restore":
      validateRestoreAction(report);
      break;
    case "reconnect-restore":
      validateReconnectRestoreAction(report);
      break;
    case "bring-forward":
      validateBringForwardAction(report);
      break;
    case "recover-display":
      validateRecoverDisplayAction(report);
      break;
    case "wait-agent":
      validateWaitAgentAction(report);
      break;
    case "quiet-when-idle":
      validateQuietWhenIdleAction(report);
      break;
    case "stop-runtime":
      validateStopRuntimeAction(report);
      break;
    case "clipboard":
      validateClipboardAction(report);
      break;
    case "type-text":
      validateTypeTextAction(report);
      break;
    case "click":
      validateClickAction(report);
      break;
    case "proof-recommended":
      validateProofRecommendedAction(report);
      break;
  }

  validateStringArray(report.nextActions, "nextActions");
  validateGuestToolsMediaRebuildNextActions(report);
  validateProofNextActions(report);
  return report;
}

function validateGuestToolsMediaRebuildNextActions(report) {
  if (!report.status.localRuntime.requiresGuestToolsMediaRebuild) {
    return;
  }

  const joinedActions = report.nextActions.join("\n");
  if (!joinedActions.includes("app-runtime-action --json --action stop-runtime")) {
    throw new TypeError("stale guest tools media actions must tell the operator to stop Windows first.");
  }
  if (!joinedActions.includes("veil-vmctl prepare --installer")) {
    throw new TypeError("stale guest tools media actions must include the media rebuild command.");
  }
  if (joinedActions.includes("qemu-install-agent")) {
    throw new TypeError("stale guest tools media actions must not recommend guest-agent repair before media rebuild.");
  }
}

function validateWaitAgentAction(report) {
  if (!report.agentWait || typeof report.agentWait !== "object" || Array.isArray(report.agentWait)) {
    throw new TypeError("wait-agent actions must include agentWait.");
  }

  validateGuestAgentWait(report.agentWait);
  if (report.accepted !== (report.agentWait.status === "connected")) {
    throw new TypeError("wait-agent accepted must match agentWait connected status.");
  }

  if (report.agentWait.endpoint !== report.status.guestAgentDiagnostics.endpoint) {
    throw new TypeError("wait-agent endpoint must match status.guestAgentDiagnostics.endpoint.");
  }
}

function validateRecoverDisplayAction(report) {
  const recovery = report.displayRecovery;
  if (!recovery || typeof recovery !== "object" || Array.isArray(recovery)) {
    throw new TypeError("recover-display actions must include displayRecovery.");
  }

  requireString(recovery.kind, "displayRecovery.kind");
  if (recovery.kind !== "windowsAppRuntimeDisplayRecovery") {
    throw new TypeError("Unsupported displayRecovery.kind.");
  }

  requireString(recovery.command, "displayRecovery.command");
  if (recovery.command !== "veil-vmctl qemu-capture --json") {
    throw new TypeError("displayRecovery.command must point at qemu-capture.");
  }

  validateOptionalPreviewStatus(recovery.beforePreviewStatus, "displayRecovery.beforePreviewStatus");
  validateOptionalPreviewStatus(recovery.afterPreviewStatus, "displayRecovery.afterPreviewStatus");

  if (recovery.beforeScreenshotPath !== undefined) {
    requireString(recovery.beforeScreenshotPath, "displayRecovery.beforeScreenshotPath");
  }
  if (recovery.afterScreenshotPath !== undefined) {
    requireString(recovery.afterScreenshotPath, "displayRecovery.afterScreenshotPath");
  }
  if (recovery.error !== undefined) {
    requireString(recovery.error, "displayRecovery.error");
  }

  const hasCapture = recovery.capture !== undefined && recovery.capture !== null;
  if (hasCapture) {
    validateConsoleCapture(recovery.capture);
  }

  if (report.accepted !== (hasCapture && recovery.afterPreviewStatus === "fresh")) {
    throw new TypeError("recover-display accepted must require a capture and fresh afterPreviewStatus.");
  }

  const recoverAction = report.status.actions.find((action) => action.id === "runtime.recoverDisplay");
  if (!recoverAction) {
    throw new TypeError("recover-display status must include runtime.recoverDisplay.");
  }

  if (!report.accepted && recovery.error === undefined && report.status.localRuntime.recommendedRecoveryCommand === undefined) {
    throw new TypeError("rejected recover-display actions must expose either a recovery error or continued recovery command.");
  }
}

function validateProofRecommendedAction(report) {
  if (!report.accepted) {
    if (report.proof !== undefined && report.proof !== null) {
      throw new TypeError("rejected proof-recommended actions cannot include proof.");
    }
    return;
  }

  validateRecommendedProofRun(report.proof, report);
}

function validateOptionalPreviewStatus(value, fieldName) {
  if (value === undefined || value === null) {
    return;
  }
  requireString(value, fieldName);
  if (!VALID_CONSOLE_PREVIEW_STATES.has(value)) {
    throw new TypeError(`Unsupported ${fieldName}: ${value}`);
  }
}

function validateConsoleCapture(capture) {
  if (!capture || typeof capture !== "object" || Array.isArray(capture)) {
    throw new TypeError("displayRecovery.capture must be an object.");
  }

  requireString(capture.kind, "displayRecovery.capture.kind");
  if (capture.kind !== "qemuConsoleCapture") {
    throw new TypeError("Unsupported displayRecovery.capture.kind.");
  }
  requireString(capture.monitorSocketPath, "displayRecovery.capture.monitorSocketPath");
  requireString(capture.consoleScreenshotPath, "displayRecovery.capture.consoleScreenshotPath");
  requireString(capture.capturedAt, "displayRecovery.capture.capturedAt");
  if (Number.isNaN(Date.parse(capture.capturedAt))) {
    throw new TypeError("displayRecovery.capture.capturedAt must be an ISO date.");
  }
}

function validateFulfillPendingAction(report) {
  if (report.launchPlan === undefined) {
    throw new TypeError("fulfill-pending actions must include top-level launchPlan.");
  }

  if (!report.accepted) {
    if (report.launch !== undefined && report.launch !== null) {
      throw new TypeError("rejected fulfill-pending actions cannot include launch.");
    }

    if (report.window !== undefined && report.window !== null) {
      throw new TypeError("rejected fulfill-pending actions cannot include window.");
    }

    return;
  }

  requireString(report.appId, "appId");
  requireString(report.windowId, "windowId");
  validateLaunchResponse(report.launch);
  validateWindow(report.window);

  if (report.window.appId !== report.appId) {
    throw new TypeError("fulfill-pending window appId must match report.appId.");
  }

  if (report.window.windowId !== report.windowId) {
    throw new TypeError("fulfill-pending window must match report.windowId.");
  }

  requireForegroundWindowIdentity(report, report.window.windowId, report.window.title, "accepted fulfill-pending actions");

  if (report.status.pendingLaunch.isQueued) {
    throw new TypeError("accepted fulfill-pending actions must clear status.pendingLaunch.");
  }

  if (report.status.pendingLaunchAppId !== undefined) {
    throw new TypeError("accepted fulfill-pending actions must clear status.pendingLaunchAppId.");
  }

  requireForegroundableMacWindow(report, "accepted fulfill-pending actions");
}

function validateQuietWhenIdleAction(report) {
  validateQuietRuntime(report.quietRuntime, "quietRuntime");

  if (JSON.stringify(report.quietRuntime) !== JSON.stringify(report.status.quietRuntime)) {
    throw new TypeError("quietRuntime action status must match report.status.quietRuntime.");
  }

  if (report.accepted !== report.quietRuntime.canQuietRuntime) {
    throw new TypeError("quiet-when-idle accepted must match quietRuntime.canQuietRuntime.");
  }
}

function validateStopRuntimeAction(report) {
  validateQuietRuntime(report.quietRuntime, "quietRuntime");

  if (JSON.stringify(report.quietRuntime) !== JSON.stringify(report.status.quietRuntime)) {
    throw new TypeError("stop-runtime action status must match report.status.quietRuntime.");
  }

  if (!report.accepted) {
    if (report.runtimeStop !== undefined && report.runtimeStop !== null) {
      throw new TypeError("rejected stop-runtime actions cannot include runtimeStop.");
    }
    return;
  }

  if (!report.quietRuntime.canQuietRuntime) {
    throw new TypeError("accepted stop-runtime actions require quietRuntime.canQuietRuntime.");
  }

  validateRuntimeStop(report.runtimeStop);
}

function validateLaunchAction(report) {
  requireString(report.appId, "appId");
  if (report.launchPlan === undefined) {
    throw new TypeError("launch actions must include top-level launchPlan.");
  }

  if (!report.accepted) {
    if (report.launch !== undefined && report.launch !== null) {
      throw new TypeError("rejected launch actions cannot include launch.");
    }

    if (report.window !== undefined && report.window !== null) {
      throw new TypeError("rejected launch actions cannot include window.");
    }

    if (
      report.status.launchPlan.canRequestSelectedAppLaunch &&
      report.status.launchPlan.requiresRuntimeStart &&
      report.status.launchPlan.pendingLaunchAppId !== report.appId
    ) {
      throw new TypeError("rejected app-first launch actions must queue pendingLaunchAppId for the requested app.");
    }

    if (report.pendingLaunchAppId !== report.appId) {
      throw new TypeError("rejected app-first launch actions must expose pendingLaunchAppId for the requested app.");
    }

    const requiresGuestToolsMediaRebuild = report.status.localRuntime.requiresGuestToolsMediaRebuild === true;
    if (requiresGuestToolsMediaRebuild) {
      if (report.status.localRuntime.recommendedPowerDownCommand === undefined
        || report.status.localRuntime.recommendedMediaRebuildCommand === undefined) {
        throw new TypeError("rejected app-first launch actions with stale guest tools media must expose powerdown and rebuild commands.");
      }
      return;
    }

    if (
      report.launchPlan.recommendedStartCommand === undefined
      && report.launchPlan.recommendedRepairCommand === undefined
    ) {
      throw new TypeError("rejected app-first launch actions must expose launchPlan.recommendedStartCommand or launchPlan.recommendedRepairCommand.");
    }

    if (report.launchPlan.requiresRuntimeStart && report.launchPlan.recommendedStartCommand === undefined) {
      throw new TypeError("rejected app-first launch actions that require runtime start must expose launchPlan.recommendedStartCommand.");
    }

    if (!report.launchPlan.requiresRuntimeStart && report.launchPlan.recommendedRepairCommand === undefined) {
      throw new TypeError("rejected app-first launch actions for running runtimes must expose launchPlan.recommendedRepairCommand.");
    }

    if (report.launchPlan.recommendedWaitCommand === undefined) {
      throw new TypeError("rejected app-first launch actions must expose launchPlan.recommendedWaitCommand.");
    }

    if (report.launchPlan.recommendedLaunchCommand === undefined) {
      throw new TypeError("rejected app-first launch actions must expose launchPlan.recommendedLaunchCommand.");
    }

    return;
  }

  requireString(report.windowId, "windowId");
  validateLaunchResponse(report.launch);
  validateWindow(report.window);
  if (report.window.windowId !== report.windowId) {
    throw new TypeError("launch window must match report.windowId.");
  }

  requireForegroundWindowIdentity(report, report.window.windowId, report.window.title, "accepted launch actions");
  requireForegroundableMacWindow(report, "accepted launch actions");
}

function validateActionLaunchPlan(report) {
  if (report.pendingLaunchAppId !== undefined) {
    requireString(report.pendingLaunchAppId, "pendingLaunchAppId");
    if (report.pendingLaunchAppId !== report.status.pendingLaunchAppId) {
      throw new TypeError("pendingLaunchAppId must match report.status.pendingLaunchAppId.");
    }
  }

  if (report.launchPlan === undefined) {
    return;
  }

  if (!report.launchPlan || typeof report.launchPlan !== "object" || Array.isArray(report.launchPlan)) {
    throw new TypeError("launchPlan must be an object when present.");
  }

  if (JSON.stringify(report.launchPlan) !== JSON.stringify(report.status.launchPlan)) {
    throw new TypeError("top-level launchPlan must match report.status.launchPlan.");
  }
}

function validateActionProofPlan(report) {
  if (!report.proofPlan || typeof report.proofPlan !== "object" || Array.isArray(report.proofPlan)) {
    throw new TypeError("proofPlan must be an object.");
  }

  if (JSON.stringify(report.proofPlan) !== JSON.stringify(report.status.proofPlan)) {
    throw new TypeError("top-level proofPlan must match report.status.proofPlan.");
  }
}

function validateRecommendedProofRun(proof, report) {
  if (!proof || typeof proof !== "object" || Array.isArray(proof)) {
    throw new TypeError("proof-recommended actions must include proof.");
  }

  requireString(proof.kind, "proof.kind");
  if (proof.kind !== "windowsAppRuntimeRecommendedProofRun") {
    throw new TypeError("Unsupported proof.kind.");
  }

  requireString(proof.proofKind, "proof.proofKind");
  requireString(proof.command, "proof.command");
  requireString(proof.appId, "proof.appId");
  requireString(proof.status, "proof.status");
  if (!["proved", "unavailable"].includes(proof.status)) {
    throw new TypeError("proof.status must be proved or unavailable.");
  }

  if (proof.proofKind !== report.proofPlan.recommendedProofKind) {
    throw new TypeError("proof.proofKind must match proofPlan.recommendedProofKind.");
  }

  if (proof.command !== report.proofPlan.recommendedProofCommand) {
    throw new TypeError("proof.command must match proofPlan.recommendedProofCommand.");
  }

  if (proof.appId !== report.proofPlan.selectedAppId) {
    throw new TypeError("proof.appId must match proofPlan.selectedAppId.");
  }

  if (report.appId !== proof.appId) {
    throw new TypeError("proof-recommended appId must match proof.appId.");
  }

  if (proof.status !== "proved") {
    throw new TypeError("accepted proof-recommended actions must prove the recommended gate.");
  }

  requireString(proof.windowId, "proof.windowId");
  requireString(proof.windowTitle, "proof.windowTitle");
  requireNumber(proof.frameSequence, "proof.frameSequence");
  validateStringArray(proof.nextActions, "proof.nextActions");

  if (report.windowId !== proof.windowId) {
    throw new TypeError("proof-recommended windowId must match proof.windowId.");
  }

  if (report.foregroundWindowId !== proof.windowId) {
    throw new TypeError("accepted proof-recommended actions must report the proof window as foreground.");
  }

  if (report.foregroundWindowTitle !== proof.windowTitle) {
    throw new TypeError("accepted proof-recommended actions must report the proof window title.");
  }

  if (proof.proofKind === "coherence" || proof.proofKind === "mvp") {
    requireNumber(proof.inputEventCount, "proof.inputEventCount");
    requireNumber(proof.clipboardTextByteCount, "proof.clipboardTextByteCount");
  }
}

function validateProofNextActions(report) {
  if (!report.accepted) {
    return;
  }

  if (!["launch", "fulfill-pending", "focus", "restore", "reconnect-restore", "bring-forward", "clipboard"].includes(report.action)) {
    return;
  }

  const command = report.proofPlan.recommendedProofCommand;
  if (command === undefined) {
    return;
  }

  if (!report.nextActions.some((action) => action.includes(command))) {
    throw new TypeError("accepted app-runtime actions with an available proof command must include that command in nextActions.");
  }
}

function validateFocusAction(report) {
  requireString(report.windowId, "windowId");
  if (!report.accepted) {
    return;
  }

  validateBooleanResponse(report.focus, "window.focus.response");
  if (report.focus.windowId !== report.windowId) {
    throw new TypeError("focus response must match report.windowId.");
  }

  requireString(report.foregroundWindowId, "foregroundWindowId");
  if (report.foregroundWindowId !== report.windowId) {
    throw new TypeError("accepted focus actions must report the foreground Windows app window id.");
  }
}

function validateCloseAction(report) {
  requireString(report.windowId, "windowId");
  if (!report.accepted) {
    return;
  }

  validateBooleanResponse(report.close, "window.close.response");
  if (report.close.windowId !== report.windowId) {
    throw new TypeError("close response must match report.windowId.");
  }
}

function validateCloseAllAction(report) {
  if (!Array.isArray(report.closedWindows)) {
    throw new TypeError("closedWindows must be an array.");
  }

  if (!report.accepted) {
    if (report.closedWindows.length !== 0) {
      throw new TypeError("rejected close-all actions cannot include closedWindows.");
    }
    return;
  }

  if (report.closedWindows.length === 0) {
    throw new TypeError("accepted close-all actions must include closedWindows.");
  }

  for (const response of report.closedWindows) {
    validateBooleanResponse(response, "window.close.response");
    if (!response.accepted) {
      throw new TypeError("accepted close-all actions cannot include rejected close responses.");
    }
  }

  if (report.status.mirrorSessions.length !== 0) {
    throw new TypeError("accepted close-all actions must leave no mirrored Windows app windows.");
  }

  if (report.status.dockIntegration.openWindowCount !== 0 || report.status.dockIntegration.canBringWindowsAppsForward) {
    throw new TypeError("accepted close-all actions must clear Dock open-window state.");
  }

  const closeAllAction = report.status.actions.find((action) => action.id === "windowsApps.closeAll");
  if (!closeAllAction || closeAllAction.isAvailable) {
    throw new TypeError("accepted close-all actions must make windowsApps.closeAll unavailable.");
  }
}

function validateRestoreAction(report) {
  validateRestoredWindowsAction(report, "restore");
}

function validateReconnectRestoreAction(report) {
  validateRestoredWindowsAction(report, "reconnect-restore");

  const reconnectRestoreAction = report.status.actions.find((action) => action.id === "windowsApps.reconnectRestore");
  if (!reconnectRestoreAction) {
    throw new TypeError("reconnect-restore status must include windowsApps.reconnectRestore.");
  }
}

function validateRestoredWindowsAction(report, actionName) {
  validateStringArray(report.restoreRequestedAppIds, "restoreRequestedAppIds");

  if (!report.accepted) {
    if (report.restoredWindows.length !== 0) {
      throw new TypeError("rejected restore actions cannot include restored windows.");
    }
    return;
  }

  if (report.restoreRequestedAppIds.length === 0) {
    throw new TypeError(`accepted ${actionName} actions must include restoreRequestedAppIds.`);
  }

  if (report.restoredWindows.length === 0) {
    throw new TypeError(`accepted ${actionName} actions must include restoredWindows.`);
  }

  const restoredAppIds = report.restoredWindows.map((window) => window.appId);
  if (JSON.stringify(restoredAppIds) !== JSON.stringify(report.restoreRequestedAppIds)) {
    throw new TypeError("restoredWindows appIds must match restoreRequestedAppIds order.");
  }

  const mirrorWindowIds = new Set(report.status.mirrorSessions.map((session) => session.windowId));
  for (const window of report.restoredWindows) {
    validateWindow(window);
    if (!mirrorWindowIds.has(window.windowId)) {
      throw new TypeError("restoredWindows must be present in status.mirrorSessions.");
    }
  }

  const foregroundWindow = report.restoredWindows.at(-1);
  requireForegroundWindowIdentity(report, foregroundWindow.windowId, foregroundWindow.title, `accepted ${actionName} actions`);

  if (!report.status.dockIntegration.canBringWindowsAppsForward) {
    throw new TypeError(`accepted ${actionName} actions must leave Windows app windows available to bring forward.`);
  }

  if (report.status.dockIntegration.canRestorePreviousApps) {
    throw new TypeError(`accepted ${actionName} actions should consume the immediate restore availability while windows are open.`);
  }

  requireForegroundableMacWindow(report, `accepted ${actionName} actions`);
}

function validateBringForwardAction(report) {
  validateStringArray(report.broughtForwardWindowIds, "broughtForwardWindowIds");

  if (report.accepted !== report.status.dockIntegration.canBringWindowsAppsForward) {
    throw new TypeError("bring-forward accepted must match status.dockIntegration.canBringWindowsAppsForward.");
  }

  if (!report.accepted) {
    if (report.broughtForwardWindowIds.length !== 0) {
      throw new TypeError("rejected bring-forward actions cannot include broughtForwardWindowIds.");
    }
    return;
  }

  const mirrorWindowIds = report.status.mirrorSessions.map((session) => session.windowId);
  if (report.broughtForwardWindowIds.length === 0) {
    throw new TypeError("accepted bring-forward actions must include broughtForwardWindowIds.");
  }

  if (JSON.stringify(report.broughtForwardWindowIds) !== JSON.stringify(mirrorWindowIds)) {
    throw new TypeError("broughtForwardWindowIds must match status.mirrorSessions order.");
  }

  requireString(report.windowId, "windowId");
  if (report.windowId !== report.broughtForwardWindowIds.at(-1)) {
    throw new TypeError("bring-forward windowId must identify the foreground mirror session.");
  }

  const foregroundSession = report.status.mirrorSessions.at(-1);
  requireForegroundWindowIdentity(report, foregroundSession.windowId, foregroundSession.title, "accepted bring-forward actions");

  if (report.focus !== undefined && report.focus !== null) {
    validateBooleanResponse(report.focus, "window.focus.response");
    if (report.focus.windowId !== report.windowId) {
      throw new TypeError("bring-forward focus response must match report.windowId.");
    }
  }
}

function requireForegroundableMacWindow(report, actionName) {
  if (!report.status.dockIntegration.canBringWindowsAppsForward) {
    throw new TypeError(`${actionName} must leave Windows app windows available to bring forward.`);
  }

  if (report.status.macWindowIntegration.foregroundableWindowCount < 1) {
    throw new TypeError(`${actionName} must leave at least one foregroundable macOS app window.`);
  }
}

function requireForegroundWindowIdentity(report, expectedWindowId, expectedTitle, actionName) {
  requireString(report.foregroundWindowId, "foregroundWindowId");
  requireString(report.foregroundWindowTitle, "foregroundWindowTitle");
  if (report.foregroundWindowId !== expectedWindowId) {
    throw new TypeError(`${actionName} must report the foreground Windows app window id.`);
  }
  if (report.foregroundWindowTitle !== expectedTitle) {
    throw new TypeError(`${actionName} must report the foreground Windows app window title.`);
  }

  if (report.status.macWindowIntegration.foregroundWindowId !== expectedWindowId) {
    throw new TypeError(`${actionName} status must report the same foreground Windows app window id.`);
  }
}

function validateClipboardAction(report) {
  if (!report.accepted && report.clipboard === undefined) {
    return;
  }

  validateClipboard(report.clipboard);
}

function validateTypeTextAction(report) {
  requireString(report.windowId, "windowId");
  if (!Array.isArray(report.keyInputs)) {
    throw new TypeError("keyInputs must be an array.");
  }

  if (report.typedTextCharacterCount !== undefined) {
    requireNonNegativeInteger(report.typedTextCharacterCount, "typedTextCharacterCount");
  }

  if (!report.accepted) {
    return;
  }

  if (report.keyInputs.length === 0) {
    throw new TypeError("accepted type-text actions must include keyInputs.");
  }

  for (const input of report.keyInputs) {
    validateKeyInput(input);
  }
}

function validateClickAction(report) {
  requireString(report.windowId, "windowId");
  if (!Array.isArray(report.mouseInputs)) {
    throw new TypeError("mouseInputs must be an array.");
  }

  if (!report.accepted) {
    return;
  }

  if (report.mouseInputs.length !== 2) {
    throw new TypeError("accepted click actions must include leftDown and leftUp mouseInputs.");
  }

  for (const input of report.mouseInputs) {
    validateMouseInput(input);
  }

  if (report.mouseInputs[0].event !== "leftDown" || report.mouseInputs[1].event !== "leftUp") {
    throw new TypeError("click mouseInputs must be ordered leftDown then leftUp.");
  }
}

function validateLaunchResponse(launch) {
  if (!launch || typeof launch !== "object" || Array.isArray(launch)) {
    throw new TypeError("launch must be an object for accepted launch actions.");
  }

  if (launch.type !== "app.launch.response") {
    throw new TypeError("launch must use type app.launch.response.");
  }
  requireString(launch.requestId, "launch.requestId");
  requireBoolean(launch.accepted, "launch.accepted");
  requirePositiveInteger(launch.processId, "launch.processId");
}

function validateQuietRuntime(quietRuntime, fieldName) {
  if (!quietRuntime || typeof quietRuntime !== "object" || Array.isArray(quietRuntime)) {
    throw new TypeError(`${fieldName} must be an object.`);
  }

  requireBoolean(quietRuntime.isEnabled, `${fieldName}.isEnabled`);
  requireBoolean(quietRuntime.hasOpenedAppWindowThisSession, `${fieldName}.hasOpenedAppWindowThisSession`);
  requireNonNegativeInteger(quietRuntime.openWindowCount, `${fieldName}.openWindowCount`);
  requireBoolean(quietRuntime.canQuietRuntime, `${fieldName}.canQuietRuntime`);
  requireBoolean(quietRuntime.willQuietAutomatically, `${fieldName}.willQuietAutomatically`);
  requireNonNegativeInteger(quietRuntime.automaticQuietDelaySeconds, `${fieldName}.automaticQuietDelaySeconds`);
  requireString(quietRuntime.recommendedAction, `${fieldName}.recommendedAction`);
  requireString(quietRuntime.reason, `${fieldName}.reason`);

  if (quietRuntime.recommendedStopCommand !== undefined) {
    requireString(quietRuntime.recommendedStopCommand, `${fieldName}.recommendedStopCommand`);
  }

  if (quietRuntime.willQuietAutomatically && !quietRuntime.canQuietRuntime) {
    throw new TypeError(`${fieldName}.willQuietAutomatically requires ${fieldName}.canQuietRuntime.`);
  }

  if (quietRuntime.canQuietRuntime && quietRuntime.recommendedStopCommand === undefined) {
    throw new TypeError(`${fieldName}.canQuietRuntime requires ${fieldName}.recommendedStopCommand.`);
  }

  if (!quietRuntime.canQuietRuntime && quietRuntime.recommendedStopCommand !== undefined) {
    throw new TypeError(`${fieldName}.recommendedStopCommand is only allowed when ${fieldName}.canQuietRuntime is true.`);
  }
}

function validateRuntimeStop(runtimeStop) {
  if (!runtimeStop || typeof runtimeStop !== "object" || Array.isArray(runtimeStop)) {
    throw new TypeError("runtimeStop must be an object for accepted stop-runtime actions.");
  }

  requireString(runtimeStop.state, "runtimeStop.state");
  if (runtimeStop.state !== "stopped") {
    throw new TypeError("accepted stop-runtime actions must report runtimeStop.state stopped.");
  }

  requireBoolean(runtimeStop.virtualizationAvailable, "runtimeStop.virtualizationAvailable");
  requireString(runtimeStop.architecture, "runtimeStop.architecture");
  requireBoolean(runtimeStop.minimumOSSupported, "runtimeStop.minimumOSSupported");
  requireBoolean(runtimeStop.bootReady, "runtimeStop.bootReady");
  requireBoolean(runtimeStop.windowsInstalled, "runtimeStop.windowsInstalled");
  requireString(runtimeStop.detail, "runtimeStop.detail");
}

function validateClipboard(clipboard) {
  if (!clipboard || typeof clipboard !== "object" || Array.isArray(clipboard)) {
    throw new TypeError("clipboard must be an object when present.");
  }

  if (clipboard.type !== "clipboard.text.set") {
    throw new TypeError("clipboard must use type clipboard.text.set.");
  }
  requireString(clipboard.requestId, "clipboard.requestId");
  requireString(clipboard.origin, "clipboard.origin");
  if (clipboard.origin !== "host") {
    throw new TypeError("app runtime clipboard actions must use host origin.");
  }
  requirePositiveInteger(clipboard.sequence, "clipboard.sequence");
  requireString(clipboard.text, "clipboard.text");
}

function validateKeyInput(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new TypeError("key input entries must be objects.");
  }

  if (input.type !== "input.key") {
    throw new TypeError("key input entries must use type input.key.");
  }
  requireString(input.windowId, "input.windowId");
  requireString(input.event, "input.event");
  if (!["keyDown", "keyUp"].includes(input.event)) {
    throw new TypeError(`Unsupported key input event: ${input.event}`);
  }
  requireString(input.key, "input.key");
  requirePositiveInteger(input.windowsVirtualKey, "input.windowsVirtualKey");
  if (!Array.isArray(input.modifiers) || input.modifiers.some((modifier) => typeof modifier !== "string")) {
    throw new TypeError("input.modifiers must be an array of strings.");
  }
}

function validateMouseInput(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new TypeError("mouse input entries must be objects.");
  }

  if (input.type !== "input.mouse") {
    throw new TypeError("mouse input entries must use type input.mouse.");
  }
  requireString(input.windowId, "input.windowId");
  requireString(input.event, "input.event");
  if (!["leftDown", "leftUp", "rightDown", "rightUp", "move", "scroll"].includes(input.event)) {
    throw new TypeError(`Unsupported mouse input event: ${input.event}`);
  }
  requireNonNegativeInteger(input.x, "input.x");
  requireNonNegativeInteger(input.y, "input.y");
  if (!Array.isArray(input.modifiers) || input.modifiers.some((modifier) => typeof modifier !== "string")) {
    throw new TypeError("input.modifiers must be an array of strings.");
  }
}

function validateBooleanResponse(response, type) {
  if (!response || typeof response !== "object" || Array.isArray(response)) {
    throw new TypeError(`${type} response must be an object.`);
  }

  if (response.type !== type) {
    throw new TypeError(`response must use type ${type}.`);
  }
  requireString(response.requestId, "response.requestId");
  requireString(response.windowId, "response.windowId");
  requireBoolean(response.accepted, "response.accepted");
}

function validateWindow(window) {
  if (!window || typeof window !== "object" || Array.isArray(window)) {
    throw new TypeError("window must be an object.");
  }

  if (window.type !== "window.created") {
    throw new TypeError("window must use type window.created.");
  }
  requireString(window.windowId, "window.windowId");
  requirePositiveInteger(window.processId, "window.processId");
  requireString(window.appId, "window.appId");
  requireString(window.title, "window.title");
  requireString(window.state, "window.state");
  requireBoolean(window.focused, "window.focused");
}

function validateStringArray(value, fieldName) {
  if (!Array.isArray(value)) {
    throw new TypeError(`${fieldName} must be an array.`);
  }

  for (const item of value) {
    requireString(item, fieldName);
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`App runtime action field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`App runtime action field '${fieldName}' must be boolean.`);
  }
}

function requireNumber(value, fieldName) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`App runtime action field '${fieldName}' must be number.`);
  }
}

function requirePositiveInteger(value, fieldName) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new TypeError(`App runtime action field '${fieldName}' must be a positive integer.`);
  }
}

function requireNonNegativeInteger(value, fieldName) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`App runtime action field '${fieldName}' must be a non-negative integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected app runtime action JSON on stdin.");
  }

  validateAppRuntimeAction(JSON.parse(input));
  process.stdout.write("app runtime action valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
