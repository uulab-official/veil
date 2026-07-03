import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { validateAppRuntimeStatus } from "../../app-runtime-status/src/validate-app-runtime-status.mjs";

const VALID_ACTIONS = new Set(["launch", "focus", "close", "close-all", "restore", "bring-forward", "quiet-when-idle", "clipboard", "type-text", "click"]);
const VALID_CONNECTION_MODES = new Set(["agent", "demo"]);

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

  if (!Array.isArray(report.restoredWindows)) {
    throw new TypeError("restoredWindows must be an array.");
  }

  switch (report.action) {
    case "launch":
      validateLaunchAction(report);
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
    case "bring-forward":
      validateBringForwardAction(report);
      break;
    case "quiet-when-idle":
      validateQuietWhenIdleAction(report);
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
  }

  validateStringArray(report.nextActions, "nextActions");
  return report;
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

    if (report.launchPlan.recommendedStartCommand === undefined) {
      throw new TypeError("rejected app-first launch actions must expose launchPlan.recommendedStartCommand.");
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

function validateFocusAction(report) {
  requireString(report.windowId, "windowId");
  if (!report.accepted) {
    return;
  }

  validateBooleanResponse(report.focus, "window.focus.response");
  if (report.focus.windowId !== report.windowId) {
    throw new TypeError("focus response must match report.windowId.");
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
  validateStringArray(report.restoreRequestedAppIds, "restoreRequestedAppIds");

  if (!report.accepted) {
    if (report.restoredWindows.length !== 0) {
      throw new TypeError("rejected restore actions cannot include restored windows.");
    }
    return;
  }

  if (report.restoreRequestedAppIds.length === 0) {
    throw new TypeError("accepted restore actions must include restoreRequestedAppIds.");
  }

  if (report.restoredWindows.length === 0) {
    throw new TypeError("accepted restore actions must include restoredWindows.");
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

  if (!report.status.dockIntegration.canBringWindowsAppsForward) {
    throw new TypeError("accepted restore actions must leave Windows app windows available to bring forward.");
  }

  if (report.status.dockIntegration.canRestorePreviousApps) {
    throw new TypeError("accepted restore actions should consume the immediate restore availability while windows are open.");
  }
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

  if (report.focus !== undefined && report.focus !== null) {
    validateBooleanResponse(report.focus, "window.focus.response");
    if (report.focus.windowId !== report.windowId) {
      throw new TypeError("bring-forward focus response must match report.windowId.");
    }
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
