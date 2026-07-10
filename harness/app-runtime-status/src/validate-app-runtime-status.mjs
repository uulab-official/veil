import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_CONNECTION_MODES = new Set(["agent", "demo"]);
const VALID_PHASES = new Set(["idle", "loading", "connected", "launching", "failed"]);
const VALID_CAPTURE_STATES = new Set(["unavailable", "pending", "streaming"]);
const VALID_FRAME_STREAM_STATUSES = new Set(["unavailable", "waitingForFirstFrame", "fresh", "delayed", "stale"]);
const VALID_FRAME_LATENCY_HEALTH = new Set(["idle", "waiting", "healthy", "delayed", "stale"]);
const VALID_PROOF_LATENCY_HEALTH = new Set(["healthy", "delayed", "stale"]);
const VALID_PROOF_COVERAGE_HEALTH = new Set(["missing", "partial", "complete"]);
const MULTI_APP_PROOF_TARGET_APP_IDS = ["winapp_notepad", "winapp_calculator", "winapp_paint"];
const FRAME_LATENCY_BUDGET_MILLISECONDS = 1_000;
const FRAME_STALE_TIMEOUT_MILLISECONDS = 5_000;
const FIRST_FRAME_TIMEOUT_MILLISECONDS = 8_000;
const VALID_CONSOLE_PREVIEW_STATES = new Set(["fresh", "stale", "unavailable"]);
const VALID_AUTOMATIC_INSTALL_MEDIA_STATES = new Set(["current", "stale", "missing", "unavailable"]);
const VALID_INSTALL_EVIDENCE_KINDS = new Set([
  "notConfigured",
  "setupBlocked",
  "sparseDisk",
  "setupReady",
  "profileFlag",
  "guestAgent"
]);

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
  validateLocalRuntime(report.localRuntime, report);
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
  validateDailyUseReadiness(report.dailyUseReadiness, report);
  validateReleaseGate(report.releaseGate, report);
  validatePrimaryNextAction(report.primaryNextAction, report);
  validateMenuBarIntegration(report.menuBarIntegration, report);
  validateOneScreenUX(report.oneScreenUX, report);
  validateLaunchOnboarding(report.launchOnboarding, report);
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

  if (connection.hasLiveAgentConnection) {
    requireString(connection.agentVersion, "connection.agentVersion");
    requireString(connection.os, "connection.os");
  }

  if (!connection.hasLiveAgentConnection) {
    for (const field of ["agentVersion", "os", "capabilities", "packageIdentityStatus"]) {
      if (connection[field] !== undefined) {
        throw new TypeError(`connection.${field} is only allowed when a live agent is connected.`);
      }
    }
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
  }
  if (connection.packageIdentityStatus !== undefined) {
    validatePackageIdentityStatus(connection.packageIdentityStatus, "connection.packageIdentityStatus");
  }
}

