import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_CONNECTION_MODES = new Set(["agent", "demo"]);
const VALID_PHASES = new Set(["idle", "loading", "connected", "launching", "failed"]);
const VALID_CAPTURE_STATES = new Set(["unavailable", "pending", "streaming"]);
const VALID_CONSOLE_PREVIEW_STATES = new Set(["fresh", "stale", "unavailable"]);

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
  validateGuestAgentDiagnostics(report.guestAgentDiagnostics, report);
  validateLocalRuntime(report.localRuntime);
  validateApps(report.apps);
  validatePendingLaunch(report.pendingLaunch, report);
  validateMirrorSessions(report.mirrorSessions);
  validateStringArray(report.restorableAppIds, "restorableAppIds");
  validateDockIntegration(report.dockIntegration, report.mirrorSessions, report);
  validateMacWindowIntegration(report.macWindowIntegration, report.mirrorSessions, report.connection);
  validateLauncherVisibility(report.launcherVisibility, report);
  validateVisibleSurfacePolicy(report.visibleSurfacePolicy, report);
  validateQuietRuntime(report.quietRuntime, report.mirrorSessions);
  validateLaunchPlan(report.launchPlan, report);
  validateProofPlan(report.proofPlan, report);
  validateProofArtifacts(report.proofArtifacts);
  validateReleaseGate(report.releaseGate, report);
  validatePrimaryNextAction(report.primaryNextAction, report);
  validateMenuBarIntegration(report.menuBarIntegration, report);
  validateOneScreenUX(report.oneScreenUX, report);
  validateActions(report.actions, report);

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

  if (connection.capabilities !== undefined) {
    validateCapabilities(connection.capabilities);
    if (!connection.hasLiveAgentConnection) {
      throw new TypeError("connection.capabilities is only allowed when a live agent is connected.");
    }
  }
}

function validateCapabilities(capabilities) {
  if (!capabilities || typeof capabilities !== "object" || Array.isArray(capabilities)) {
    throw new TypeError("connection.capabilities must be an object.");
  }

  for (const field of ["appList", "appLaunch", "windowTracking", "windowCapture", "input", "clipboardText"]) {
    requireBoolean(capabilities[field], `connection.capabilities.${field}`);
  }
}

function validateGuestAgentDiagnostics(guestAgentDiagnostics, report) {
  if (!guestAgentDiagnostics || typeof guestAgentDiagnostics !== "object" || Array.isArray(guestAgentDiagnostics)) {
    throw new TypeError("guestAgentDiagnostics must be an object.");
  }

  requireString(guestAgentDiagnostics.endpoint, "guestAgentDiagnostics.endpoint");
  requireBoolean(guestAgentDiagnostics.isConnected, "guestAgentDiagnostics.isConnected");
  requireString(guestAgentDiagnostics.diagnosticCommand, "guestAgentDiagnostics.diagnosticCommand");
  requireString(guestAgentDiagnostics.waitCommand, "guestAgentDiagnostics.waitCommand");
  requireString(guestAgentDiagnostics.recommendedAction, "guestAgentDiagnostics.recommendedAction");
  requireString(guestAgentDiagnostics.reason, "guestAgentDiagnostics.reason");

  if (guestAgentDiagnostics.isConnected !== report.connection.hasLiveAgentConnection) {
    throw new TypeError("guestAgentDiagnostics.isConnected must match connection.hasLiveAgentConnection.");
  }

  if (guestAgentDiagnostics.diagnosticCommand !== "veil-host-probe --diagnose-agent") {
    throw new TypeError("guestAgentDiagnostics.diagnosticCommand must point at the host probe diagnostic.");
  }

  if (guestAgentDiagnostics.waitCommand !== "veil-vmctl guest-agent-wait --json --wait-seconds 30") {
    throw new TypeError("guestAgentDiagnostics.waitCommand must point at the guest-agent wait harness gate.");
  }

  const expectedAction = report.connection.hasLiveAgentConnection ? "run-app-window-proof" : "diagnose-agent";
  if (guestAgentDiagnostics.recommendedAction !== expectedAction) {
    throw new TypeError("guestAgentDiagnostics.recommendedAction must match live agent readiness.");
  }
}

