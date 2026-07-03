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
  validateActions(report.actions);

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

function validateActions(actions) {
  if (!Array.isArray(actions)) {
    throw new TypeError("actions must be an array.");
  }

  const actionIds = new Set(actions.map((action) => action?.id));
  for (const requiredAction of ["windowsApps.restorePrevious", "windowsApps.closeAll", "clipboard.setText"]) {
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
