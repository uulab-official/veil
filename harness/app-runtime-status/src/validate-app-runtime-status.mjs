import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_CONNECTION_MODES = new Set(["agent", "demo"]);
const VALID_PHASES = new Set(["idle", "loading", "connected", "launching", "failed"]);
const VALID_CAPTURE_STATES = new Set(["unavailable", "pending", "streaming"]);

export function validateAppRuntimeStatus(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("App runtime status report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "windowsAppRuntimeStatus") {
    throw new TypeError(`Unsupported app runtime status kind: ${report.kind}`);
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  requireString(report.phase, "phase");
  if (!VALID_PHASES.has(report.phase)) {
    throw new TypeError(`Unsupported app runtime phase: ${report.phase}`);
  }

  validateConnection(report.connection);
  validateApps(report.apps);
  validateMirrorSessions(report.mirrorSessions);
  validateStringArray(report.restorableAppIds, "restorableAppIds");
  validateDockIntegration(report.dockIntegration, report.mirrorSessions);
  validateMacWindowIntegration(report.macWindowIntegration, report.mirrorSessions, report.connection);
  validateQuietRuntime(report.quietRuntime, report.mirrorSessions);
  validateLaunchPlan(report.launchPlan, report);
  validateActions(report.actions, report.launchPlan);

  if (report.selectedAppId !== undefined) {
    requireString(report.selectedAppId, "selectedAppId");
  }

  if (report.pendingLaunchAppId !== undefined) {
    requireString(report.pendingLaunchAppId, "pendingLaunchAppId");
  }

  return report;
}

function validateConnection(connection) {
  if (!connection || typeof connection !== "object" || Array.isArray(connection)) {
    throw new TypeError("connection must be an object.");
  }

  requireString(connection.mode, "connection.mode");
  if (!VALID_CONNECTION_MODES.has(connection.mode)) {
    throw new TypeError(`Unsupported connection mode: ${connection.mode}`);
  }

  if (typeof connection.hasLiveAgentConnection !== "boolean") {
    throw new TypeError("connection.hasLiveAgentConnection must be boolean.");
  }

  if (connection.hasLiveAgentConnection && connection.mode !== "agent") {
    throw new TypeError("Only agent mode may report a live agent connection.");
  }

  if (connection.agentVersion !== undefined) {
    requireString(connection.agentVersion, "connection.agentVersion");
  }

  if (connection.os !== undefined) {
    requireString(connection.os, "connection.os");
  }

  if (connection.connectionDetail !== undefined) {
    requireString(connection.connectionDetail, "connection.connectionDetail");
  }
}

function validateApps(apps) {
  if (!Array.isArray(apps)) {
    throw new TypeError("apps must be an array.");
  }

  for (const app of apps) {
    if (!app || typeof app !== "object" || Array.isArray(app)) {
      throw new TypeError("app entries must be objects.");
    }

    requireString(app.id, "app.id");
    requireString(app.name, "app.name");
    requireBoolean(app.canRequestLaunch, "app.canRequestLaunch");
    requireBoolean(app.canLaunchNow, "app.canLaunchNow");
  }
}

function validateMirrorSessions(sessions) {
  if (!Array.isArray(sessions)) {
    throw new TypeError("mirrorSessions must be an array.");
  }

  for (const session of sessions) {
    if (!session || typeof session !== "object" || Array.isArray(session)) {
      throw new TypeError("mirror session entries must be objects.");
    }

    requireString(session.windowId, "session.windowId");
    requireString(session.appId, "session.appId");
    requireString(session.title, "session.title");
    requireString(session.captureState, "session.captureState");
    if (!VALID_CAPTURE_STATES.has(session.captureState)) {
      throw new TypeError(`Unsupported capture state: ${session.captureState}`);
    }
    requireBoolean(session.canFocus, "session.canFocus");
    requireBoolean(session.canClose, "session.canClose");
    requireBoolean(session.canSendInput, "session.canSendInput");
  }
}

function validateMacWindowIntegration(macWindowIntegration, mirrorSessions, connection) {
  if (!macWindowIntegration || typeof macWindowIntegration !== "object" || Array.isArray(macWindowIntegration)) {
    throw new TypeError("macWindowIntegration must be an object.");
  }

  requireBoolean(macWindowIntegration.isEnabled, "macWindowIntegration.isEnabled");
  requireBoolean(macWindowIntegration.acceptsGuestWindowEvents, "macWindowIntegration.acceptsGuestWindowEvents");
  requireBoolean(macWindowIntegration.opensMacWindowsAutomatically, "macWindowIntegration.opensMacWindowsAutomatically");
  requireBoolean(macWindowIntegration.hidesLauncherWhenMirroring, "macWindowIntegration.hidesLauncherWhenMirroring");
  requireNonNegativeInteger(macWindowIntegration.mirroredWindowCount, "macWindowIntegration.mirroredWindowCount");
  requireNonNegativeInteger(macWindowIntegration.pendingFrameWindowCount, "macWindowIntegration.pendingFrameWindowCount");
  requireNonNegativeInteger(macWindowIntegration.streamingWindowCount, "macWindowIntegration.streamingWindowCount");
  requireString(macWindowIntegration.reason, "macWindowIntegration.reason");

  if (macWindowIntegration.mirroredWindowCount !== mirrorSessions.length) {
    throw new TypeError("macWindowIntegration.mirroredWindowCount must match mirrorSessions length.");
  }

  if (macWindowIntegration.pendingFrameWindowCount !== mirrorSessions.filter((session) => session.captureState === "pending").length) {
    throw new TypeError("macWindowIntegration.pendingFrameWindowCount must match pending mirror sessions.");
  }

  if (macWindowIntegration.streamingWindowCount !== mirrorSessions.filter((session) => session.captureState === "streaming").length) {
    throw new TypeError("macWindowIntegration.streamingWindowCount must match streaming mirror sessions.");
  }

  if (macWindowIntegration.pendingFrameWindowCount + macWindowIntegration.streamingWindowCount > macWindowIntegration.mirroredWindowCount) {
    throw new TypeError("macWindowIntegration frame counts cannot exceed mirroredWindowCount.");
  }

  if (macWindowIntegration.acceptsGuestWindowEvents !== connection.hasLiveAgentConnection) {
    throw new TypeError("macWindowIntegration.acceptsGuestWindowEvents must reflect live agent connection.");
  }

  if (macWindowIntegration.hidesLauncherWhenMirroring && (!connection.hasLiveAgentConnection || mirrorSessions.length === 0)) {
    throw new TypeError("macWindowIntegration.hidesLauncherWhenMirroring requires a live mirrored Windows app window.");
  }
}

function validateQuietRuntime(quietRuntime, mirrorSessions) {
  if (!quietRuntime || typeof quietRuntime !== "object" || Array.isArray(quietRuntime)) {
    throw new TypeError("quietRuntime must be an object.");
  }

  requireBoolean(quietRuntime.isEnabled, "quietRuntime.isEnabled");
  requireBoolean(quietRuntime.hasOpenedAppWindowThisSession, "quietRuntime.hasOpenedAppWindowThisSession");
  requireNonNegativeInteger(quietRuntime.openWindowCount, "quietRuntime.openWindowCount");
  requireBoolean(quietRuntime.canQuietRuntime, "quietRuntime.canQuietRuntime");
  requireBoolean(quietRuntime.willQuietAutomatically, "quietRuntime.willQuietAutomatically");
  requireNonNegativeInteger(quietRuntime.automaticQuietDelaySeconds, "quietRuntime.automaticQuietDelaySeconds");
  requireString(quietRuntime.recommendedAction, "quietRuntime.recommendedAction");
  requireString(quietRuntime.reason, "quietRuntime.reason");

  if (quietRuntime.recommendedStopCommand !== undefined) {
    requireString(quietRuntime.recommendedStopCommand, "quietRuntime.recommendedStopCommand");
  }

  if (quietRuntime.openWindowCount !== mirrorSessions.length) {
    throw new TypeError("quietRuntime.openWindowCount must match mirrorSessions length.");
  }

  if (quietRuntime.canQuietRuntime && !quietRuntime.hasOpenedAppWindowThisSession) {
    throw new TypeError("quietRuntime.canQuietRuntime requires a Windows app window to have opened this session.");
  }

  if (quietRuntime.canQuietRuntime && quietRuntime.openWindowCount !== 0) {
    throw new TypeError("quietRuntime.canQuietRuntime requires zero open Windows app windows.");
  }

  if (quietRuntime.willQuietAutomatically && !quietRuntime.canQuietRuntime) {
    throw new TypeError("quietRuntime.willQuietAutomatically requires quietRuntime.canQuietRuntime.");
  }

  if (quietRuntime.canQuietRuntime && quietRuntime.recommendedStopCommand === undefined) {
    throw new TypeError("quietRuntime.canQuietRuntime requires quietRuntime.recommendedStopCommand.");
  }

  if (!quietRuntime.canQuietRuntime && quietRuntime.recommendedStopCommand !== undefined) {
    throw new TypeError("quietRuntime.recommendedStopCommand is only allowed when quietRuntime.canQuietRuntime is true.");
  }
}

function validateLaunchPlan(launchPlan, report) {
  if (!launchPlan || typeof launchPlan !== "object" || Array.isArray(launchPlan)) {
    throw new TypeError("launchPlan must be an object.");
  }

  requireBoolean(launchPlan.canRequestSelectedAppLaunch, "launchPlan.canRequestSelectedAppLaunch");
  requireBoolean(launchPlan.canLaunchSelectedAppNow, "launchPlan.canLaunchSelectedAppNow");
  requireBoolean(launchPlan.requiresRuntimeStart, "launchPlan.requiresRuntimeStart");
  requireBoolean(launchPlan.requiresGuestAgent, "launchPlan.requiresGuestAgent");
  requireString(launchPlan.recommendedAction, "launchPlan.recommendedAction");
  requireString(launchPlan.reason, "launchPlan.reason");

  if (launchPlan.selectedAppId !== undefined) {
    requireString(launchPlan.selectedAppId, "launchPlan.selectedAppId");
    if (report.selectedAppId !== launchPlan.selectedAppId) {
      throw new TypeError("launchPlan.selectedAppId must match selectedAppId.");
    }
  }

  if (launchPlan.pendingLaunchAppId !== undefined) {
    requireString(launchPlan.pendingLaunchAppId, "launchPlan.pendingLaunchAppId");
    if (report.pendingLaunchAppId !== launchPlan.pendingLaunchAppId) {
      throw new TypeError("launchPlan.pendingLaunchAppId must match pendingLaunchAppId.");
    }
  }

  if (launchPlan.recommendedStartCommand !== undefined) {
    requireString(launchPlan.recommendedStartCommand, "launchPlan.recommendedStartCommand");
  }

  if (launchPlan.recommendedWaitCommand !== undefined) {
    requireString(launchPlan.recommendedWaitCommand, "launchPlan.recommendedWaitCommand");
  }

  if (launchPlan.recommendedLaunchCommand !== undefined) {
    requireString(launchPlan.recommendedLaunchCommand, "launchPlan.recommendedLaunchCommand");
  }

  if (launchPlan.canLaunchSelectedAppNow && !launchPlan.canRequestSelectedAppLaunch) {
    throw new TypeError("launchPlan.canLaunchSelectedAppNow requires canRequestSelectedAppLaunch.");
  }

  if (launchPlan.canLaunchSelectedAppNow && !report.connection.hasLiveAgentConnection) {
    throw new TypeError("launchPlan.canLaunchSelectedAppNow requires a live agent connection.");
  }

  if (launchPlan.requiresRuntimeStart && report.connection.hasLiveAgentConnection) {
    throw new TypeError("launchPlan.requiresRuntimeStart is only valid before the live agent connects.");
  }

  if (launchPlan.requiresGuestAgent && report.connection.hasLiveAgentConnection) {
    throw new TypeError("launchPlan.requiresGuestAgent is only valid before the live agent connects.");
  }

  if (launchPlan.requiresRuntimeStart && launchPlan.recommendedStartCommand === undefined) {
    throw new TypeError("launchPlan.requiresRuntimeStart requires recommendedStartCommand.");
  }

  if (launchPlan.requiresGuestAgent && launchPlan.recommendedWaitCommand === undefined) {
    throw new TypeError("launchPlan.requiresGuestAgent requires recommendedWaitCommand.");
  }

  if (launchPlan.canRequestSelectedAppLaunch && launchPlan.recommendedLaunchCommand === undefined) {
    throw new TypeError("launchPlan.canRequestSelectedAppLaunch requires recommendedLaunchCommand.");
  }

  const selectedApp = report.apps.find((app) => app.id === launchPlan.selectedAppId);
  if (launchPlan.selectedAppId !== undefined && selectedApp === undefined) {
    throw new TypeError("launchPlan.selectedAppId must reference an app entry.");
  }

  if (selectedApp !== undefined) {
    if (launchPlan.canRequestSelectedAppLaunch !== selectedApp.canRequestLaunch) {
      throw new TypeError("launchPlan.canRequestSelectedAppLaunch must match the selected app.");
    }

    if (launchPlan.canLaunchSelectedAppNow !== selectedApp.canLaunchNow) {
      throw new TypeError("launchPlan.canLaunchSelectedAppNow must match the selected app.");
    }
  }
}

function validateDockIntegration(dockIntegration, mirrorSessions) {
  if (!dockIntegration || typeof dockIntegration !== "object" || Array.isArray(dockIntegration)) {
    throw new TypeError("dockIntegration must be an object.");
  }

  requireBoolean(dockIntegration.isEnabled, "dockIntegration.isEnabled");
  requireNonNegativeInteger(dockIntegration.openWindowCount, "dockIntegration.openWindowCount");
  requireBoolean(dockIntegration.canOpenMainWindow, "dockIntegration.canOpenMainWindow");
  requireBoolean(dockIntegration.canBringWindowsAppsForward, "dockIntegration.canBringWindowsAppsForward");
  requireBoolean(dockIntegration.canRestorePreviousApps, "dockIntegration.canRestorePreviousApps");
  requireBoolean(dockIntegration.canLaunchSelectedApp, "dockIntegration.canLaunchSelectedApp");

  if (dockIntegration.openWindowCount !== mirrorSessions.length) {
    throw new TypeError("dockIntegration.openWindowCount must match mirrorSessions length.");
  }

  if (dockIntegration.openWindowCount === 0 && dockIntegration.badgeLabel !== undefined) {
    throw new TypeError("dockIntegration.badgeLabel must be omitted when no Windows app windows are open.");
  }

  if (dockIntegration.openWindowCount > 0) {
    requireString(dockIntegration.badgeLabel, "dockIntegration.badgeLabel");
    if (dockIntegration.badgeLabel !== String(dockIntegration.openWindowCount)) {
      throw new TypeError("dockIntegration.badgeLabel must match openWindowCount.");
    }
  }

  if (dockIntegration.canBringWindowsAppsForward !== (mirrorSessions.length > 0)) {
    throw new TypeError("dockIntegration.canBringWindowsAppsForward must reflect open mirrored sessions.");
  }
}

function validateActions(actions, launchPlan) {
  if (!Array.isArray(actions)) {
    throw new TypeError("actions must be an array.");
  }

  const actionIds = new Set(actions.map((action) => action?.id));
  for (const requiredAction of [
    "dock.openMainWindow",
    "dock.bringWindowsAppsForward",
    "windowsApps.restorePrevious",
    "windowsApps.closeAll",
    "macWindows.autoOpen",
    "runtime.startWindowsForApp",
    "runtime.quietWhenIdle",
    "clipboard.setText"
  ]) {
    if (!actionIds.has(requiredAction)) {
      throw new TypeError(`actions must include ${requiredAction}.`);
    }
  }

  for (const action of actions) {
    if (!action || typeof action !== "object" || Array.isArray(action)) {
      throw new TypeError("action entries must be objects.");
    }

    requireString(action.id, "action.id");
    requireString(action.title, "action.title");
    requireBoolean(action.isAvailable, "action.isAvailable");
  }

  const startAction = actions.find((action) => action.id === "runtime.startWindowsForApp");
  if (startAction.isAvailable !== launchPlan.requiresRuntimeStart) {
    throw new TypeError("runtime.startWindowsForApp availability must match launchPlan.requiresRuntimeStart.");
  }
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
    throw new TypeError(`App runtime status field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`App runtime status field '${fieldName}' must be boolean.`);
  }
}

function requireNonNegativeInteger(value, fieldName) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`App runtime status field '${fieldName}' must be a non-negative integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected app runtime status JSON on stdin.");
  }

  validateAppRuntimeStatus(JSON.parse(input));
  process.stdout.write("app runtime status valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
