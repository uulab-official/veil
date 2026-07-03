import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export function validateAppWindowProof(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("App window proof report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "windowsAppWindowProof") {
    throw new TypeError(`Unsupported app window proof kind: ${report.kind}`);
  }
  requireString(report.endpoint, "endpoint");
  if (!report.endpoint.startsWith("ws://")) {
    throw new TypeError("endpoint must be a WebSocket URL.");
  }
  requireString(report.appId, "appId");
  requireString(report.provedAt, "provedAt");
  if (Number.isNaN(Date.parse(report.provedAt))) {
    throw new TypeError("provedAt must be an ISO date.");
  }

  validateLaunch(report.launch);
  validateWindow(report.window, report.appId, report.launch.processId);
  validateFrame(report.frame, report.window.windowId);
  validateSavedProofPath(report.savedProofPath);
  validateNextActions(report.nextActions);

  if (!report.nextActions.some((action) => action.includes("app-runtime-status"))) {
    throw new TypeError("app window proof reports must include app-runtime-status next action.");
  }

  return report;
}

function validateSavedProofPath(savedProofPath) {
  if (savedProofPath === undefined || savedProofPath === null) {
    return;
  }

  requireString(savedProofPath, "savedProofPath");
  if (!savedProofPath.endsWith(".json")) {
    throw new TypeError("savedProofPath must point to a JSON proof artifact.");
  }
}

function validateLaunch(launch) {
  if (!launch || typeof launch !== "object" || Array.isArray(launch)) {
    throw new TypeError("launch must be an object.");
  }
  requireString(launch.type, "launch.type");
  if (launch.type !== "app.launch.response") {
    throw new TypeError("launch.type must be app.launch.response.");
  }
  requireBoolean(launch.accepted, "launch.accepted");
  if (launch.accepted !== true) {
    throw new TypeError("launch.accepted must be true.");
  }
  requireInteger(launch.processId, "launch.processId");
}

function validateWindow(window, appId, processId) {
  if (!window || typeof window !== "object" || Array.isArray(window)) {
    throw new TypeError("window must be an object.");
  }
  requireString(window.type, "window.type");
  if (window.type !== "window.created") {
    throw new TypeError("window.type must be window.created.");
  }
  requireString(window.windowId, "window.windowId");
  if (!/^hwnd:[0-9A-Fa-f]+$/.test(window.windowId)) {
    throw new TypeError("window.windowId must be an hwnd id.");
  }
  requireString(window.appId, "window.appId");
  if (window.appId !== appId) {
    throw new TypeError("window.appId must match report appId.");
  }
  requireInteger(window.processId, "window.processId");
  if (window.processId !== processId) {
    throw new TypeError("window.processId must match launch.processId.");
  }
  requireString(window.title, "window.title");
  requireBoolean(window.focused, "window.focused");
}

function validateFrame(frame, windowId) {
  if (!frame || typeof frame !== "object" || Array.isArray(frame)) {
    throw new TypeError("frame must be an object.");
  }
  requireString(frame.windowId, "frame.windowId");
  if (frame.windowId !== windowId) {
    throw new TypeError("frame.windowId must match window.windowId.");
  }
  requireString(frame.frameId, "frame.frameId");
  requireInteger(frame.sequence, "frame.sequence");
  requireString(frame.format, "frame.format");
  if (frame.format !== "png") {
    throw new TypeError("frame.format must be png.");
  }
  requireInteger(frame.width, "frame.width");
  requireInteger(frame.height, "frame.height");
  requireNumber(frame.scale, "frame.scale");
  requireInteger(frame.encodedByteCount, "frame.encodedByteCount");
  if (frame.width <= 0 || frame.height <= 0 || frame.encodedByteCount <= 0) {
    throw new TypeError("frame dimensions and encodedByteCount must be positive.");
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
    throw new TypeError(`App window proof field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`App window proof field '${fieldName}' must be boolean.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`App window proof field '${fieldName}' must be an integer.`);
  }
}

function requireNumber(value, fieldName) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    throw new TypeError(`App window proof field '${fieldName}' must be a number.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected app window proof JSON on stdin.");
  }

  validateAppWindowProof(JSON.parse(input));
  process.stdout.write("app window proof valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
