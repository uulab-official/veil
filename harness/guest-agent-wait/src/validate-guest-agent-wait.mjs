import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_STATUSES = new Set(["connected", "unavailable"]);

export function validateGuestAgentWait(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("Guest agent wait report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "guestAgentWait") {
    throw new TypeError(`Unsupported guest agent wait kind: ${report.kind}`);
  }

  requireString(report.endpoint, "endpoint");
  if (!report.endpoint.startsWith("ws://")) {
    throw new TypeError("endpoint must be a WebSocket URL.");
  }
  requireString(report.status, "status");
  if (!VALID_STATUSES.has(report.status)) {
    throw new TypeError(`Unsupported guest agent wait status: ${report.status}`);
  }
  requireInteger(report.waitedSeconds, "waitedSeconds");
  requireInteger(report.attempts, "attempts");
  if (report.waitedSeconds < 0) {
    throw new TypeError("waitedSeconds must be zero or positive.");
  }
  if (report.attempts < 1) {
    throw new TypeError("attempts must be positive.");
  }

  validateDiagnostic(report.diagnostic, report.status);
  validateNextActions(report.nextActions);

  if (report.status === "connected") {
    requireString(report.connectedAt, "connectedAt");
    if (Number.isNaN(Date.parse(report.connectedAt))) {
      throw new TypeError("connectedAt must be an ISO date.");
    }
    if (!report.nextActions.some((action) => action.includes("app-runtime-status"))) {
      throw new TypeError("connected guest agent reports must include app-runtime-status next action.");
    }
    if (!report.nextActions.some((action) => action.includes("app-window-proof"))) {
      throw new TypeError("connected guest agent reports must include app-window-proof next action.");
    }
  }

  if (report.status === "unavailable") {
    if (report.connectedAt !== undefined) {
      throw new TypeError("unavailable guest agent reports must not include connectedAt.");
    }
    if (!report.nextActions.some((action) => action.includes("Install Veil Agent.cmd"))) {
      throw new TypeError("unavailable guest agent reports must include Install Veil Agent.cmd recovery guidance.");
    }
  }

  return report;
}

function validateDiagnostic(diagnostic, expectedStatus) {
  if (!diagnostic || typeof diagnostic !== "object" || Array.isArray(diagnostic)) {
    throw new TypeError("diagnostic must be an object.");
  }

  requireString(diagnostic.status, "diagnostic.status");
  if (diagnostic.status !== expectedStatus) {
    throw new TypeError("diagnostic.status must match report status.");
  }
  requireString(diagnostic.endpoint, "diagnostic.endpoint");
  if (diagnostic.hostForwardProbe !== undefined) {
    validateHostForwardProbe(diagnostic.hostForwardProbe);
  }
  validateNextActions(diagnostic.nextActions);

  if (expectedStatus === "connected") {
    validateHealth(diagnostic.health);
  } else {
    requireString(diagnostic.errorMessage, "diagnostic.errorMessage");
  }
}

function validateHealth(health) {
  if (!health || typeof health !== "object" || Array.isArray(health)) {
    throw new TypeError("diagnostic.health must be an object for connected reports.");
  }

  requireString(health.type, "diagnostic.health.type");
  if (health.type !== "agent.health.response") {
    throw new TypeError("diagnostic.health.type must be agent.health.response.");
  }
  requireString(health.agentVersion, "diagnostic.health.agentVersion");
  requireString(health.os, "diagnostic.health.os");
  if (!health.capabilities || typeof health.capabilities !== "object" || Array.isArray(health.capabilities)) {
    throw new TypeError("diagnostic.health.capabilities must be an object.");
  }
  for (const field of ["appList", "appLaunch", "windowTracking", "windowCapture", "input", "clipboardText"]) {
    requireBoolean(health.capabilities[field], `diagnostic.health.capabilities.${field}`);
  }
}

function validateHostForwardProbe(probe) {
  if (!probe || typeof probe !== "object" || Array.isArray(probe)) {
    throw new TypeError("diagnostic.hostForwardProbe must be an object.");
  }

  requireString(probe.endpoint, "diagnostic.hostForwardProbe.endpoint");
  requireString(probe.status, "diagnostic.hostForwardProbe.status");
  if (!["tcpOpen", "tcpUnavailable", "unsupportedEndpoint"].includes(probe.status)) {
    throw new TypeError("diagnostic.hostForwardProbe.status is unsupported.");
  }
  requireString(probe.detail, "diagnostic.hostForwardProbe.detail");
  if (probe.host !== undefined) {
    requireString(probe.host, "diagnostic.hostForwardProbe.host");
  }
  if (probe.port !== undefined) {
    requireInteger(probe.port, "diagnostic.hostForwardProbe.port");
  }
}

function validateNextActions(actions) {
  if (!Array.isArray(actions) || actions.length === 0) {
    throw new TypeError("nextActions must be a non-empty array.");
  }

  for (const action of actions) {
    requireString(action, "nextActions[]");
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Guest agent wait field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`Guest agent wait field '${fieldName}' must be boolean.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`Guest agent wait field '${fieldName}' must be an integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected guest agent wait JSON on stdin.");
  }

  validateGuestAgentWait(JSON.parse(input));
  process.stdout.write("guest agent wait valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