function validateLocalRuntime(localRuntime) {
  if (!localRuntime || typeof localRuntime !== "object" || Array.isArray(localRuntime)) {
    throw new TypeError("localRuntime must be an object.");
  }

  requireBoolean(localRuntime.isKnown, "localRuntime.isKnown");
  requireBoolean(localRuntime.bootReady, "localRuntime.bootReady");
  requireBoolean(localRuntime.canStart, "localRuntime.canStart");
  requireBoolean(localRuntime.isRunning, "localRuntime.isRunning");
  requireBoolean(localRuntime.windowsInstalled, "localRuntime.windowsInstalled");
  requireString(localRuntime.recommendedAction, "localRuntime.recommendedAction");
  requireString(localRuntime.recommendedInstallStatusCommand, "localRuntime.recommendedInstallStatusCommand");
  requireString(localRuntime.reason, "localRuntime.reason");

  if (localRuntime.state !== undefined) {
    requireString(localRuntime.state, "localRuntime.state");
  }

  if (localRuntime.recommendedPrepareCommand !== undefined) {
    requireString(localRuntime.recommendedPrepareCommand, "localRuntime.recommendedPrepareCommand");
  }

  if (localRuntime.recommendedDisplayCommand !== undefined) {
    requireString(localRuntime.recommendedDisplayCommand, "localRuntime.recommendedDisplayCommand");
  }

  if (localRuntime.recommendedRecoveryCommand !== undefined) {
    requireString(localRuntime.recommendedRecoveryCommand, "localRuntime.recommendedRecoveryCommand");
  }

  if (localRuntime.consolePreviewStatus !== undefined) {
    requireString(localRuntime.consolePreviewStatus, "localRuntime.consolePreviewStatus");
    if (!VALID_CONSOLE_PREVIEW_STATES.has(localRuntime.consolePreviewStatus)) {
      throw new TypeError(`Unsupported localRuntime.consolePreviewStatus: ${localRuntime.consolePreviewStatus}`);
    }
  }

  if (localRuntime.recommendedInstallStatusCommand !== "veil-vmctl qemu-install-status --json") {
    throw new TypeError("localRuntime.recommendedInstallStatusCommand must point at qemu-install-status.");
  }

  if (localRuntime.isRunning && localRuntime.canStart) {
    throw new TypeError("localRuntime.canStart must be false while the runtime is already running.");
  }

  if (
    localRuntime.isRunning
    && ["stale", "unavailable"].includes(localRuntime.consolePreviewStatus)
    && localRuntime.recommendedRecoveryCommand === undefined
  ) {
    throw new TypeError("localRuntime.recommendedRecoveryCommand is required when a running runtime has stale or unavailable console preview evidence.");
  }

  if (
    localRuntime.recommendedRecoveryCommand !== undefined
    && localRuntime.recommendedAction !== "recover-runtime-display"
  ) {
    throw new TypeError("localRuntime.recommendedRecoveryCommand requires recommendedAction recover-runtime-display.");
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

function validatePendingLaunch(pendingLaunch, report) {
  if (!pendingLaunch || typeof pendingLaunch !== "object" || Array.isArray(pendingLaunch)) {
    throw new TypeError("pendingLaunch must be an object.");
  }

  requireBoolean(pendingLaunch.isQueued, "pendingLaunch.isQueued");
  requireBoolean(pendingLaunch.willLaunchOnAgentReconnect, "pendingLaunch.willLaunchOnAgentReconnect");
  requireString(pendingLaunch.recommendedAction, "pendingLaunch.recommendedAction");
  requireString(pendingLaunch.reason, "pendingLaunch.reason");

  if (pendingLaunch.appId !== undefined) {
    requireString(pendingLaunch.appId, "pendingLaunch.appId");
  }

  if (report.pendingLaunchAppId === undefined && pendingLaunch.isQueued) {
    throw new TypeError("pendingLaunch.isQueued requires pendingLaunchAppId.");
  }

  if (report.pendingLaunchAppId !== undefined) {
    if (!pendingLaunch.isQueued) {
      throw new TypeError("pendingLaunchAppId requires pendingLaunch.isQueued.");
    }

    if (pendingLaunch.appId !== report.pendingLaunchAppId) {
      throw new TypeError("pendingLaunch.appId must match pendingLaunchAppId.");
    }
  }

  if (!pendingLaunch.isQueued && pendingLaunch.appId !== undefined) {
    throw new TypeError("pendingLaunch.appId is only allowed when pendingLaunch.isQueued is true.");
  }

  if (pendingLaunch.willLaunchOnAgentReconnect) {
    if (!pendingLaunch.isQueued) {
      throw new TypeError("pendingLaunch.willLaunchOnAgentReconnect requires pendingLaunch.isQueued.");
    }

    if (report.connection.hasLiveAgentConnection) {
      throw new TypeError("pendingLaunch.willLaunchOnAgentReconnect is only valid before the live agent connects.");
    }

    const pendingApp = report.apps.find((app) => app.id === pendingLaunch.appId);
    if (pendingApp === undefined || !pendingApp.canRequestLaunch) {
      throw new TypeError("pendingLaunch.willLaunchOnAgentReconnect requires a requestable pending app.");
    }
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
  requireNonNegativeInteger(macWindowIntegration.foregroundableWindowCount, "macWindowIntegration.foregroundableWindowCount");
  requireNonNegativeInteger(macWindowIntegration.pendingFrameWindowCount, "macWindowIntegration.pendingFrameWindowCount");
  requireNonNegativeInteger(macWindowIntegration.streamingWindowCount, "macWindowIntegration.streamingWindowCount");
  requireString(macWindowIntegration.reason, "macWindowIntegration.reason");

  if (macWindowIntegration.mirroredWindowCount !== mirrorSessions.length) {
    throw new TypeError("macWindowIntegration.mirroredWindowCount must match mirrorSessions length.");
  }

  if (macWindowIntegration.foregroundableWindowCount !== mirrorSessions.length) {
    throw new TypeError("macWindowIntegration.foregroundableWindowCount must match mirrorSessions length.");
  }

  if (mirrorSessions.length === 0) {
    if (macWindowIntegration.foregroundWindowId !== undefined || macWindowIntegration.foregroundWindowTitle !== undefined) {
      throw new TypeError("macWindowIntegration foreground window fields must be omitted when no mirrored sessions exist.");
    }
  } else {
    const foregroundSession = mirrorSessions.at(-1);
    requireString(macWindowIntegration.foregroundWindowId, "macWindowIntegration.foregroundWindowId");
    requireString(macWindowIntegration.foregroundWindowTitle, "macWindowIntegration.foregroundWindowTitle");
    if (macWindowIntegration.foregroundWindowId !== foregroundSession.windowId) {
      throw new TypeError("macWindowIntegration.foregroundWindowId must match the foreground mirror session.");
    }
    if (macWindowIntegration.foregroundWindowTitle !== foregroundSession.title) {
      throw new TypeError("macWindowIntegration.foregroundWindowTitle must match the foreground mirror session.");
    }
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
  requireBoolean(launchPlan.willOpenAppAutomatically, "launchPlan.willOpenAppAutomatically");
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

  if (report.pendingLaunch.isQueued && launchPlan.pendingLaunchAppId !== report.pendingLaunch.appId) {
    throw new TypeError("launchPlan.pendingLaunchAppId must match pendingLaunch.appId while a launch is queued.");
  }

  if (report.pendingLaunch.isQueued && launchPlan.recommendedLaunchCommand !== "veil-vmctl app-runtime-action --json --action fulfill-pending") {
    throw new TypeError("queued pending launches must recommend the fulfill-pending action.");
  }

  if (report.pendingLaunch.willLaunchOnAgentReconnect && !launchPlan.requiresGuestAgent) {
    throw new TypeError("pendingLaunch.willLaunchOnAgentReconnect requires launchPlan.requiresGuestAgent.");
  }

  if (launchPlan.recommendedStartCommand !== undefined) {
    requireString(launchPlan.recommendedStartCommand, "launchPlan.recommendedStartCommand");
  }

  if (launchPlan.recommendedWaitCommand !== undefined) {
    requireString(launchPlan.recommendedWaitCommand, "launchPlan.recommendedWaitCommand");
  }

  if (launchPlan.recommendedRepairCommand !== undefined) {
    requireString(launchPlan.recommendedRepairCommand, "launchPlan.recommendedRepairCommand");
  }

  if (launchPlan.recommendedLaunchCommand !== undefined) {
    requireString(launchPlan.recommendedLaunchCommand, "launchPlan.recommendedLaunchCommand");
  }

  if (launchPlan.canLaunchSelectedAppNow && !launchPlan.canRequestSelectedAppLaunch) {
    throw new TypeError("launchPlan.canLaunchSelectedAppNow requires canRequestSelectedAppLaunch.");
  }

  const expectedAutomaticOpen = launchPlan.canLaunchSelectedAppNow
    || (launchPlan.canRequestSelectedAppLaunch && launchPlan.recommendedAction !== "prepare-local-runtime");
  if (launchPlan.willOpenAppAutomatically !== expectedAutomaticOpen) {
    throw new TypeError("launchPlan.willOpenAppAutomatically must reflect the app shell automatic handoff path.");
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

  if (launchPlan.requiresRuntimeStart
    && launchPlan.recommendedStartCommand === undefined
    && launchPlan.recommendedAction !== "prepare-local-runtime") {
    throw new TypeError("launchPlan.requiresRuntimeStart requires recommendedStartCommand unless local runtime preparation is required.");
  }

  if (launchPlan.recommendedAction === "prepare-local-runtime") {
    if (!launchPlan.requiresRuntimeStart || report.localRuntime.canStart || report.localRuntime.isRunning) {
      throw new TypeError("launchPlan.prepare-local-runtime requires a blocked local runtime start.");
    }
    if (launchPlan.recommendedStartCommand !== undefined) {
      throw new TypeError("launchPlan.prepare-local-runtime must not expose qemu-start.");
    }
  }

  if (launchPlan.requiresGuestAgent
    && launchPlan.recommendedWaitCommand === undefined
    && launchPlan.recommendedAction !== "prepare-local-runtime") {
    throw new TypeError("launchPlan.requiresGuestAgent requires recommendedWaitCommand.");
  }

  if (launchPlan.recommendedRepairCommand !== undefined) {
    if (!launchPlan.requiresGuestAgent || !report.localRuntime.isRunning || report.connection.hasLiveAgentConnection) {
      throw new TypeError("launchPlan.recommendedRepairCommand is only allowed for a running local runtime waiting for the guest agent.");
    }
    if (!launchPlan.recommendedAction.includes("repair-guest-agent")) {
      throw new TypeError("launchPlan.recommendedRepairCommand requires a repair-guest-agent recommendedAction.");
    }
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

function validateProofPlan(proofPlan, report) {
  if (!proofPlan || typeof proofPlan !== "object" || Array.isArray(proofPlan)) {
    throw new TypeError("proofPlan must be an object.");
  }

  requireBoolean(proofPlan.canRunAppWindowProof, "proofPlan.canRunAppWindowProof");
  requireBoolean(proofPlan.canRunCoherenceProof, "proofPlan.canRunCoherenceProof");
  requireBoolean(proofPlan.canRunMVPProof, "proofPlan.canRunMVPProof");
  requireString(proofPlan.reason, "proofPlan.reason");

  if (proofPlan.selectedAppId !== undefined) {
    requireString(proofPlan.selectedAppId, "proofPlan.selectedAppId");
    if (report.selectedAppId !== proofPlan.selectedAppId) {
      throw new TypeError("proofPlan.selectedAppId must match selectedAppId.");
    }
  }

  if (report.selectedAppId !== undefined && proofPlan.selectedAppId !== report.selectedAppId) {
    throw new TypeError("proofPlan.selectedAppId must be present when selectedAppId is present.");
  }

  const selectedApp = report.apps.find((app) => app.id === report.selectedAppId);
  const capabilities = report.connection.capabilities;
  const canRunAppWindowProof = report.connection.hasLiveAgentConnection
    && selectedApp?.canLaunchNow === true
    && capabilities?.windowCapture === true;
  const canRunCoherenceProof = canRunAppWindowProof
    && capabilities?.input === true
    && capabilities?.clipboardText === true;

  if (proofPlan.canRunAppWindowProof !== canRunAppWindowProof) {
    throw new TypeError("proofPlan.canRunAppWindowProof must match live app launch and window capture readiness.");
  }

  if (proofPlan.canRunCoherenceProof !== canRunCoherenceProof) {
    throw new TypeError("proofPlan.canRunCoherenceProof must match input and clipboard proof readiness.");
  }

  if (proofPlan.canRunMVPProof !== canRunCoherenceProof) {
    throw new TypeError("proofPlan.canRunMVPProof must match coherence proof readiness.");
  }

  const expectedAppWindowCommand = report.selectedAppId === undefined
    ? undefined
    : `veil-vmctl app-window-proof --json --app-id ${report.selectedAppId}`;
  const expectedCoherenceCommand = report.selectedAppId === undefined
    ? undefined
    : `veil-vmctl coherence-proof --json --app-id ${report.selectedAppId}`;
  const expectedMVPCommand = report.selectedAppId === undefined
    ? undefined
    : `veil-vmctl mvp-proof --json --app-id ${report.selectedAppId} --require-proved`;
  const expectedRecommendedProof = strongestProof(proofPlan);

  validateProofCommand(
    proofPlan.recommendedAppWindowProofCommand,
    "proofPlan.recommendedAppWindowProofCommand",
    proofPlan.canRunAppWindowProof,
    expectedAppWindowCommand
  );
  validateProofCommand(
    proofPlan.recommendedCoherenceProofCommand,
    "proofPlan.recommendedCoherenceProofCommand",
    proofPlan.canRunCoherenceProof,
    expectedCoherenceCommand
  );
  validateProofCommand(
    proofPlan.recommendedMVPProofCommand,
    "proofPlan.recommendedMVPProofCommand",
    proofPlan.canRunMVPProof,
    expectedMVPCommand
  );

  if (expectedRecommendedProof === undefined) {
    if (proofPlan.recommendedProofKind !== undefined || proofPlan.recommendedProofCommand !== undefined) {
      throw new TypeError("proofPlan recommended proof fields are only allowed when a proof command is available.");
    }
  } else {
    requireString(proofPlan.recommendedProofKind, "proofPlan.recommendedProofKind");
    requireString(proofPlan.recommendedProofCommand, "proofPlan.recommendedProofCommand");
    if (proofPlan.recommendedProofKind !== expectedRecommendedProof.kind) {
      throw new TypeError("proofPlan.recommendedProofKind must identify the strongest available proof.");
    }
    if (proofPlan.recommendedProofCommand !== expectedRecommendedProof.command) {
      throw new TypeError("proofPlan.recommendedProofCommand must match the strongest available proof command.");
    }
  }
}

function strongestProof(proofPlan) {
  if (proofPlan.canRunMVPProof) {
    return { kind: "mvp", command: proofPlan.recommendedMVPProofCommand };
  }
  if (proofPlan.canRunCoherenceProof) {
    return { kind: "coherence", command: proofPlan.recommendedCoherenceProofCommand };
  }
  if (proofPlan.canRunAppWindowProof) {
    return { kind: "app-window", command: proofPlan.recommendedAppWindowProofCommand };
  }
  return undefined;
}

function validateProofArtifacts(proofArtifacts) {
  if (proofArtifacts === undefined) {
    return;
  }

  if (!proofArtifacts || typeof proofArtifacts !== "object" || Array.isArray(proofArtifacts)) {
    throw new TypeError("proofArtifacts must be an object when present.");
  }

  requireString(proofArtifacts.diagnosticsDirectory, "proofArtifacts.diagnosticsDirectory");
  requireString(proofArtifacts.recommendedProofDirectory, "proofArtifacts.recommendedProofDirectory");
  requireString(proofArtifacts.reason, "proofArtifacts.reason");

  const hasLatest = proofArtifacts.latestProofKind !== undefined
    || proofArtifacts.latestProofPath !== undefined
    || proofArtifacts.latestProofFileName !== undefined
    || proofArtifacts.latestProofModifiedAt !== undefined;

  if (!hasLatest) {
    return;
  }

  requireString(proofArtifacts.latestProofKind, "proofArtifacts.latestProofKind");
  if (!["recommended", "app-window", "coherence", "mvp"].includes(proofArtifacts.latestProofKind)) {
    throw new TypeError("proofArtifacts.latestProofKind must identify a known proof kind.");
  }

  requireString(proofArtifacts.latestProofPath, "proofArtifacts.latestProofPath");
  requireString(proofArtifacts.latestProofFileName, "proofArtifacts.latestProofFileName");
  requireString(proofArtifacts.latestProofModifiedAt, "proofArtifacts.latestProofModifiedAt");
  if (!proofArtifacts.latestProofPath.endsWith(".json") || !proofArtifacts.latestProofFileName.endsWith(".json")) {
    throw new TypeError("proofArtifacts latest artifact must point to a JSON file.");
  }

  if (Number.isNaN(Date.parse(proofArtifacts.latestProofModifiedAt))) {
    throw new TypeError("proofArtifacts.latestProofModifiedAt must be an ISO date.");
  }
}

function validateReleaseGate(releaseGate, report) {
  if (!releaseGate || typeof releaseGate !== "object" || Array.isArray(releaseGate)) {
    throw new TypeError("releaseGate must be an object.");
  }

  requireBoolean(releaseGate.isEnabled, "releaseGate.isEnabled");
  requireNonNegativeInteger(releaseGate.requiredStepCount, "releaseGate.requiredStepCount");
  requireNonNegativeInteger(releaseGate.passingStepCount, "releaseGate.passingStepCount");
  requireBoolean(releaseGate.isPassing, "releaseGate.isPassing");
  requireString(releaseGate.recommendedAction, "releaseGate.recommendedAction");
  requireString(releaseGate.reason, "releaseGate.reason");

  if (!Array.isArray(releaseGate.steps) || releaseGate.steps.length === 0) {
    throw new TypeError("releaseGate.steps must be a non-empty array.");
  }

  if (!Array.isArray(releaseGate.screenshotSlots) || releaseGate.screenshotSlots.length === 0) {
    throw new TypeError("releaseGate.screenshotSlots must be a non-empty array.");
  }

  const expectedStepIds = [
    "windowsSetup",
    "oneScreenPath",
    "openWindowsApp",
    "appCheckEvidence",
    "closeOrRestore"
  ];
  const actualStepIds = releaseGate.steps.map((step) => step?.id);
  if (actualStepIds.join(",") !== expectedStepIds.join(",")) {
    throw new TypeError("releaseGate.steps must preserve the one-screen release gate order.");
  }

  const validStates = new Set(["pending", "ready", "passed", "blocked"]);
  for (const step of releaseGate.steps) {
    if (!step || typeof step !== "object" || Array.isArray(step)) {
      throw new TypeError("releaseGate step entries must be objects.");
    }

    requireString(step.id, "releaseGate.step.id");
    requireString(step.title, "releaseGate.step.title");
    requireString(step.state, `releaseGate.steps.${step.id}.state`);
    requireBoolean(step.isRequired, `releaseGate.steps.${step.id}.isRequired`);
    requireBoolean(step.isPassing, `releaseGate.steps.${step.id}.isPassing`);
    requireString(step.evidence, `releaseGate.steps.${step.id}.evidence`);

    if (!validStates.has(step.state)) {
      throw new TypeError(`Unsupported releaseGate step state: ${step.state}`);
    }

    if (step.nextActionCommand !== undefined) {
      requireString(step.nextActionCommand, `releaseGate.steps.${step.id}.nextActionCommand`);
    }

    for (const disallowedTerm of ["Guest Agent", "HWND", "QEMU", "Proof"]) {
      if (step.title.includes(disallowedTerm)) {
        throw new TypeError("releaseGate step titles must stay product-facing.");
      }
    }
  }

  const requiredSteps = releaseGate.steps.filter((step) => step.isRequired);
  const passingStepCount = requiredSteps.filter((step) => step.isPassing).length;
  if (releaseGate.requiredStepCount !== requiredSteps.length) {
    throw new TypeError("releaseGate.requiredStepCount must match required steps.");
  }
  if (releaseGate.passingStepCount !== passingStepCount) {
    throw new TypeError("releaseGate.passingStepCount must match passing required steps.");
  }
  if (releaseGate.isPassing !== (passingStepCount === requiredSteps.length)) {
    throw new TypeError("releaseGate.isPassing must reflect all required steps.");
  }

  const firstUnmetStep = requiredSteps.find((step) => !step.isPassing);
  const expectedRecommendedAction = firstUnmetStep?.id ?? "ready-for-release-card";
  if (releaseGate.recommendedAction !== expectedRecommendedAction) {
    throw new TypeError("releaseGate.recommendedAction must point at the first unmet step.");
  }

  const setupStep = releaseGate.steps.find((step) => step.id === "windowsSetup");
  const expectedSetupPassing = report.localRuntime.bootReady && report.localRuntime.windowsInstalled;
  if (setupStep.isPassing !== expectedSetupPassing) {
    throw new TypeError("releaseGate windowsSetup must reflect local Windows setup readiness.");
  }
  if (setupStep.nextActionCommand !== report.localRuntime.recommendedInstallStatusCommand
    && setupStep.nextActionCommand !== report.localRuntime.recommendedPrepareCommand) {
    throw new TypeError("releaseGate windowsSetup must expose an install status or prepare command.");
  }

  const oneScreenStep = releaseGate.steps.find((step) => step.id === "oneScreenPath");
  const expectedOneScreenPassing = report.launcherVisibility.isEnabled
    && report.visibleSurfacePolicy.isEnabled
    && report.visibleSurfacePolicy.keepsRecoveryDisplayManual
    && (report.visibleSurfacePolicy.primarySurface === "launcher" || report.macWindowIntegration.hidesLauncherWhenMirroring);
  if (oneScreenStep.isPassing !== expectedOneScreenPassing) {
    throw new TypeError("releaseGate oneScreenPath must reflect visible surface policy.");
  }
  if (oneScreenStep.nextActionCommand !== "veil-vmctl app-runtime-status --json") {
    throw new TypeError("releaseGate oneScreenPath must point back to app-runtime-status.");
  }

  const launchStep = releaseGate.steps.find((step) => step.id === "openWindowsApp");
  const expectedLaunchPassing = report.launchPlan.willOpenAppAutomatically
    && report.launchPlan.recommendedLaunchCommand !== undefined;
  if (launchStep.isPassing !== expectedLaunchPassing) {
    throw new TypeError("releaseGate openWindowsApp must reflect launch plan readiness.");
  }
  const expectedLaunchCommand = report.launchPlan.recommendedLaunchCommand
    ?? report.launchPlan.recommendedStartCommand
    ?? report.launchPlan.recommendedRepairCommand
    ?? report.launchPlan.recommendedWaitCommand;
  if (launchStep.nextActionCommand !== expectedLaunchCommand) {
    throw new TypeError("releaseGate openWindowsApp must expose the next launch command.");
  }

  const checkStep = releaseGate.steps.find((step) => step.id === "appCheckEvidence");
  const expectedCheckPassing = report.proofArtifacts.latestProofPath !== undefined
    && report.proofArtifacts.latestProofKind !== undefined;
  if (checkStep.isPassing !== expectedCheckPassing) {
    throw new TypeError("releaseGate appCheckEvidence must reflect saved app check evidence.");
  }
  if (checkStep.nextActionCommand !== report.proofPlan.recommendedProofCommand) {
    throw new TypeError("releaseGate appCheckEvidence must expose the recommended app check command.");
  }

  const closeStep = releaseGate.steps.find((step) => step.id === "closeOrRestore");
  const expectedClosePassing = report.quietRuntime.canQuietRuntime
    || report.macWindowIntegration.mirroredWindowCount > 0
    || report.dockIntegration.canReconnectPreviousApps
    || report.dockIntegration.canRestorePreviousApps;
  if (closeStep.isPassing !== expectedClosePassing) {
    throw new TypeError("releaseGate closeOrRestore must reflect close, quiet, or restore readiness.");
  }
  const expectedCloseCommand = report.macWindowIntegration.mirroredWindowCount > 0
    ? "veil-vmctl app-runtime-action --json --action close-all"
    : (report.quietRuntime.recommendedStopCommand
      ?? ((report.dockIntegration.canReconnectPreviousApps || report.dockIntegration.canRestorePreviousApps)
        ? "veil-vmctl app-runtime-action --json --action reconnect-restore"
        : undefined));
  if (closeStep.nextActionCommand !== expectedCloseCommand) {
    throw new TypeError("releaseGate closeOrRestore must expose the next close, quiet, or restore command.");
  }

  const expectedSlotIds = [
    "preBootLauncher",
    "firstAppLaunch",
    "appWindowOnly",
    "menuRestore",
    "closeQuiet"
  ];
  const actualSlotIds = releaseGate.screenshotSlots.map((slot) => slot?.id);
  if (actualSlotIds.join(",") !== expectedSlotIds.join(",")) {
    throw new TypeError("releaseGate.screenshotSlots must match the proof card template.");
  }

  for (const slot of releaseGate.screenshotSlots) {
    if (!slot || typeof slot !== "object" || Array.isArray(slot)) {
      throw new TypeError("releaseGate screenshot slot entries must be objects.");
    }
    requireString(slot.id, "releaseGate.screenshotSlot.id");
    requireString(slot.title, `releaseGate.screenshotSlots.${slot.id}.title`);
    requireString(slot.expectedSurface, `releaseGate.screenshotSlots.${slot.id}.expectedSurface`);
    requireBoolean(slot.isRequired, `releaseGate.screenshotSlots.${slot.id}.isRequired`);
  }
}

function validatePrimaryNextAction(primaryNextAction, report) {
  if (!primaryNextAction || typeof primaryNextAction !== "object" || Array.isArray(primaryNextAction)) {
    throw new TypeError("primaryNextAction must be an object.");
  }

  requireString(primaryNextAction.id, "primaryNextAction.id");
  requireString(primaryNextAction.title, "primaryNextAction.title");
  requireString(primaryNextAction.source, "primaryNextAction.source");
  requireBoolean(primaryNextAction.isAvailable, "primaryNextAction.isAvailable");
  requireString(primaryNextAction.reason, "primaryNextAction.reason");

  if (primaryNextAction.command !== undefined) {
    requireString(primaryNextAction.command, "primaryNextAction.command");
  }
  if (primaryNextAction.actionId !== undefined) {
    requireString(primaryNextAction.actionId, "primaryNextAction.actionId");
  }

  if (primaryNextAction.source !== "releaseGate") {
    throw new TypeError("primaryNextAction.source must be releaseGate.");
  }

  const expectedStep = report.releaseGate.isPassing
    ? undefined
    : report.releaseGate.steps.find((step) => step.id === report.releaseGate.recommendedAction);
  const expectedId = report.releaseGate.isPassing ? "ready-for-release-card" : expectedStep?.id;
  const expectedTitle = report.releaseGate.isPassing ? "Review App Flow" : expectedStep?.title;
  const expectedCommand = report.releaseGate.isPassing
    ? "veil-vmctl app-runtime-review --json"
    : expectedStep?.nextActionCommand;
  const expectedActionId = report.releaseGate.isPassing
    ? undefined
    : expectedPrimaryNextActionId(expectedStep?.id, expectedCommand);
  const expectedReason = report.releaseGate.isPassing
    ? report.releaseGate.reason
    : expectedStep?.evidence;

  if (primaryNextAction.id !== expectedId) {
    throw new TypeError("primaryNextAction.id must match the release gate's next step.");
  }
  if (primaryNextAction.title !== expectedTitle) {
    throw new TypeError("primaryNextAction.title must match the release gate's next step.");
  }
  if (primaryNextAction.command !== expectedCommand) {
    throw new TypeError("primaryNextAction.command must match the release gate's next command.");
  }
  if (primaryNextAction.actionId !== expectedActionId) {
    throw new TypeError("primaryNextAction.actionId must match the release gate's next executable action.");
  }
  if (primaryNextAction.isAvailable !== (expectedCommand !== undefined)) {
    throw new TypeError("primaryNextAction.isAvailable must reflect whether a next command exists.");
  }
  if (primaryNextAction.reason !== expectedReason) {
    throw new TypeError("primaryNextAction.reason must match the release gate's next evidence.");
  }

  for (const disallowedTerm of ["Guest Agent", "HWND", "QEMU", "Proof"]) {
    if (primaryNextAction.title.includes(disallowedTerm)) {
      throw new TypeError("primaryNextAction title must stay product-facing.");
    }
  }
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

function validateProofCommand(command, fieldName, isAvailable, expectedCommand) {
  if (isAvailable) {
    requireString(command, fieldName);
    if (command !== expectedCommand) {
      throw new TypeError(`${fieldName} must match the selected app proof command.`);
    }
    return;
  }

  if (command !== undefined) {
    throw new TypeError(`${fieldName} is only allowed when the matching proof is available.`);
  }
}

function validateDockIntegration(dockIntegration, mirrorSessions, report) {
  if (!dockIntegration || typeof dockIntegration !== "object" || Array.isArray(dockIntegration)) {
    throw new TypeError("dockIntegration must be an object.");
  }

  requireBoolean(dockIntegration.isEnabled, "dockIntegration.isEnabled");
  requireNonNegativeInteger(dockIntegration.openWindowCount, "dockIntegration.openWindowCount");
  requireNonNegativeInteger(dockIntegration.pendingLaunchCount, "dockIntegration.pendingLaunchCount");
  requireNonNegativeInteger(dockIntegration.restorableAppCount, "dockIntegration.restorableAppCount");
  requireBoolean(dockIntegration.canOpenMainWindow, "dockIntegration.canOpenMainWindow");
  requireBoolean(dockIntegration.canBringWindowsAppsForward, "dockIntegration.canBringWindowsAppsForward");
  requireBoolean(dockIntegration.canRestorePreviousApps, "dockIntegration.canRestorePreviousApps");
  requireBoolean(dockIntegration.canReconnectPreviousApps, "dockIntegration.canReconnectPreviousApps");
  requireBoolean(dockIntegration.canLaunchSelectedApp, "dockIntegration.canLaunchSelectedApp");

  if (dockIntegration.openWindowCount !== mirrorSessions.length) {
    throw new TypeError("dockIntegration.openWindowCount must match mirrorSessions length.");
  }

  const expectedPendingLaunchCount = report.pendingLaunch.isQueued ? 1 : 0;
  if (dockIntegration.pendingLaunchCount !== expectedPendingLaunchCount) {
    throw new TypeError("dockIntegration.pendingLaunchCount must reflect queued pending launch state.");
  }

  if (dockIntegration.restorableAppCount !== report.restorableAppIds.length) {
    throw new TypeError("dockIntegration.restorableAppCount must match restorableAppIds length.");
  }

  const canReconnectPreviousApps = report.restorableAppIds.length > 0
    && mirrorSessions.length === 0
    && !["loading", "launching"].includes(report.phase);
  if (dockIntegration.canReconnectPreviousApps !== canReconnectPreviousApps) {
    throw new TypeError("dockIntegration.canReconnectPreviousApps must reflect previous-app restore readiness.");
  }

  const canRestorePreviousApps = report.connection.hasLiveAgentConnection && canReconnectPreviousApps;
  if (dockIntegration.canRestorePreviousApps !== canRestorePreviousApps) {
    throw new TypeError("dockIntegration.canRestorePreviousApps must reflect live app connection restore readiness.");
  }

  if (
    dockIntegration.openWindowCount === 0
    && dockIntegration.pendingLaunchCount === 0
    && dockIntegration.restorableAppCount === 0
    && dockIntegration.badgeLabel !== undefined
  ) {
    throw new TypeError("dockIntegration.badgeLabel must be omitted when no Windows app windows, pending launches, or restorable apps exist.");
  }

  if (dockIntegration.openWindowCount > 0) {
    requireString(dockIntegration.badgeLabel, "dockIntegration.badgeLabel");
    if (dockIntegration.badgeLabel !== String(dockIntegration.openWindowCount)) {
      throw new TypeError("dockIntegration.badgeLabel must match openWindowCount.");
    }
  }

  if (dockIntegration.openWindowCount === 0 && dockIntegration.pendingLaunchCount > 0) {
    requireString(dockIntegration.badgeLabel, "dockIntegration.badgeLabel");
    if (dockIntegration.badgeLabel !== "...") {
      throw new TypeError("dockIntegration.badgeLabel must show pending app launch progress.");
    }
  }

  if (
    dockIntegration.openWindowCount === 0
    && dockIntegration.pendingLaunchCount === 0
    && dockIntegration.restorableAppCount > 0
  ) {
    requireString(dockIntegration.badgeLabel, "dockIntegration.badgeLabel");
    const expectedRestoreBadge = dockIntegration.restorableAppCount === 1 ? "R" : `R${dockIntegration.restorableAppCount}`;
    if (dockIntegration.badgeLabel !== expectedRestoreBadge) {
      throw new TypeError("dockIntegration.badgeLabel must show previous-app restore readiness.");
    }
  }

  if (dockIntegration.canBringWindowsAppsForward !== (mirrorSessions.length > 0)) {
    throw new TypeError("dockIntegration.canBringWindowsAppsForward must reflect open mirrored sessions.");
  }
}

function validateMenuBarIntegration(menuBarIntegration, report) {
  if (!menuBarIntegration || typeof menuBarIntegration !== "object" || Array.isArray(menuBarIntegration)) {
    throw new TypeError("menuBarIntegration must be an object.");
  }

  requireBoolean(menuBarIntegration.isEnabled, "menuBarIntegration.isEnabled");
  requireString(menuBarIntegration.statusTitle, "menuBarIntegration.statusTitle");
  requireString(menuBarIntegration.symbolName, "menuBarIntegration.symbolName");
  requireString(menuBarIntegration.primaryActionId, "menuBarIntegration.primaryActionId");
  requireString(menuBarIntegration.primaryActionTitle, "menuBarIntegration.primaryActionTitle");
  requireBoolean(menuBarIntegration.primaryActionAvailable, "menuBarIntegration.primaryActionAvailable");
  requireBoolean(menuBarIntegration.canOpenMainWindow, "menuBarIntegration.canOpenMainWindow");
  requireBoolean(menuBarIntegration.canBringWindowsAppsForward, "menuBarIntegration.canBringWindowsAppsForward");
  requireBoolean(menuBarIntegration.canRestorePreviousApps, "menuBarIntegration.canRestorePreviousApps");
  requireBoolean(menuBarIntegration.canReconnectPreviousApps, "menuBarIntegration.canReconnectPreviousApps");
  requireBoolean(menuBarIntegration.canLaunchSelectedApp, "menuBarIntegration.canLaunchSelectedApp");
  requireBoolean(menuBarIntegration.canFulfillPendingLaunch, "menuBarIntegration.canFulfillPendingLaunch");

  if (menuBarIntegration.statusTitle.length > 30) {
    throw new TypeError("menuBarIntegration.statusTitle must stay compact for the menu bar.");
  }

  if (menuBarIntegration.primaryActionTitle.length > 30) {
    throw new TypeError("menuBarIntegration.primaryActionTitle must stay compact for the menu bar.");
  }

  for (const disallowedTerm of ["Runtime", "Guest Agent", "HWND", "QEMU"]) {
    if (menuBarIntegration.statusTitle.includes(disallowedTerm)) {
      throw new TypeError("menuBarIntegration.statusTitle must stay app-first.");
    }
  }

  if (menuBarIntegration.canOpenMainWindow !== report.dockIntegration.canOpenMainWindow) {
    throw new TypeError("menuBarIntegration.canOpenMainWindow must match dockIntegration.canOpenMainWindow.");
  }

  if (menuBarIntegration.canBringWindowsAppsForward !== report.dockIntegration.canBringWindowsAppsForward) {
    throw new TypeError("menuBarIntegration.canBringWindowsAppsForward must match dockIntegration.canBringWindowsAppsForward.");
  }

  if (menuBarIntegration.canRestorePreviousApps !== report.dockIntegration.canRestorePreviousApps) {
    throw new TypeError("menuBarIntegration.canRestorePreviousApps must match dockIntegration.canRestorePreviousApps.");
  }

  if (menuBarIntegration.canReconnectPreviousApps !== report.dockIntegration.canReconnectPreviousApps) {
    throw new TypeError("menuBarIntegration.canReconnectPreviousApps must match dockIntegration.canReconnectPreviousApps.");
  }

  if (menuBarIntegration.canLaunchSelectedApp !== report.launchPlan.canRequestSelectedAppLaunch) {
    throw new TypeError("menuBarIntegration.canLaunchSelectedApp must match launchPlan.canRequestSelectedAppLaunch.");
  }

  const pendingApp = report.apps.find((app) => app.id === report.pendingLaunch.appId);
  const canFulfillPendingLaunch = report.pendingLaunch.isQueued
    && report.connection.hasLiveAgentConnection
    && pendingApp?.canLaunchNow === true;
  if (menuBarIntegration.canFulfillPendingLaunch !== canFulfillPendingLaunch) {
    throw new TypeError("menuBarIntegration.canFulfillPendingLaunch must match queued launch readiness.");
  }

  const expectedSymbol = expectedMenuBarSymbolName(report);
  if (menuBarIntegration.symbolName !== expectedSymbol) {
    throw new TypeError("menuBarIntegration.symbolName must prioritize Windows app state.");
  }
}

function expectedMenuBarSymbolName(report) {
  if (report.mirrorSessions.length > 0) {
    return "rectangle.stack.fill";
  }

  if (report.pendingLaunch.isQueued) {
    return "clock.fill";
  }

  if (report.dockIntegration.canRestorePreviousApps || report.dockIntegration.canReconnectPreviousApps) {
    return "arrow.counterclockwise.circle.fill";
  }

  switch (report.localRuntime.state) {
    case "running":
      return "display";
    case "starting":
      return "arrow.triangle.2.circlepath";
    case "failed":
    case "unsupported":
      return "exclamationmark.triangle";
    default:
      return "play.rectangle";
  }
}

function validateLauncherVisibility(launcherVisibility, report) {
  if (!launcherVisibility || typeof launcherVisibility !== "object" || Array.isArray(launcherVisibility)) {
    throw new TypeError("launcherVisibility must be an object.");
  }

  requireBoolean(launcherVisibility.isEnabled, "launcherVisibility.isEnabled");
  requireBoolean(launcherVisibility.canOpenMainWindow, "launcherVisibility.canOpenMainWindow");
  requireBoolean(launcherVisibility.shouldHideMainWindow, "launcherVisibility.shouldHideMainWindow");
  requireBoolean(launcherVisibility.keepsDockMenuAvailable, "launcherVisibility.keepsDockMenuAvailable");
  requireString(launcherVisibility.recommendedAction, "launcherVisibility.recommendedAction");
  requireString(launcherVisibility.reason, "launcherVisibility.reason");

  if (launcherVisibility.canOpenMainWindow !== report.dockIntegration.canOpenMainWindow) {
    throw new TypeError("launcherVisibility.canOpenMainWindow must match dockIntegration.canOpenMainWindow.");
  }

  if (!launcherVisibility.keepsDockMenuAvailable) {
    throw new TypeError("launcherVisibility.keepsDockMenuAvailable must keep Dock/menu recovery available.");
  }

  if (launcherVisibility.shouldHideMainWindow !== report.macWindowIntegration.hidesLauncherWhenMirroring) {
    throw new TypeError("launcherVisibility.shouldHideMainWindow must match macWindowIntegration.hidesLauncherWhenMirroring.");
  }

  if (launcherVisibility.shouldHideMainWindow) {
    if (!report.connection.hasLiveAgentConnection || report.mirrorSessions.length === 0) {
      throw new TypeError("launcherVisibility.shouldHideMainWindow requires a live mirrored Windows app window.");
    }

    if (launcherVisibility.recommendedAction !== "hide-main-window-use-app-windows") {
      throw new TypeError("launcherVisibility.recommendedAction must hide the launcher while mirrored Windows app windows are open.");
    }
  } else if (launcherVisibility.recommendedAction === "hide-main-window-use-app-windows") {
    throw new TypeError("launcherVisibility.recommendedAction cannot hide the launcher without mirrored Windows app windows.");
  }
}

function validateVisibleSurfacePolicy(visibleSurfacePolicy, report) {
  if (!visibleSurfacePolicy || typeof visibleSurfacePolicy !== "object" || Array.isArray(visibleSurfacePolicy)) {
    throw new TypeError("visibleSurfacePolicy must be an object.");
  }

  requireBoolean(visibleSurfacePolicy.isEnabled, "visibleSurfacePolicy.isEnabled");
  requireString(visibleSurfacePolicy.primarySurface, "visibleSurfacePolicy.primarySurface");
  requireNonNegativeInteger(visibleSurfacePolicy.expectedVisibleSurfaceCount, "visibleSurfacePolicy.expectedVisibleSurfaceCount");
  requireBoolean(visibleSurfacePolicy.shouldHideLauncher, "visibleSurfacePolicy.shouldHideLauncher");
  requireBoolean(visibleSurfacePolicy.keepsRecoveryDisplayManual, "visibleSurfacePolicy.keepsRecoveryDisplayManual");
  requireString(visibleSurfacePolicy.reason, "visibleSurfacePolicy.reason");

  if (!["launcher", "windows-app-windows"].includes(visibleSurfacePolicy.primarySurface)) {
    throw new TypeError("visibleSurfacePolicy.primarySurface must identify a known surface.");
  }

  if (visibleSurfacePolicy.shouldHideLauncher !== report.launcherVisibility.shouldHideMainWindow) {
    throw new TypeError("visibleSurfacePolicy.shouldHideLauncher must match launcherVisibility.shouldHideMainWindow.");
  }

  if (!visibleSurfacePolicy.keepsRecoveryDisplayManual) {
    throw new TypeError("visibleSurfacePolicy.keepsRecoveryDisplayManual must keep VM display recovery manual.");
  }

  if (visibleSurfacePolicy.primarySurface === "windows-app-windows") {
    if (!report.connection.hasLiveAgentConnection || report.mirrorSessions.length === 0) {
      throw new TypeError("visibleSurfacePolicy windows-app-windows requires live mirrored Windows app windows.");
    }
    if (visibleSurfacePolicy.expectedVisibleSurfaceCount !== report.mirrorSessions.length) {
      throw new TypeError("visibleSurfacePolicy expected surface count must match mirrored Windows app windows.");
    }
    if (!visibleSurfacePolicy.shouldHideLauncher) {
      throw new TypeError("visibleSurfacePolicy windows-app-windows must hide the launcher.");
    }
  } else {
    if (visibleSurfacePolicy.expectedVisibleSurfaceCount !== 1) {
      throw new TypeError("visibleSurfacePolicy launcher mode must expect one visible surface.");
    }
    if (visibleSurfacePolicy.shouldHideLauncher) {
      throw new TypeError("visibleSurfacePolicy launcher mode cannot hide the launcher.");
    }
  }
}

function validateOneScreenUX(oneScreenUX, report) {
  if (!oneScreenUX || typeof oneScreenUX !== "object" || Array.isArray(oneScreenUX)) {
    throw new TypeError("oneScreenUX must be an object.");
  }

  requireBoolean(oneScreenUX.isEnabled, "oneScreenUX.isEnabled");
  requireString(oneScreenUX.mode, "oneScreenUX.mode");
  requireNonNegativeInteger(oneScreenUX.expectedVisibleSurfaceCount, "oneScreenUX.expectedVisibleSurfaceCount");
  requireBoolean(oneScreenUX.usesSinglePrimarySurfaceFamily, "oneScreenUX.usesSinglePrimarySurfaceFamily");
  requireBoolean(oneScreenUX.hidesLauncherDuringAppMirroring, "oneScreenUX.hidesLauncherDuringAppMirroring");
  requireBoolean(oneScreenUX.keepsMenuBarControlAvailable, "oneScreenUX.keepsMenuBarControlAvailable");
  requireBoolean(oneScreenUX.keepsDockControlAvailable, "oneScreenUX.keepsDockControlAvailable");
  requireBoolean(oneScreenUX.canRecoverFromMenuOrDock, "oneScreenUX.canRecoverFromMenuOrDock");
  requireBoolean(oneScreenUX.keepsDisplayRecoveryManual, "oneScreenUX.keepsDisplayRecoveryManual");
  requireString(oneScreenUX.reason, "oneScreenUX.reason");

  if (oneScreenUX.primaryActionId !== undefined) {
    requireString(oneScreenUX.primaryActionId, "oneScreenUX.primaryActionId");
  }

  if (!oneScreenUX.isEnabled) {
    throw new TypeError("oneScreenUX must stay enabled for Parallels-style one-screen acceptance.");
  }

  if (oneScreenUX.mode !== report.visibleSurfacePolicy.primarySurface) {
    throw new TypeError("oneScreenUX.mode must match visibleSurfacePolicy.primarySurface.");
  }

  if (oneScreenUX.expectedVisibleSurfaceCount !== report.visibleSurfacePolicy.expectedVisibleSurfaceCount) {
    throw new TypeError("oneScreenUX.expectedVisibleSurfaceCount must match visibleSurfacePolicy.");
  }

  if (!oneScreenUX.usesSinglePrimarySurfaceFamily) {
    throw new TypeError("oneScreenUX must use exactly one primary surface family.");
  }

  const expectedHidesLauncherDuringAppMirroring = report.visibleSurfacePolicy.primarySurface === "windows-app-windows"
    ? report.launcherVisibility.shouldHideMainWindow && report.macWindowIntegration.hidesLauncherWhenMirroring
    : !report.launcherVisibility.shouldHideMainWindow;
  if (oneScreenUX.hidesLauncherDuringAppMirroring !== expectedHidesLauncherDuringAppMirroring) {
    throw new TypeError("oneScreenUX.hidesLauncherDuringAppMirroring must match launcher/app-window policy.");
  }

  if (oneScreenUX.keepsMenuBarControlAvailable !== report.menuBarIntegration.isEnabled) {
    throw new TypeError("oneScreenUX.keepsMenuBarControlAvailable must match menuBarIntegration.isEnabled.");
  }

  if (oneScreenUX.keepsDockControlAvailable !== report.launcherVisibility.keepsDockMenuAvailable) {
    throw new TypeError("oneScreenUX.keepsDockControlAvailable must match launcherVisibility.keepsDockMenuAvailable.");
  }

  const expectedCanRecoverFromMenuOrDock = report.visibleSurfacePolicy.primarySurface === "windows-app-windows"
    ? report.menuBarIntegration.canBringWindowsAppsForward && report.launcherVisibility.keepsDockMenuAvailable
    : report.menuBarIntegration.canOpenMainWindow || report.launcherVisibility.canOpenMainWindow;
  if (oneScreenUX.canRecoverFromMenuOrDock !== expectedCanRecoverFromMenuOrDock) {
    throw new TypeError("oneScreenUX.canRecoverFromMenuOrDock must match menu/Dock recovery readiness.");
  }

  if (!oneScreenUX.canRecoverFromMenuOrDock) {
    throw new TypeError("oneScreenUX must keep a menu or Dock recovery path available.");
  }

  if (oneScreenUX.keepsDisplayRecoveryManual !== report.visibleSurfacePolicy.keepsRecoveryDisplayManual) {
    throw new TypeError("oneScreenUX.keepsDisplayRecoveryManual must match visibleSurfacePolicy.keepsRecoveryDisplayManual.");
  }

  if (report.visibleSurfacePolicy.primarySurface === "windows-app-windows") {
    if (report.mirrorSessions.length === 0 || report.launcherVisibility.shouldHideMainWindow !== true) {
      throw new TypeError("oneScreenUX app-window mode requires mirrored Windows app windows and a hidden launcher.");
    }
  }

  const expectedPrimaryActionId = report.primaryNextAction.actionId ?? report.menuBarIntegration.primaryActionId;
  if (oneScreenUX.primaryActionId !== expectedPrimaryActionId) {
    throw new TypeError("oneScreenUX.primaryActionId must match the executable next action or menu primary action.");
  }

  for (const disallowedTerm of ["Guest Agent", "HWND", "QEMU", "Proof"]) {
    if (oneScreenUX.reason.includes(disallowedTerm)) {
      throw new TypeError("oneScreenUX.reason must stay product-facing.");
    }
  }
}

function validateActions(actions, report) {
  if (!Array.isArray(actions)) {
    throw new TypeError("actions must be an array.");
  }

  const actionIds = new Set(actions.map((action) => action?.id));
  for (const requiredAction of [
    "dock.openMainWindow",
    "dock.bringWindowsAppsForward",
    "windowsApps.restorePrevious",
    "windowsApps.reconnectRestore",
    "windowsApps.closeAll",
    "macWindows.autoOpen",
    "windowsApps.launchSelected",
    "runtime.prepareWindows",
    "runtime.refreshStatus",
    "runtime.startWindowsForApp",
    "runtime.repairGuestAgentForApp",
    "runtime.recoverDisplay",
    "runtime.fulfillPendingLaunch",
    "runtime.waitAgent",
    "runtime.quietWhenIdle",
    "runtime.stopWhenIdle",
    "proof.appWindow",
    "proof.coherence",
    "proof.mvp",
    "proof.recommended",
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

    for (const disallowedTerm of ["Runtime", "Guest Agent", "HWND", "Proof"]) {
      if (action.title.includes(disallowedTerm)) {
        throw new TypeError("action.title must stay product-facing.");
      }
    }
  }

  const startAction = actions.find((action) => action.id === "runtime.startWindowsForApp");
  if (startAction.isAvailable !== (report.launchPlan.recommendedStartCommand !== undefined)) {
    throw new TypeError("runtime.startWindowsForApp availability must match launchPlan.recommendedStartCommand.");
  }

  const prepareAction = actions.find((action) => action.id === "runtime.prepareWindows");
  if (prepareAction.isAvailable !== (report.localRuntime.recommendedPrepareCommand !== undefined)) {
    throw new TypeError("runtime.prepareWindows availability must match localRuntime.recommendedPrepareCommand.");
  }

  const refreshStatusAction = actions.find((action) => action.id === "runtime.refreshStatus");
  if (!refreshStatusAction.isAvailable) {
    throw new TypeError("runtime.refreshStatus must stay available for app-runtime status refresh.");
  }

  const repairAction = actions.find((action) => action.id === "runtime.repairGuestAgentForApp");
  if (repairAction.isAvailable !== (report.launchPlan.recommendedRepairCommand !== undefined)) {
    throw new TypeError("runtime.repairGuestAgentForApp availability must match launchPlan.recommendedRepairCommand.");
  }

  const recoverDisplayAction = actions.find((action) => action.id === "runtime.recoverDisplay");
  if (recoverDisplayAction.isAvailable !== (report.localRuntime.recommendedRecoveryCommand !== undefined)) {
    throw new TypeError("runtime.recoverDisplay availability must match localRuntime.recommendedRecoveryCommand.");
  }

  const reconnectRestoreAction = actions.find((action) => action.id === "windowsApps.reconnectRestore");
  const canReconnectRestore = report.restorableAppIds.length > 0 && report.mirrorSessions.length === 0;
  if (reconnectRestoreAction.isAvailable !== canReconnectRestore) {
    throw new TypeError("windowsApps.reconnectRestore availability must match restorable app readiness.");
  }

  const pendingApp = report.apps.find((app) => app.id === report.pendingLaunch.appId);
  const canFulfillPendingLaunch = report.pendingLaunch.isQueued
    && report.connection.hasLiveAgentConnection
    && pendingApp?.canLaunchNow === true;
  const fulfillPendingAction = actions.find((action) => action.id === "runtime.fulfillPendingLaunch");
  if (fulfillPendingAction.isAvailable !== canFulfillPendingLaunch) {
    throw new TypeError("runtime.fulfillPendingLaunch availability must match queued launch readiness.");
  }

  const waitAgentAction = actions.find((action) => action.id === "runtime.waitAgent");
  if (waitAgentAction.isAvailable !== !report.connection.hasLiveAgentConnection) {
    throw new TypeError("runtime.waitAgent availability must match missing live guest agent connection.");
  }

  const quietAction = actions.find((action) => action.id === "runtime.quietWhenIdle");
  if (quietAction.isAvailable !== report.quietRuntime.canQuietRuntime) {
    throw new TypeError("runtime.quietWhenIdle availability must match quietRuntime.canQuietRuntime.");
  }

  const stopWhenIdleAction = actions.find((action) => action.id === "runtime.stopWhenIdle");
  if (stopWhenIdleAction.isAvailable !== report.quietRuntime.canQuietRuntime) {
    throw new TypeError("runtime.stopWhenIdle availability must match quietRuntime.canQuietRuntime.");
  }

  const launchSelectedAction = actions.find((action) => action.id === "windowsApps.launchSelected");
  if (launchSelectedAction.isAvailable !== report.launchPlan.canRequestSelectedAppLaunch) {
    throw new TypeError("windowsApps.launchSelected availability must match launchPlan.canRequestSelectedAppLaunch.");
  }

  const menuPrimaryAction = actions.find((action) => action.id === report.menuBarIntegration.primaryActionId);
  if (menuPrimaryAction === undefined) {
    throw new TypeError("menuBarIntegration.primaryActionId must reference a supported action.");
  }

  if (report.primaryNextAction.actionId !== undefined) {
    const primaryAction = actions.find((action) => action.id === report.primaryNextAction.actionId);
    if (primaryAction === undefined) {
      throw new TypeError("primaryNextAction.actionId must reference a supported action.");
    }
    if (primaryAction.isAvailable !== report.primaryNextAction.isAvailable) {
      throw new TypeError("primaryNextAction.actionId availability must match the referenced action.");
    }
  }

  if (menuPrimaryAction.isAvailable !== report.menuBarIntegration.primaryActionAvailable) {
    throw new TypeError("menuBarIntegration.primaryActionAvailable must match the referenced action availability.");
  }

  const selectedApp = report.apps.find((app) => app.id === report.selectedAppId);
  const capabilities = report.connection.capabilities;
  const canRunAppWindowProof = report.connection.hasLiveAgentConnection
    && selectedApp?.canLaunchNow === true
    && capabilities?.windowCapture === true;
  const canRunCoherenceProof = canRunAppWindowProof
    && capabilities?.input === true
    && capabilities?.clipboardText === true;

  const appWindowProofAction = actions.find((action) => action.id === "proof.appWindow");
  if (appWindowProofAction.isAvailable !== canRunAppWindowProof
      || appWindowProofAction.isAvailable !== report.proofPlan.canRunAppWindowProof) {
    throw new TypeError("proof.appWindow availability must match live app launch, window capture readiness, and proofPlan.");
  }

  const coherenceProofAction = actions.find((action) => action.id === "proof.coherence");
  if (coherenceProofAction.isAvailable !== canRunCoherenceProof
      || coherenceProofAction.isAvailable !== report.proofPlan.canRunCoherenceProof) {
    throw new TypeError("proof.coherence availability must match input, clipboard proof readiness, and proofPlan.");
  }

  const mvpProofAction = actions.find((action) => action.id === "proof.mvp");
  if (mvpProofAction.isAvailable !== canRunCoherenceProof
      || mvpProofAction.isAvailable !== report.proofPlan.canRunMVPProof) {
    throw new TypeError("proof.mvp availability must match coherence proof readiness and proofPlan.");
  }

  const recommendedProofAction = actions.find((action) => action.id === "proof.recommended");
  if (recommendedProofAction.isAvailable !== (report.proofPlan.recommendedProofCommand !== undefined)) {
    throw new TypeError("proof.recommended availability must match proofPlan.recommendedProofCommand.");
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