function validateCapabilities(capabilities) {
  if (!capabilities || typeof capabilities !== "object" || Array.isArray(capabilities)) {
    throw new TypeError("connection.capabilities must be an object.");
  }

  for (const field of [
    "appList",
    "appLaunch",
    "windowTracking",
    "windowCapture",
    "input",
    "clipboardText",
    "packageIdentity"
  ]) {
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

function validateLocalRuntime(localRuntime, report) {
  if (!localRuntime || typeof localRuntime !== "object" || Array.isArray(localRuntime)) {
    throw new TypeError("localRuntime must be an object.");
  }

  requireBoolean(localRuntime.isKnown, "localRuntime.isKnown");
  requireBoolean(localRuntime.bootReady, "localRuntime.bootReady");
  requireBoolean(localRuntime.canStart, "localRuntime.canStart");
  requireBoolean(localRuntime.isRunning, "localRuntime.isRunning");
  requireBoolean(localRuntime.windowsInstalled, "localRuntime.windowsInstalled");
  if (localRuntime.requiresGuestToolsMediaRebuild !== undefined) {
    requireBoolean(localRuntime.requiresGuestToolsMediaRebuild, "localRuntime.requiresGuestToolsMediaRebuild");
  }
  requireString(localRuntime.recommendedAction, "localRuntime.recommendedAction");
  requireString(localRuntime.recommendedInstallStatusCommand, "localRuntime.recommendedInstallStatusCommand");
  requireString(localRuntime.reason, "localRuntime.reason");

  if (localRuntime.automaticInstallMediaStatus !== undefined) {
    validateAutomaticInstallMediaStatus(localRuntime.automaticInstallMediaStatus);
  }

  if (localRuntime.installEvidence !== undefined) {
    validateInstallEvidence(localRuntime.installEvidence);
    if (localRuntime.installEvidence.isInstalled !== localRuntime.windowsInstalled) {
      throw new TypeError("localRuntime.installEvidence.isInstalled must match localRuntime.windowsInstalled.");
    }
  } else if (localRuntime.isKnown || report.connection.hasLiveAgentConnection) {
    throw new TypeError("localRuntime.installEvidence is required for known local runtime state.");
  }

  if (report.connection.hasLiveAgentConnection) {
    if (localRuntime.installEvidence?.kind !== "guestAgent") {
      throw new TypeError("live app connections must use guest-agent install evidence.");
    }
    if (localRuntime.windowsInstalled !== true) {
      throw new TypeError("live app connections require localRuntime.windowsInstalled.");
    }
  }

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

  if (localRuntime.recommendedMediaRebuildCommand !== undefined) {
    requireString(localRuntime.recommendedMediaRebuildCommand, "localRuntime.recommendedMediaRebuildCommand");
  }

  if (localRuntime.recommendedPowerDownCommand !== undefined) {
    requireString(localRuntime.recommendedPowerDownCommand, "localRuntime.recommendedPowerDownCommand");
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

  if (localRuntime.requiresGuestToolsMediaRebuild) {
    if (localRuntime.recommendedAction !== "rebuild-guest-tools-media") {
      throw new TypeError("localRuntime.requiresGuestToolsMediaRebuild requires recommendedAction rebuild-guest-tools-media.");
    }
    if (localRuntime.canStart) {
      throw new TypeError("localRuntime.canStart must be false while guest tools media needs rebuild.");
    }
    if (!["stale", "missing"].includes(localRuntime.automaticInstallMediaStatus?.state)) {
      throw new TypeError("localRuntime.requiresGuestToolsMediaRebuild requires stale or missing automatic install media status.");
    }
    if (localRuntime.recommendedMediaRebuildCommand === undefined
      || !localRuntime.recommendedMediaRebuildCommand.includes("veil-vmctl prepare --installer")) {
      throw new TypeError("localRuntime.requiresGuestToolsMediaRebuild requires a media rebuild command.");
    }
    if (localRuntime.isRunning) {
      if (localRuntime.recommendedPowerDownCommand !== "veil-vmctl app-runtime-action --json --action stop-runtime") {
        throw new TypeError("running stale guest tools media must power down through app-runtime stop-runtime.");
      }
      if (localRuntime.recommendedPrepareCommand !== undefined) {
        throw new TypeError("running stale guest tools media must not expose prepare before powerdown.");
      }
    }
  }
}

function validateInstallEvidence(installEvidence) {
  if (!installEvidence || typeof installEvidence !== "object" || Array.isArray(installEvidence)) {
    throw new TypeError("localRuntime.installEvidence must be an object.");
  }

  requireString(installEvidence.kind, "localRuntime.installEvidence.kind");
  if (!VALID_INSTALL_EVIDENCE_KINDS.has(installEvidence.kind)) {
    throw new TypeError(`Unsupported localRuntime.installEvidence.kind: ${installEvidence.kind}`);
  }
  requireBoolean(installEvidence.isInstalled, "localRuntime.installEvidence.isInstalled");
  requireString(installEvidence.title, "localRuntime.installEvidence.title");
  requireString(installEvidence.detail, "localRuntime.installEvidence.detail");

  if (installEvidence.kind === "guestAgent" && !installEvidence.isInstalled) {
    throw new TypeError("guest-agent install evidence must mark Windows installed.");
  }
  if (installEvidence.kind === "profileFlag" && !installEvidence.isInstalled) {
    throw new TypeError("profile-flag install evidence must mark Windows installed.");
  }
  if (["notConfigured", "setupBlocked", "sparseDisk", "setupReady"].includes(installEvidence.kind)
    && installEvidence.isInstalled) {
    throw new TypeError("pre-install evidence kinds must not mark Windows installed.");
  }
}

function validateAutomaticInstallMediaStatus(status) {
  if (!status || typeof status !== "object" || Array.isArray(status)) {
    throw new TypeError("localRuntime.automaticInstallMediaStatus must be an object.");
  }

  requireString(status.state, "localRuntime.automaticInstallMediaStatus.state");
  if (!VALID_AUTOMATIC_INSTALL_MEDIA_STATES.has(status.state)) {
    throw new TypeError(`Unsupported automatic install media state: ${status.state}`);
  }
  requireBoolean(status.isCurrent, "localRuntime.automaticInstallMediaStatus.isCurrent");
  requireString(status.recommendedAction, "localRuntime.automaticInstallMediaStatus.recommendedAction");
  requireBoolean(status.requiresRelaunch, "localRuntime.automaticInstallMediaStatus.requiresRelaunch");
  requireString(status.detail, "localRuntime.automaticInstallMediaStatus.detail");

  for (const field of ["mediaPath", "sourcePath", "rebuildCommand"]) {
    if (status[field] !== undefined) {
      requireString(status[field], `localRuntime.automaticInstallMediaStatus.${field}`);
    }
  }
  for (const field of ["mediaModifiedAt", "sourceModifiedAt"]) {
    if (status[field] !== undefined && Number.isNaN(Date.parse(status[field]))) {
      throw new TypeError(`localRuntime.automaticInstallMediaStatus.${field} must be an ISO date.`);
    }
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
    requireString(session.frameStreamStatus, "session.frameStreamStatus");
    if (!VALID_FRAME_STREAM_STATUSES.has(session.frameStreamStatus)) {
      throw new TypeError(`Unsupported frame stream status: ${session.frameStreamStatus}`);
    }
    requireNonNegativeInteger(session.receivedFrameCount, "session.receivedFrameCount");
    requireString(session.frameStreamRecommendedAction, "session.frameStreamRecommendedAction");
    requireNonNegativeInteger(session.frameStreamRestartCount, "session.frameStreamRestartCount");
    requireBoolean(session.frameStreamRecoveryEscalated, "session.frameStreamRecoveryEscalated");
    requireBoolean(session.frameStreamReopenEscalated, "session.frameStreamReopenEscalated");
    if (session.frameStreamRequestedAt !== undefined) {
      requireString(session.frameStreamRequestedAt, "session.frameStreamRequestedAt");
      if (Number.isNaN(Date.parse(session.frameStreamRequestedAt))) {
        throw new TypeError("session.frameStreamRequestedAt must be an ISO date.");
      }
    }
    if (session.latestFrameReceivedAt !== undefined) {
      requireString(session.latestFrameReceivedAt, "session.latestFrameReceivedAt");
      if (Number.isNaN(Date.parse(session.latestFrameReceivedAt))) {
        throw new TypeError("session.latestFrameReceivedAt must be an ISO date.");
      }
    }
    if (session.latestFrameAgeMilliseconds !== undefined) {
      requireNonNegativeInteger(session.latestFrameAgeMilliseconds, "session.latestFrameAgeMilliseconds");
    }
    if (session.latestFrameIntervalMilliseconds !== undefined) {
      requireNonNegativeInteger(session.latestFrameIntervalMilliseconds, "session.latestFrameIntervalMilliseconds");
    }
    if (session.frameStreamWaitingAgeMilliseconds !== undefined) {
      requireNonNegativeInteger(session.frameStreamWaitingAgeMilliseconds, "session.frameStreamWaitingAgeMilliseconds");
    }
    if (session.latestFrameStreamRestartedAt !== undefined) {
      requireString(session.latestFrameStreamRestartedAt, "session.latestFrameStreamRestartedAt");
      if (Number.isNaN(Date.parse(session.latestFrameStreamRestartedAt))) {
        throw new TypeError("session.latestFrameStreamRestartedAt must be an ISO date.");
      }
    }
    if (session.frameStreamRestartCount === 0 && session.latestFrameStreamRestartedAt !== undefined) {
      throw new TypeError("latestFrameStreamRestartedAt requires at least one frame stream restart.");
    }
    if (session.frameStreamRestartCount > 0 && session.latestFrameStreamRestartedAt === undefined) {
      throw new TypeError("frameStreamRestartCount requires latestFrameStreamRestartedAt.");
    }
    if (session.captureState === "unavailable" && session.frameStreamStatus !== "unavailable") {
      throw new TypeError("Unavailable capture sessions must report unavailable frame streams.");
    }
    const timedOutWaitingForFirstFrame = session.receivedFrameCount === 0
      && session.frameStreamStatus === "stale"
      && session.frameStreamWaitingAgeMilliseconds >= FIRST_FRAME_TIMEOUT_MILLISECONDS;
    if (session.captureState !== "unavailable"
      && session.receivedFrameCount === 0
      && session.frameStreamStatus !== "waitingForFirstFrame"
      && !timedOutWaitingForFirstFrame) {
      throw new TypeError("Capture sessions without received frames must wait for the first frame unless first-frame delivery timed out.");
    }
    if (session.receivedFrameCount === 0) {
      if (session.latestFrameReceivedAt !== undefined || session.latestFrameAgeMilliseconds !== undefined || session.latestFrameIntervalMilliseconds !== undefined) {
        throw new TypeError("Frame timing fields require at least one received frame.");
      }
      if (session.captureState !== "unavailable" && session.frameStreamRequestedAt === undefined) {
        throw new TypeError("Capture sessions waiting for frames require frameStreamRequestedAt.");
      }
    } else {
      if (session.latestFrameReceivedAt === undefined || session.latestFrameAgeMilliseconds === undefined) {
        throw new TypeError("Received frames require latest frame timing fields.");
      }
      if (session.frameStreamStatus === "waitingForFirstFrame" || session.frameStreamStatus === "unavailable") {
        throw new TypeError("Received frames require an active frame stream status.");
      }
    }
    const shouldEscalateFrameReopen = session.frameStreamStatus === "stale" && session.frameStreamRestartCount >= 3;
    if (session.frameStreamReopenEscalated !== shouldEscalateFrameReopen) {
      throw new TypeError("frameStreamReopenEscalated must reflect repeated stale frame capture recovery attempts.");
    }
    const shouldEscalateFrameRecovery = session.frameStreamStatus === "stale"
      && session.frameStreamRestartCount >= 2
      && !shouldEscalateFrameReopen;
    if (session.frameStreamRecoveryEscalated !== shouldEscalateFrameRecovery) {
      throw new TypeError("frameStreamRecoveryEscalated must reflect repeated stale frame stream restarts.");
    }
    const expectedFrameAction = expectedFrameStreamRecommendedAction(session);
    if (session.frameStreamRecommendedAction !== expectedFrameAction) {
      throw new TypeError("frameStreamRecommendedAction must match frame stream state.");
    }
    requireBoolean(session.canFocus, "session.canFocus");
    requireBoolean(session.canClose, "session.canClose");
    requireBoolean(session.canSendInput, "session.canSendInput");
  }
}

function expectedFrameStreamRecommendedAction(session) {
  switch (session.frameStreamStatus) {
    case "unavailable":
      return "enable-window-capture";
    case "waitingForFirstFrame":
      return "wait-for-first-frame";
    case "fresh":
      return "none";
    case "delayed":
      return "refresh-runtime-status";
    case "stale":
      if (session.frameStreamReopenEscalated) {
        return "reopen-windows-app";
      }
      return session.frameStreamRecoveryEscalated ? "recover-window-capture" : "restart-frame-subscription";
    default:
      throw new TypeError(`Unsupported frame stream status: ${session.frameStreamStatus}`);
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
  requireNonNegativeInteger(macWindowIntegration.freshFrameWindowCount, "macWindowIntegration.freshFrameWindowCount");
  requireNonNegativeInteger(macWindowIntegration.delayedFrameWindowCount, "macWindowIntegration.delayedFrameWindowCount");
  requireNonNegativeInteger(macWindowIntegration.staleFrameWindowCount, "macWindowIntegration.staleFrameWindowCount");
  requireString(macWindowIntegration.frameLatencyHealth, "macWindowIntegration.frameLatencyHealth");
  if (!VALID_FRAME_LATENCY_HEALTH.has(macWindowIntegration.frameLatencyHealth)) {
    throw new TypeError(`Unsupported frame latency health: ${macWindowIntegration.frameLatencyHealth}`);
  }
  requireNonNegativeInteger(macWindowIntegration.frameLatencyBudgetMilliseconds, "macWindowIntegration.frameLatencyBudgetMilliseconds");
  requireNonNegativeInteger(macWindowIntegration.frameStaleTimeoutMilliseconds, "macWindowIntegration.frameStaleTimeoutMilliseconds");
  requireString(macWindowIntegration.frameLatencyRecommendedAction, "macWindowIntegration.frameLatencyRecommendedAction");
  requireString(macWindowIntegration.reason, "macWindowIntegration.reason");
  if (macWindowIntegration.slowestFrameWindowId !== undefined) {
    requireString(macWindowIntegration.slowestFrameWindowId, "macWindowIntegration.slowestFrameWindowId");
  }
  if (macWindowIntegration.slowestFrameWindowTitle !== undefined) {
    requireString(macWindowIntegration.slowestFrameWindowTitle, "macWindowIntegration.slowestFrameWindowTitle");
  }
  if (macWindowIntegration.slowestFrameAgeMilliseconds !== undefined) {
    requireNonNegativeInteger(macWindowIntegration.slowestFrameAgeMilliseconds, "macWindowIntegration.slowestFrameAgeMilliseconds");
  }
  if (macWindowIntegration.frameLatencyBudgetMilliseconds !== FRAME_LATENCY_BUDGET_MILLISECONDS) {
    throw new TypeError("macWindowIntegration.frameLatencyBudgetMilliseconds must match the fresh frame budget.");
  }
  if (macWindowIntegration.frameStaleTimeoutMilliseconds !== FRAME_STALE_TIMEOUT_MILLISECONDS) {
    throw new TypeError("macWindowIntegration.frameStaleTimeoutMilliseconds must match the stale frame timeout.");
  }

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

  if (macWindowIntegration.freshFrameWindowCount !== mirrorSessions.filter((session) => session.frameStreamStatus === "fresh").length) {
    throw new TypeError("macWindowIntegration.freshFrameWindowCount must match fresh frame streams.");
  }

  if (macWindowIntegration.delayedFrameWindowCount !== mirrorSessions.filter((session) => session.frameStreamStatus === "delayed").length) {
    throw new TypeError("macWindowIntegration.delayedFrameWindowCount must match delayed frame streams.");
  }

  if (macWindowIntegration.staleFrameWindowCount !== mirrorSessions.filter((session) => session.frameStreamStatus === "stale").length) {
    throw new TypeError("macWindowIntegration.staleFrameWindowCount must match stale frame streams.");
  }

  if (macWindowIntegration.pendingFrameWindowCount + macWindowIntegration.streamingWindowCount > macWindowIntegration.mirroredWindowCount) {
    throw new TypeError("macWindowIntegration frame counts cannot exceed mirroredWindowCount.");
  }

  if (macWindowIntegration.freshFrameWindowCount + macWindowIntegration.delayedFrameWindowCount + macWindowIntegration.staleFrameWindowCount > macWindowIntegration.mirroredWindowCount) {
    throw new TypeError("Mac frame stream quality counts cannot exceed mirroredWindowCount.");
  }

  const expectedFrameLatencyHealth = expectedMacFrameLatencyHealth(mirrorSessions, connection);
  if (macWindowIntegration.frameLatencyHealth !== expectedFrameLatencyHealth) {
    throw new TypeError("macWindowIntegration.frameLatencyHealth must match aggregate frame stream state.");
  }
  const expectedFrameLatencyAction = expectedMacFrameLatencyRecommendedAction(mirrorSessions, connection);
  if (macWindowIntegration.frameLatencyRecommendedAction !== expectedFrameLatencyAction) {
    throw new TypeError("macWindowIntegration.frameLatencyRecommendedAction must match aggregate frame stream state.");
  }
  const expectedSlowestFrame = expectedMacSlowestFrame(mirrorSessions);
  if (!expectedSlowestFrame) {
    if (macWindowIntegration.slowestFrameWindowId !== undefined
      || macWindowIntegration.slowestFrameWindowTitle !== undefined
      || macWindowIntegration.slowestFrameAgeMilliseconds !== undefined) {
      throw new TypeError("macWindowIntegration slowest frame fields must be omitted when no frame age is known.");
    }
  } else if (
    macWindowIntegration.slowestFrameWindowId !== expectedSlowestFrame.windowId
    || macWindowIntegration.slowestFrameWindowTitle !== expectedSlowestFrame.title
    || macWindowIntegration.slowestFrameAgeMilliseconds !== expectedSlowestFrame.age
  ) {
    throw new TypeError("macWindowIntegration slowest frame fields must match the slowest mirror session.");
  }

  if (macWindowIntegration.acceptsGuestWindowEvents !== connection.hasLiveAgentConnection) {
    throw new TypeError("macWindowIntegration.acceptsGuestWindowEvents must reflect live agent connection.");
  }

  if (macWindowIntegration.hidesLauncherWhenMirroring && (!connection.hasLiveAgentConnection || mirrorSessions.length === 0)) {
    throw new TypeError("macWindowIntegration.hidesLauncherWhenMirroring requires a live mirrored Windows app window.");
  }
}

function expectedMacFrameLatencyHealth(mirrorSessions, connection) {
  if (!connection.hasLiveAgentConnection || mirrorSessions.length === 0) {
    return "idle";
  }
  if (mirrorSessions.some((session) => session.frameStreamStatus === "stale")) {
    return "stale";
  }
  if (mirrorSessions.some((session) => session.frameStreamStatus === "delayed")) {
    return "delayed";
  }
  if (mirrorSessions.some((session) => session.frameStreamStatus === "waitingForFirstFrame")) {
    return "waiting";
  }
  return "healthy";
}

function expectedMacFrameLatencyRecommendedAction(mirrorSessions, connection) {
  const health = expectedMacFrameLatencyHealth(mirrorSessions, connection);
  if (!connection.hasLiveAgentConnection) {
    return "wait-for-agent";
  }
  if (mirrorSessions.length === 0) {
    return "open-windows-app";
  }
  switch (health) {
    case "healthy":
      return "none";
    case "waiting":
      return "wait-for-first-frame";
    case "delayed":
      return "refresh-runtime-status";
    case "stale":
      return "maintain-frame-streams";
    default:
      throw new TypeError(`Unsupported frame latency health: ${health}`);
  }
}

function expectedMacSlowestFrame(mirrorSessions) {
  let slowest;
  for (const session of mirrorSessions) {
    const age = session.latestFrameAgeMilliseconds ?? session.frameStreamWaitingAgeMilliseconds;
    if (age === undefined) {
      continue;
    }
    if (!slowest || age > slowest.age) {
      slowest = {
        windowId: session.windowId,
        title: session.title,
        age
      };
    }
  }
  return slowest;
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
    || (launchPlan.canRequestSelectedAppLaunch
      && !["prepare-local-runtime", "rebuild-guest-tools-media-before-launch"].includes(launchPlan.recommendedAction));
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
    && !["prepare-local-runtime", "rebuild-guest-tools-media-before-launch"].includes(launchPlan.recommendedAction)) {
    throw new TypeError("launchPlan.requiresGuestAgent requires recommendedWaitCommand.");
  }

  if (launchPlan.recommendedRepairCommand !== undefined) {
    if (report.localRuntime.requiresGuestToolsMediaRebuild) {
      throw new TypeError("stale guest tools media must not expose guest-agent repair.");
    }
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

  if (report.localRuntime.requiresGuestToolsMediaRebuild) {
    if (launchPlan.recommendedAction !== "rebuild-guest-tools-media-before-launch") {
      throw new TypeError("stale guest tools media must block launchPlan with rebuild-guest-tools-media-before-launch.");
    }
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

function validateDailyUseReadiness(dailyUseReadiness, report) {
  if (!dailyUseReadiness || typeof dailyUseReadiness !== "object" || Array.isArray(dailyUseReadiness)) {
    throw new TypeError("dailyUseReadiness must be an object.");
  }

  requireBoolean(dailyUseReadiness.isEnabled, "dailyUseReadiness.isEnabled");
  requireBoolean(dailyUseReadiness.packageIdentityReady, "dailyUseReadiness.packageIdentityReady");
  requireBoolean(
    dailyUseReadiness.borderlessCapturePreflightPassed,
    "dailyUseReadiness.borderlessCapturePreflightPassed"
  );
  requireString(dailyUseReadiness.borderlessCaptureRecommendedAction, "dailyUseReadiness.borderlessCaptureRecommendedAction");
  requireString(dailyUseReadiness.borderlessCaptureRequirement, "dailyUseReadiness.borderlessCaptureRequirement");
  requireBoolean(
    dailyUseReadiness.notificationBridgePreflightPassed,
    "dailyUseReadiness.notificationBridgePreflightPassed"
  );
  requireString(dailyUseReadiness.notificationBridgeRecommendedAction, "dailyUseReadiness.notificationBridgeRecommendedAction");
  requireString(dailyUseReadiness.notificationBridgeRequirement, "dailyUseReadiness.notificationBridgeRequirement");
  requireString(dailyUseReadiness.printerBridgeMode, "dailyUseReadiness.printerBridgeMode");
  requireString(dailyUseReadiness.printerBridgeRecommendedAction, "dailyUseReadiness.printerBridgeRecommendedAction");
  requireString(dailyUseReadiness.printerBridgeEndpointTemplate, "dailyUseReadiness.printerBridgeEndpointTemplate");
  requireString(dailyUseReadiness.printerBridgeSetupHint, "dailyUseReadiness.printerBridgeSetupHint");
  requireString(dailyUseReadiness.recommendedAction, "dailyUseReadiness.recommendedAction");
  requireString(dailyUseReadiness.reason, "dailyUseReadiness.reason");
  if (dailyUseReadiness.recommendedCommand !== undefined) {
    requireString(dailyUseReadiness.recommendedCommand, "dailyUseReadiness.recommendedCommand");
  }
  if (dailyUseReadiness.packageIdentityStatus !== undefined) {
    validatePackageIdentityStatus(dailyUseReadiness.packageIdentityStatus, "dailyUseReadiness.packageIdentityStatus");
  }
  if (dailyUseReadiness.packageIdentityStage !== undefined) {
    requireString(dailyUseReadiness.packageIdentityStage, "dailyUseReadiness.packageIdentityStage");
  }
  if (dailyUseReadiness.packageIdentitySucceeded !== undefined) {
    requireBoolean(dailyUseReadiness.packageIdentitySucceeded, "dailyUseReadiness.packageIdentitySucceeded");
  }
  if (dailyUseReadiness.packageIdentityMessage !== undefined) {
    requireString(dailyUseReadiness.packageIdentityMessage, "dailyUseReadiness.packageIdentityMessage");
  }
  if (dailyUseReadiness.packageIdentityEvidencePath !== undefined) {
    requireString(dailyUseReadiness.packageIdentityEvidencePath, "dailyUseReadiness.packageIdentityEvidencePath");
  }

  if (dailyUseReadiness.isEnabled !== true) {
    throw new TypeError("dailyUseReadiness must stay enabled for v1.5 readiness tracking.");
  }

  if (!dailyUseReadiness.borderlessCaptureRequirement.includes("signed sparse package identity")
    || !dailyUseReadiness.borderlessCaptureRequirement.includes("windowCapture capability")) {
    throw new TypeError("dailyUseReadiness.borderlessCaptureRequirement must explain the package identity and windowCapture prerequisites.");
  }
  if (!dailyUseReadiness.notificationBridgeRequirement.includes("signed sparse package identity")
    || !dailyUseReadiness.notificationBridgeRequirement.includes("Windows UserNotificationListener consent")) {
    throw new TypeError("dailyUseReadiness.notificationBridgeRequirement must explain the package identity and notification listener consent prerequisites.");
  }

  if (dailyUseReadiness.printerBridgeMode !== "manual-ipp-experiment") {
    throw new TypeError("dailyUseReadiness.printerBridgeMode must preserve the current IPP printer experiment path.");
  }
  if (dailyUseReadiness.printerBridgeRecommendedAction !== "manual-ipp-experiment") {
    throw new TypeError("dailyUseReadiness.printerBridgeRecommendedAction must preserve the current IPP printer experiment path.");
  }
  if (dailyUseReadiness.printerBridgeEndpointTemplate !== "http://10.0.2.2:631/printers/<shared-printer-name>") {
    throw new TypeError("dailyUseReadiness.printerBridgeEndpointTemplate must expose the QEMU user-network IPP endpoint template.");
  }
  if (!dailyUseReadiness.printerBridgeSetupHint.includes("Share the Mac printer")
    || !dailyUseReadiness.printerBridgeSetupHint.includes("IPP network printer")) {
    throw new TypeError("dailyUseReadiness.printerBridgeSetupHint must explain the manual Mac printer sharing and Windows IPP setup path.");
  }

  const capabilities = report.connection.capabilities;
  const expectedPackageIdentityReady = report.connection.hasLiveAgentConnection
    && capabilities?.packageIdentity === true;
  const expectedBorderlessCapturePreflight = expectedPackageIdentityReady
    && capabilities?.windowCapture === true;
  const expectedBorderlessAction = !report.connection.hasLiveAgentConnection
    ? "connect-agent"
    : expectedPackageIdentityReady
      ? expectedBorderlessCapturePreflight
        ? "verify-daily-use-integrations"
        : "verify-window-capture"
      : "prepare-sparse-package";
  const expectedNotificationAction = !report.connection.hasLiveAgentConnection
    ? "connect-agent"
    : expectedPackageIdentityReady
      ? "verify-notification-listener-consent"
      : "prepare-sparse-package";

  if (dailyUseReadiness.packageIdentityReady !== expectedPackageIdentityReady) {
    throw new TypeError("dailyUseReadiness.packageIdentityReady must match live package identity readiness.");
  }

  if (dailyUseReadiness.borderlessCapturePreflightPassed !== expectedBorderlessCapturePreflight) {
    throw new TypeError("dailyUseReadiness.borderlessCapturePreflightPassed must require package identity and window capture.");
  }
  if (dailyUseReadiness.borderlessCaptureRecommendedAction !== expectedBorderlessAction) {
    throw new TypeError("dailyUseReadiness.borderlessCaptureRecommendedAction must match the current borderless capture gate.");
  }

  if (dailyUseReadiness.notificationBridgePreflightPassed !== expectedPackageIdentityReady) {
    throw new TypeError("dailyUseReadiness.notificationBridgePreflightPassed must require package identity.");
  }
  if (dailyUseReadiness.notificationBridgeRecommendedAction !== expectedNotificationAction) {
    throw new TypeError("dailyUseReadiness.notificationBridgeRecommendedAction must match the current notification bridge gate.");
  }

  if (JSON.stringify(dailyUseReadiness.packageIdentityStatus) !== JSON.stringify(report.connection.packageIdentityStatus)) {
    throw new TypeError("dailyUseReadiness.packageIdentityStatus must match connection.packageIdentityStatus.");
  }
  if (dailyUseReadiness.packageIdentityStatus !== undefined) {
    const status = dailyUseReadiness.packageIdentityStatus;
    if (dailyUseReadiness.packageIdentityStage !== status.stage) {
      throw new TypeError("dailyUseReadiness.packageIdentityStage must summarize packageIdentityStatus.stage.");
    }
    if (dailyUseReadiness.packageIdentitySucceeded !== status.succeeded) {
      throw new TypeError("dailyUseReadiness.packageIdentitySucceeded must summarize packageIdentityStatus.succeeded.");
    }
    if (dailyUseReadiness.packageIdentityMessage !== status.message) {
      throw new TypeError("dailyUseReadiness.packageIdentityMessage must summarize packageIdentityStatus.message.");
    }
    if (dailyUseReadiness.packageIdentityEvidencePath !== status.statusPath) {
      throw new TypeError("dailyUseReadiness.packageIdentityEvidencePath must summarize packageIdentityStatus.statusPath.");
    }
  } else if (
    dailyUseReadiness.packageIdentityStage !== undefined
    || dailyUseReadiness.packageIdentitySucceeded !== undefined
    || dailyUseReadiness.packageIdentityMessage !== undefined
    || dailyUseReadiness.packageIdentityEvidencePath !== undefined
  ) {
    throw new TypeError("dailyUseReadiness package identity summary fields require packageIdentityStatus evidence.");
  }

  const expectedAction = report.connection.hasLiveAgentConnection
    ? expectedPackageIdentityReady
      ? expectedBorderlessCapturePreflight
        ? "verify-daily-use-integrations"
        : "verify-window-capture"
      : "prepare-sparse-package"
    : "connect-agent";
  if (dailyUseReadiness.recommendedAction !== expectedAction) {
    throw new TypeError("dailyUseReadiness.recommendedAction must match the next Daily Use readiness gate.");
  }

  const expectedCommand = report.connection.hasLiveAgentConnection
    ? expectedPackageIdentityReady
      ? expectedBorderlessCapturePreflight && report.proofPlan.recommendedProofCommand !== undefined
        ? "veil-vmctl app-runtime-action --json --action proof-recommended"
        : "veil-vmctl app-runtime-status --json"
      : "veil-vmctl app-runtime-action --json --action prepare-sparse-package --wait-seconds 120"
    : "veil-vmctl guest-agent-wait --json --wait-seconds 30";
  if (dailyUseReadiness.recommendedCommand !== expectedCommand) {
    throw new TypeError("dailyUseReadiness.recommendedCommand must match the Daily Use readiness gate.");
  }
}

function validatePackageIdentityStatus(status, path) {
  if (!status || typeof status !== "object" || Array.isArray(status)) {
    throw new TypeError(`${path} must be an object when present.`);
  }
  requireString(status.statusPath, `${path}.statusPath`);
  requireString(status.stage, `${path}.stage`);
  requireBoolean(status.succeeded, `${path}.succeeded`);
  for (const field of ["message", "updatedAt", "packagePath", "certificatePath"]) {
    if (status[field] !== undefined) {
      requireString(status[field], `${path}.${field}`);
    }
  }
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
  validateProofArtifactCoverage(proofArtifacts);

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

  validateProofArtifactLatency(proofArtifacts);
}

function validateProofArtifactCoverage(proofArtifacts) {
  const hasCoverage = proofArtifacts.multiAppProofTargetAppIds !== undefined
    || proofArtifacts.multiAppProofCoverageCount !== undefined
    || proofArtifacts.multiAppProofCoverageHealth !== undefined
    || proofArtifacts.latestProofsByApp !== undefined;

  if (!hasCoverage) {
    return;
  }

  if (!Array.isArray(proofArtifacts.multiAppProofTargetAppIds)) {
    throw new TypeError("proofArtifacts.multiAppProofTargetAppIds must be an array.");
  }
  if (JSON.stringify(proofArtifacts.multiAppProofTargetAppIds) !== JSON.stringify(MULTI_APP_PROOF_TARGET_APP_IDS)) {
    throw new TypeError("proofArtifacts.multiAppProofTargetAppIds must match the Daily Use proof target apps.");
  }
  requireNonNegativeInteger(proofArtifacts.multiAppProofCoverageCount, "proofArtifacts.multiAppProofCoverageCount");
  requireString(proofArtifacts.multiAppProofCoverageHealth, "proofArtifacts.multiAppProofCoverageHealth");
  if (!VALID_PROOF_COVERAGE_HEALTH.has(proofArtifacts.multiAppProofCoverageHealth)) {
    throw new TypeError("proofArtifacts.multiAppProofCoverageHealth must be missing, partial, or complete.");
  }
  if (!Array.isArray(proofArtifacts.latestProofsByApp)) {
    throw new TypeError("proofArtifacts.latestProofsByApp must be an array.");
  }

  const seenAppIds = new Set();
  for (const proof of proofArtifacts.latestProofsByApp) {
    validateProofArtifactAppSummary(proof);
    if (seenAppIds.has(proof.appId)) {
      throw new TypeError("proofArtifacts.latestProofsByApp must contain at most one summary per app.");
    }
    seenAppIds.add(proof.appId);
  }

  const expectedCoverageCount = MULTI_APP_PROOF_TARGET_APP_IDS
    .filter((appId) => seenAppIds.has(appId))
    .length;
  if (proofArtifacts.multiAppProofCoverageCount !== expectedCoverageCount) {
    throw new TypeError("proofArtifacts.multiAppProofCoverageCount must match latestProofsByApp target coverage.");
  }

  const expectedHealth = expectedCoverageCount === MULTI_APP_PROOF_TARGET_APP_IDS.length
    ? "complete"
    : expectedCoverageCount > 0
      ? "partial"
      : "missing";
  if (proofArtifacts.multiAppProofCoverageHealth !== expectedHealth) {
    throw new TypeError("proofArtifacts.multiAppProofCoverageHealth must match target app coverage.");
  }
}

function validateProofArtifactAppSummary(proof) {
  if (!proof || typeof proof !== "object" || Array.isArray(proof)) {
    throw new TypeError("proofArtifacts.latestProofsByApp[] must be an object.");
  }

  requireString(proof.appId, "proofArtifacts.latestProofsByApp[].appId");
  requireString(proof.latestProofKind, "proofArtifacts.latestProofsByApp[].latestProofKind");
  if (!["recommended", "app-window", "coherence", "mvp"].includes(proof.latestProofKind)) {
    throw new TypeError("proofArtifacts.latestProofsByApp[].latestProofKind must identify a known proof kind.");
  }
  requireString(proof.latestProofPath, "proofArtifacts.latestProofsByApp[].latestProofPath");
  requireString(proof.latestProofFileName, "proofArtifacts.latestProofsByApp[].latestProofFileName");
  if (!proof.latestProofPath.endsWith(".json") || !proof.latestProofFileName.endsWith(".json")) {
    throw new TypeError("proofArtifacts.latestProofsByApp[] latest artifact must point to a JSON file.");
  }
  requireString(proof.latestProofModifiedAt, "proofArtifacts.latestProofsByApp[].latestProofModifiedAt");
  if (Number.isNaN(Date.parse(proof.latestProofModifiedAt))) {
    throw new TypeError("proofArtifacts.latestProofsByApp[].latestProofModifiedAt must be an ISO date.");
  }
  validateProofArtifactLatency(proof, "proofArtifacts.latestProofsByApp[]");
}

function validateProofArtifactLatency(proofArtifacts, fieldPrefix = "proofArtifacts") {
  const hasLatency = proofArtifacts.latestProofLatencyHealth !== undefined
    || proofArtifacts.latestProofSlowestLatencyMeasurement !== undefined
    || proofArtifacts.latestProofSlowestLatencyMilliseconds !== undefined
    || proofArtifacts.latestProofLatencyBudgetMilliseconds !== undefined
    || proofArtifacts.latestProofStaleTimeoutMilliseconds !== undefined
    || proofArtifacts.latestProofLatencyRecommendedAction !== undefined;

  if (!hasLatency) {
    return;
  }

  requireString(proofArtifacts.latestProofLatencyHealth, `${fieldPrefix}.latestProofLatencyHealth`);
  if (!VALID_PROOF_LATENCY_HEALTH.has(proofArtifacts.latestProofLatencyHealth)) {
    throw new TypeError(`${fieldPrefix}.latestProofLatencyHealth must be healthy, delayed, or stale.`);
  }
  requireString(proofArtifacts.latestProofSlowestLatencyMeasurement, `${fieldPrefix}.latestProofSlowestLatencyMeasurement`);
  requireNonNegativeInteger(
    proofArtifacts.latestProofSlowestLatencyMilliseconds,
    `${fieldPrefix}.latestProofSlowestLatencyMilliseconds`
  );
  requireNonNegativeInteger(
    proofArtifacts.latestProofLatencyBudgetMilliseconds,
    `${fieldPrefix}.latestProofLatencyBudgetMilliseconds`
  );
  requireNonNegativeInteger(
    proofArtifacts.latestProofStaleTimeoutMilliseconds,
    `${fieldPrefix}.latestProofStaleTimeoutMilliseconds`
  );
  if (proofArtifacts.latestProofLatencyBudgetMilliseconds !== FRAME_LATENCY_BUDGET_MILLISECONDS) {
    throw new TypeError(`${fieldPrefix}.latestProofLatencyBudgetMilliseconds must match the app-screen latency budget.`);
  }
  if (proofArtifacts.latestProofStaleTimeoutMilliseconds !== FRAME_STALE_TIMEOUT_MILLISECONDS) {
    throw new TypeError(`${fieldPrefix}.latestProofStaleTimeoutMilliseconds must match the app-screen stale timeout.`);
  }

  const elapsed = proofArtifacts.latestProofSlowestLatencyMilliseconds;
  const expectedHealth = elapsed <= proofArtifacts.latestProofLatencyBudgetMilliseconds
    ? "healthy"
    : elapsed <= proofArtifacts.latestProofStaleTimeoutMilliseconds
      ? "delayed"
      : "stale";
  if (proofArtifacts.latestProofLatencyHealth !== expectedHealth) {
    throw new TypeError(`${fieldPrefix}.latestProofLatencyHealth must match the slowest proof latency.`);
  }

  const expectedAction = expectedHealth === "healthy"
    ? "none"
    : expectedHealth === "delayed"
      ? "measure-again"
      : "tune-frame-latency";
  requireString(proofArtifacts.latestProofLatencyRecommendedAction, `${fieldPrefix}.latestProofLatencyRecommendedAction`);
  if (proofArtifacts.latestProofLatencyRecommendedAction !== expectedAction) {
    throw new TypeError(`${fieldPrefix}.latestProofLatencyRecommendedAction must match the slowest proof latency.`);
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
  const requiresDisplayRecovery = report.localRuntime.recommendedAction === "recover-runtime-display"
    || report.localRuntime.recommendedRecoveryCommand !== undefined;
  const expectedSetupPassing = report.localRuntime.bootReady
    && report.localRuntime.windowsInstalled
    && !report.localRuntime.requiresGuestToolsMediaRebuild
    && !requiresDisplayRecovery;
  if (setupStep.isPassing !== expectedSetupPassing) {
    throw new TypeError("releaseGate windowsSetup must reflect local Windows setup readiness.");
  }
  if (requiresDisplayRecovery
    && setupStep.nextActionCommand !== report.localRuntime.recommendedRecoveryCommand
    && setupStep.nextActionCommand !== report.localRuntime.recommendedDisplayCommand) {
    throw new TypeError("releaseGate windowsSetup must expose display recovery before review readiness.");
  }
  if (setupStep.nextActionCommand !== report.localRuntime.recommendedInstallStatusCommand
    && setupStep.nextActionCommand !== report.localRuntime.recommendedPrepareCommand
    && setupStep.nextActionCommand !== report.localRuntime.recommendedMediaRebuildCommand
    && setupStep.nextActionCommand !== report.localRuntime.recommendedPowerDownCommand
    && setupStep.nextActionCommand !== report.localRuntime.recommendedRecoveryCommand
    && setupStep.nextActionCommand !== report.localRuntime.recommendedDisplayCommand) {
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
  const expectedLaunchPassing = (
    report.launchPlan.canLaunchSelectedAppNow
    && report.launchPlan.recommendedLaunchCommand !== undefined
  ) || report.macWindowIntegration.mirroredWindowCount > 0;
  if (launchStep.isPassing !== expectedLaunchPassing) {
    throw new TypeError("releaseGate openWindowsApp must reflect launch plan readiness.");
  }
  const expectedLaunchCommand = expectedOpenWindowsAppCommand(report.launchPlan);
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

function expectedOpenWindowsAppCommand(launchPlan) {
  if (launchPlan.canLaunchSelectedAppNow) {
    return launchPlan.recommendedLaunchCommand
      ?? launchPlan.recommendedStartCommand
      ?? launchPlan.recommendedRepairCommand
      ?? launchPlan.recommendedWaitCommand;
  }

  return launchPlan.recommendedStartCommand
    ?? launchPlan.recommendedRepairCommand
    ?? launchPlan.recommendedWaitCommand
    ?? launchPlan.recommendedLaunchCommand;
}

function validatePrimaryNextAction(primaryNextAction, report) {
  if (!primaryNextAction || typeof primaryNextAction !== "object" || Array.isArray(primaryNextAction)) {
    throw new TypeError("primaryNextAction must be an object.");
  }

  requireString(primaryNextAction.id, "primaryNextAction.id");
  requireString(primaryNextAction.title, "primaryNextAction.title");
  requireString(primaryNextAction.source, "primaryNextAction.source");
  requireBoolean(primaryNextAction.isAvailable, "primaryNextAction.isAvailable");
  requireBoolean(primaryNextAction.runsInApp, "primaryNextAction.runsInApp");
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
  if (primaryNextAction.runsInApp !== (expectedActionId !== undefined)) {
    throw new TypeError("primaryNextAction.runsInApp must reflect whether the next action is executable inside the app.");
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
      if (command.includes("--action stop-runtime")
        || command.includes("qemu-powerdown")) {
        return "runtime.stopWhenIdle";
      }
      if (command.includes("--action quiet-when-idle")) {
        return "runtime.quietWhenIdle";
      }
      if (command.includes("qemu-capture")
        || command.includes("qemu-display-smoke")
        || command.includes("--action recover-display")) {
        return "runtime.recoverDisplay";
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
      if (command.includes("--action repair-agent") || command.includes("qemu-install-agent")) {
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
    "runtime.prepareSparsePackage",
    "runtime.startWindowsForApp",
    "runtime.prepareWindows",
    "runtime.refreshStatus",
    "windowsApps.reconnectRestore",
    "windowsApps.restorePrevious",
    "windowsApps.closeAll",
    "windowsApps.restartFrameStream",
    "runtime.quietWhenIdle",
    "runtime.stopWhenIdle",
    "proof.recommended"
  ].includes(actionId);
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
  const restorableWindowCount = dockIntegration.restorableWindowCount ?? dockIntegration.restorableAppCount;
  requireNonNegativeInteger(restorableWindowCount, "dockIntegration.restorableWindowCount");
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
  if (restorableWindowCount < dockIntegration.restorableAppCount) {
    throw new TypeError("dockIntegration.restorableWindowCount must be at least restorableAppCount.");
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
    && restorableWindowCount === 0
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
    && restorableWindowCount > 0
  ) {
    requireString(dockIntegration.badgeLabel, "dockIntegration.badgeLabel");
    const expectedRestoreBadge = restorableWindowCount === 1 ? "R" : `R${restorableWindowCount}`;
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

  const expectedPrimaryActionId = expectedMenuBarPrimaryActionId(report);
  if (menuBarIntegration.primaryActionId !== expectedPrimaryActionId) {
    if (report.pendingLaunch.isQueued) {
      throw new TypeError("menuBarIntegration.primaryActionId must prioritize queued app launch recovery.");
    }
    throw new TypeError("menuBarIntegration.primaryActionId must prioritize Windows app and Daily Use recovery.");
  }

  if (menuBarIntegration.primaryActionId === "runtime.prepareSparsePackage"
    && menuBarIntegration.primaryActionTitle !== "Prepare Identity") {
    throw new TypeError("menuBarIntegration.primaryActionTitle must expose package identity preparation.");
  }

  if (menuBarIntegration.primaryActionId === "dailyUse.verifyIntegrations"
    && menuBarIntegration.primaryActionTitle !== "Verify Daily Use") {
    throw new TypeError("menuBarIntegration.primaryActionTitle must expose Daily Use verification.");
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

  if (report.dailyUseReadiness.recommendedAction === "prepare-sparse-package") {
    return "shippingbox";
  }

  if (report.dailyUseReadiness.recommendedAction === "verify-daily-use-integrations") {
    return "checkmark.seal";
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

function expectedMenuBarPrimaryActionId(report) {
  if (report.mirrorSessions.length > 0) {
    return "dock.bringWindowsAppsForward";
  }

  if (report.pendingLaunch.isQueued) {
    return expectedQueuedMenuBarPrimaryActionId(report);
  }

  if (report.dockIntegration.canRestorePreviousApps || report.dockIntegration.canReconnectPreviousApps) {
    return report.dockIntegration.canRestorePreviousApps
      ? "windowsApps.restorePrevious"
      : "windowsApps.reconnectRestore";
  }

  if (report.dailyUseReadiness.recommendedAction === "prepare-sparse-package"
    && report.dailyUseReadiness.recommendedCommand !== undefined) {
    return "runtime.prepareSparsePackage";
  }

  if (report.dailyUseReadiness.recommendedAction === "verify-daily-use-integrations"
    && report.dailyUseReadiness.recommendedCommand === "veil-vmctl app-runtime-action --json --action proof-recommended") {
    return "dailyUse.verifyIntegrations";
  }

  if (report.launchPlan.canRequestSelectedAppLaunch) {
    return "windowsApps.launchSelected";
  }

  if (!report.connection.hasLiveAgentConnection) {
    return "runtime.waitAgent";
  }

  return "dock.openMainWindow";
}

function expectedQueuedMenuBarPrimaryActionId(report) {
  if (report.localRuntime.recommendedPowerDownCommand !== undefined) {
    return "runtime.stopWhenIdle";
  }
  if (report.localRuntime.recommendedRecoveryCommand !== undefined) {
    return "runtime.recoverDisplay";
  }
  if (report.menuBarIntegration.canFulfillPendingLaunch) {
    return "runtime.fulfillPendingLaunch";
  }
  if (report.launchPlan.recommendedRepairCommand !== undefined) {
    return "runtime.repairGuestAgentForApp";
  }
  if (report.launchPlan.recommendedStartCommand !== undefined) {
    return "runtime.startWindowsForApp";
  }
  return "runtime.waitAgent";
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
  requireBoolean(oneScreenUX.returnsToLauncherWhenNoAppWindows, "oneScreenUX.returnsToLauncherWhenNoAppWindows");
  requireBoolean(oneScreenUX.keepsDisplayRecoveryManual, "oneScreenUX.keepsDisplayRecoveryManual");
  requireBoolean(oneScreenUX.heroRunsPrimaryAction, "oneScreenUX.heroRunsPrimaryAction");
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

  const expectedReturnsToLauncherWhenNoAppWindows = report.visibleSurfacePolicy.primarySurface === "windows-app-windows"
    || (report.visibleSurfacePolicy.primarySurface === "launcher"
      && report.visibleSurfacePolicy.expectedVisibleSurfaceCount === 1
      && report.launcherVisibility.shouldHideMainWindow === false);
  if (oneScreenUX.returnsToLauncherWhenNoAppWindows !== expectedReturnsToLauncherWhenNoAppWindows) {
    throw new TypeError("oneScreenUX.returnsToLauncherWhenNoAppWindows must match launcher fallback readiness.");
  }

  if (!oneScreenUX.returnsToLauncherWhenNoAppWindows) {
    throw new TypeError("oneScreenUX must return to the launcher when no Windows app windows are open.");
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

  const expectedHeroRunsPrimaryAction = report.primaryNextAction.runsInApp
    && installedRuntimeHeroSupports(report.primaryNextAction.actionId);
  if (oneScreenUX.heroRunsPrimaryAction !== expectedHeroRunsPrimaryAction) {
    throw new TypeError("oneScreenUX.heroRunsPrimaryAction must match whether the primary next action is supported by the app hero.");
  }

  if (expectedHeroRunsPrimaryAction && !oneScreenUX.heroRunsPrimaryAction) {
    throw new TypeError("oneScreenUX hero action must run every in-app primary next action.");
  }

  for (const disallowedTerm of ["Guest Agent", "HWND", "QEMU", "Proof"]) {
    if (oneScreenUX.reason.includes(disallowedTerm)) {
      throw new TypeError("oneScreenUX.reason must stay product-facing.");
    }
  }
}

function validateLaunchOnboarding(launchOnboarding, report) {
  if (!launchOnboarding || typeof launchOnboarding !== "object" || Array.isArray(launchOnboarding)) {
    throw new TypeError("launchOnboarding must be an object.");
  }

  requireBoolean(launchOnboarding.isEnabled, "launchOnboarding.isEnabled");
  requireString(launchOnboarding.state, "launchOnboarding.state");
  requireString(launchOnboarding.currentStepId, "launchOnboarding.currentStepId");
  requireString(launchOnboarding.currentStepTitle, "launchOnboarding.currentStepTitle");
  requireString(launchOnboarding.currentStepDetail, "launchOnboarding.currentStepDetail");
  requireBoolean(launchOnboarding.usesSinglePrimarySurface, "launchOnboarding.usesSinglePrimarySurface");
  requireNonNegativeInteger(launchOnboarding.expectedVisibleSurfaceCount, "launchOnboarding.expectedVisibleSurfaceCount");
  requireBoolean(launchOnboarding.canContinueInApp, "launchOnboarding.canContinueInApp");
  requireBoolean(launchOnboarding.heroRunsPrimaryAction, "launchOnboarding.heroRunsPrimaryAction");
  requireBoolean(launchOnboarding.keepsRecoveryInMenuOrDock, "launchOnboarding.keepsRecoveryInMenuOrDock");
  requireBoolean(launchOnboarding.keepsVMDisplayManual, "launchOnboarding.keepsVMDisplayManual");
  requireBoolean(launchOnboarding.pendingLiveProof, "launchOnboarding.pendingLiveProof");
  requireNonNegativeInteger(launchOnboarding.completedStepCount, "launchOnboarding.completedStepCount");
  requireNonNegativeInteger(launchOnboarding.totalStepCount, "launchOnboarding.totalStepCount");
  requireNonNegativeInteger(launchOnboarding.currentStepNumber, "launchOnboarding.currentStepNumber");
  requireString(launchOnboarding.progressLabel, "launchOnboarding.progressLabel");
  requireString(launchOnboarding.reason, "launchOnboarding.reason");

  if (launchOnboarding.primaryActionId !== undefined) {
    requireString(launchOnboarding.primaryActionId, "launchOnboarding.primaryActionId");
  }
  if (launchOnboarding.primaryCommand !== undefined) {
    requireString(launchOnboarding.primaryCommand, "launchOnboarding.primaryCommand");
  }

  if (!["blocked", "continue-in-app", "external-check", "ready-for-review"].includes(launchOnboarding.state)) {
    throw new TypeError("launchOnboarding.state must identify a known onboarding state.");
  }
  if (!launchOnboarding.isEnabled) {
    throw new TypeError("launchOnboarding must stay enabled for one-shot launch acceptance.");
  }
  if (launchOnboarding.currentStepId !== report.primaryNextAction.id) {
    throw new TypeError("launchOnboarding.currentStepId must match primaryNextAction.id.");
  }
  if (launchOnboarding.currentStepTitle !== report.primaryNextAction.title) {
    throw new TypeError("launchOnboarding.currentStepTitle must match primaryNextAction.title.");
  }
  const expectedCurrentStepDetail = currentStepDetail(report);
  if (launchOnboarding.currentStepDetail !== expectedCurrentStepDetail) {
    throw new TypeError("launchOnboarding.currentStepDetail must describe the current product step.");
  }
  if (launchOnboarding.usesSinglePrimarySurface !== report.oneScreenUX.usesSinglePrimarySurfaceFamily) {
    throw new TypeError("launchOnboarding.usesSinglePrimarySurface must match oneScreenUX.");
  }
  if (launchOnboarding.expectedVisibleSurfaceCount !== report.oneScreenUX.expectedVisibleSurfaceCount) {
    throw new TypeError("launchOnboarding.expectedVisibleSurfaceCount must match oneScreenUX.");
  }
  if (launchOnboarding.heroRunsPrimaryAction !== report.oneScreenUX.heroRunsPrimaryAction) {
    throw new TypeError("launchOnboarding.heroRunsPrimaryAction must match oneScreenUX.");
  }
  if (launchOnboarding.keepsRecoveryInMenuOrDock !== report.oneScreenUX.canRecoverFromMenuOrDock) {
    throw new TypeError("launchOnboarding.keepsRecoveryInMenuOrDock must match oneScreenUX.");
  }
  if (launchOnboarding.keepsVMDisplayManual !== report.oneScreenUX.keepsDisplayRecoveryManual) {
    throw new TypeError("launchOnboarding.keepsVMDisplayManual must match oneScreenUX.");
  }
  if (launchOnboarding.primaryActionId !== report.primaryNextAction.actionId) {
    throw new TypeError("launchOnboarding.primaryActionId must match primaryNextAction.actionId.");
  }
  if (launchOnboarding.primaryCommand !== report.primaryNextAction.command) {
    throw new TypeError("launchOnboarding.primaryCommand must match primaryNextAction.command.");
  }
  if (launchOnboarding.pendingLiveProof !== !report.releaseGate.isPassing) {
    throw new TypeError("launchOnboarding.pendingLiveProof must match releaseGate progress.");
  }
  if (launchOnboarding.completedStepCount !== report.releaseGate.passingStepCount) {
    throw new TypeError("launchOnboarding.completedStepCount must match releaseGate.passingStepCount.");
  }
  if (launchOnboarding.totalStepCount !== report.releaseGate.requiredStepCount) {
    throw new TypeError("launchOnboarding.totalStepCount must match releaseGate.requiredStepCount.");
  }
  const requiredSteps = report.releaseGate.steps.filter((step) => step.isRequired);
  const recommendedStepIndex = requiredSteps.findIndex((step) => step.id === report.releaseGate.recommendedAction);
  const expectedCurrentStepNumber = report.releaseGate.isPassing
    ? report.releaseGate.requiredStepCount
    : (recommendedStepIndex >= 0
      ? recommendedStepIndex + 1
      : Math.min(report.releaseGate.passingStepCount + 1, report.releaseGate.requiredStepCount));
  if (launchOnboarding.currentStepNumber !== expectedCurrentStepNumber) {
    throw new TypeError("launchOnboarding.currentStepNumber must match releaseGate.recommendedAction.");
  }
  const expectedProgressLabel = `Step ${expectedCurrentStepNumber} of ${report.releaseGate.requiredStepCount}`;
  if (launchOnboarding.progressLabel !== expectedProgressLabel) {
    throw new TypeError("launchOnboarding.progressLabel must summarize the current releaseGate step.");
  }

  const expectedCanContinueInApp = report.primaryNextAction.runsInApp
    && report.primaryNextAction.isAvailable
    && report.oneScreenUX.heroRunsPrimaryAction;
  if (launchOnboarding.canContinueInApp !== expectedCanContinueInApp) {
    throw new TypeError("launchOnboarding.canContinueInApp must match the executable one-screen action.");
  }

  const expectedState = report.releaseGate.isPassing
    ? "ready-for-review"
    : (expectedCanContinueInApp
      ? "continue-in-app"
      : (report.primaryNextAction.isAvailable ? "external-check" : "blocked"));
  if (launchOnboarding.state !== expectedState) {
    throw new TypeError("launchOnboarding.state must match release and primary action readiness.");
  }

  for (const disallowedTerm of ["Guest Agent", "HWND", "QEMU", "Proof"]) {
    if (launchOnboarding.currentStepTitle.includes(disallowedTerm)
      || launchOnboarding.currentStepDetail.includes(disallowedTerm)
      || launchOnboarding.reason.includes(disallowedTerm)) {
      throw new TypeError("launchOnboarding copy must stay product-facing.");
    }
  }
}

function currentStepDetail(report) {
  if (report.releaseGate.isPassing) {
    return "Review and share the current app-flow evidence.";
  }

  switch (report.primaryNextAction.id) {
    case "windowsSetup":
      switch (report.primaryNextAction.actionId) {
        case "runtime.recoverDisplay":
          return "Refresh the Windows display before continuing the app flow.";
        case "runtime.stopWhenIdle":
        case "runtime.quietWhenIdle":
          return "Quiet Windows, update setup media, then continue the app flow.";
        case "runtime.prepareWindows":
          return "Finish Windows setup before opening apps.";
        default:
          return "Check Windows setup, then continue the app flow.";
      }
    case "oneScreenPath":
      return "Keep Veil as the only launcher until the app window opens.";
    case "openWindowsApp":
      switch (report.primaryNextAction.actionId) {
        case "runtime.repairGuestAgentForApp": {
          const appName = report.primaryNextAction.title.startsWith("Continue ")
            ? report.primaryNextAction.title.slice("Continue ".length)
            : "the selected app";
          return `Reconnect the app connection, then open ${appName} automatically.`;
        }
        case "runtime.startWindowsForApp":
          return "Start Windows, then open the selected app automatically.";
        case "runtime.fulfillPendingLaunch":
          return "Open the queued app as a macOS window.";
        case "runtime.waitAgent":
          return "Wait for the app connection, then continue automatically.";
        case "windowsApps.launchSelected":
          return "Open the selected Windows app as a macOS window.";
        default:
          return "Continue the selected Windows app from Veil.";
      }
    case "appCheckEvidence":
      return "Run Check App and save current app evidence.";
    case "closeOrRestore":
      return "Restore, bring forward, or close Windows app windows from Veil.";
    default:
      return "Continue the next app-flow step.";
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
    "windowsApps.restartFrameStream",
    "windowsApps.maintainFrameStreams",
    "windowsApps.reopenWindow",
    "windowsApps.recoverWindowCapture",
    "macWindows.autoOpen",
    "windowsApps.launchSelected",
    "runtime.prepareWindows",
    "runtime.refreshStatus",
    "runtime.startWindowsForApp",
    "runtime.repairGuestAgentForApp",
    "runtime.prepareSparsePackage",
    "dailyUse.verifyIntegrations",
    "dailyUse.verifyWindowCapture",
    "dailyUse.requestNotificationConsent",
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

  const restartFrameStreamAction = actions.find((action) => action.id === "windowsApps.restartFrameStream");
  const canRestartFrameStream = report.macWindowIntegration.staleFrameWindowCount > 0;
  if (restartFrameStreamAction.isAvailable !== canRestartFrameStream) {
    throw new TypeError("windowsApps.restartFrameStream availability must match stale frame streams.");
  }

  const maintainFrameStreamsAction = actions.find((action) => action.id === "windowsApps.maintainFrameStreams");
  if (maintainFrameStreamsAction.isAvailable !== canRestartFrameStream) {
    throw new TypeError("windowsApps.maintainFrameStreams availability must match stale frame streams.");
  }

  const recoverWindowCaptureAction = actions.find((action) => action.id === "windowsApps.recoverWindowCapture");
  const canRecoverWindowCapture = report.mirrorSessions.some((session) => session.frameStreamRecoveryEscalated);
  if (recoverWindowCaptureAction.isAvailable !== canRecoverWindowCapture) {
    throw new TypeError("windowsApps.recoverWindowCapture availability must match escalated frame streams.");
  }

  const reopenWindowAction = actions.find((action) => action.id === "windowsApps.reopenWindow");
  const canReopenWindow = report.mirrorSessions.some((session) => session.frameStreamReopenEscalated);
  if (reopenWindowAction.isAvailable !== canReopenWindow) {
    throw new TypeError("windowsApps.reopenWindow availability must match reopen-escalated frame streams.");
  }

  const repairAction = actions.find((action) => action.id === "runtime.repairGuestAgentForApp");
  if (repairAction.isAvailable !== (report.launchPlan.recommendedRepairCommand !== undefined)) {
    throw new TypeError("runtime.repairGuestAgentForApp availability must match launchPlan.recommendedRepairCommand.");
  }

  const prepareSparsePackageAction = actions.find((action) => action.id === "runtime.prepareSparsePackage");
  const canPrepareSparsePackage = report.dailyUseReadiness.recommendedAction === "prepare-sparse-package"
    && report.dailyUseReadiness.recommendedCommand !== undefined;
  if (prepareSparsePackageAction.isAvailable !== canPrepareSparsePackage) {
    throw new TypeError("runtime.prepareSparsePackage availability must match dailyUseReadiness package identity action.");
  }

  const verifyDailyUseAction = actions.find((action) => action.id === "dailyUse.verifyIntegrations");
  const canVerifyDailyUse = report.dailyUseReadiness.recommendedAction === "verify-daily-use-integrations"
    && report.dailyUseReadiness.recommendedCommand === "veil-vmctl app-runtime-action --json --action proof-recommended";
  if (verifyDailyUseAction.isAvailable !== canVerifyDailyUse) {
    throw new TypeError("dailyUse.verifyIntegrations availability must match Daily Use verification readiness.");
  }

  const verifyWindowCaptureAction = actions.find((action) => action.id === "dailyUse.verifyWindowCapture");
  const canVerifyWindowCapture = report.dailyUseReadiness.borderlessCaptureRecommendedAction === "verify-window-capture"
    && report.dailyUseReadiness.recommendedCommand === "veil-vmctl app-runtime-status --json";
  if (verifyWindowCaptureAction.isAvailable !== canVerifyWindowCapture) {
    throw new TypeError("dailyUse.verifyWindowCapture availability must match Daily Use window capture gate.");
  }

  const notificationConsentAction = actions.find((action) => action.id === "dailyUse.requestNotificationConsent");
  if (notificationConsentAction.isAvailable) {
    throw new TypeError("dailyUse.requestNotificationConsent must stay unavailable until notification consent automation exists.");
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
  if (stopWhenIdleAction.isAvailable !== (
    report.quietRuntime.canQuietRuntime || report.localRuntime.recommendedPowerDownCommand !== undefined
  )) {
    throw new TypeError("runtime.stopWhenIdle availability must match quietRuntime.canQuietRuntime or localRuntime.recommendedPowerDownCommand.");
  }

  const launchSelectedAction = actions.find((action) => action.id === "windowsApps.launchSelected");
  if (launchSelectedAction.isAvailable !== report.launchPlan.canRequestSelectedAppLaunch) {
    throw new TypeError("windowsApps.launchSelected availability must match launchPlan.canRequestSelectedAppLaunch.");
  }

  const menuPrimaryAction = actions.find((action) => action.id === report.menuBarIntegration.primaryActionId);
  if (menuPrimaryAction === undefined) {
    throw new TypeError("menuBarIntegration.primaryActionId must reference a supported action.");
  }
  if (menuPrimaryAction.isAvailable !== report.menuBarIntegration.primaryActionAvailable) {
    throw new TypeError("menuBarIntegration.primaryActionAvailable must match the referenced action.");
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
