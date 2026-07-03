import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { validateAppRuntimeStatus } from "../../app-runtime-status/src/validate-app-runtime-status.mjs";

const VALID_ACTIONS = new Set(["launch", "focus", "close", "restore"]);
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
    case "restore":
      validateRestoreAction(report);
      break;
  }

  validateStringArray(report.nextActions, "nextActions");
  return report;
}

function validateLaunchAction(report) {
  if (!report.accepted) {
    return;
  }

  requireString(report.appId, "appId");
  requireString(report.windowId, "windowId");
  validateLaunchResponse(report.launch);
  validateWindow(report.window);
  if (report.window.windowId !== report.windowId) {
    throw new TypeError("launch window must match report.windowId.");
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

function validateRestoreAction(report) {
  for (const window of report.restoredWindows) {
    validateWindow(window);
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
