import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export function validateCoherenceProof(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("Coherence proof report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "windowsAppCoherenceProof") {
    throw new TypeError(`Unsupported coherence proof kind: ${report.kind}`);
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
  validateFrame(report.initialFrame, report.window.windowId, "initialFrame");
  validateFrame(report.postInputFrame, report.window.windowId, "postInputFrame");
  if (report.postInputFrame.sequence <= report.initialFrame.sequence) {
    throw new TypeError("postInputFrame.sequence must be greater than initialFrame.sequence.");
  }
  validateInput(report.input);
  validateSavedProofPath(report.savedProofPath);
  validateNextActions(report.nextActions);

  return report;
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

function validateFrame(frame, windowId, fieldName) {
  if (!frame || typeof frame !== "object" || Array.isArray(frame)) {
    throw new TypeError(`${fieldName} must be an object.`);
  }
  requireString(frame.windowId, `${fieldName}.windowId`);
  if (frame.windowId !== windowId) {
    throw new TypeError(`${fieldName}.windowId must match window.windowId.`);
  }
  requireString(frame.frameId, `${fieldName}.frameId`);
  requireInteger(frame.sequence, `${fieldName}.sequence`);
  requireString(frame.format, `${fieldName}.format`);
  if (frame.format !== "png") {
    throw new TypeError(`${fieldName}.format must be png.`);
  }
  requireInteger(frame.width, `${fieldName}.width`);
  requireInteger(frame.height, `${fieldName}.height`);
  requireNumber(frame.scale, `${fieldName}.scale`);
  requireInteger(frame.encodedByteCount, `${fieldName}.encodedByteCount`);
  if (frame.width <= 0 || frame.height <= 0 || frame.encodedByteCount <= 0) {
    throw new TypeError(`${fieldName} dimensions and encodedByteCount must be positive.`);
  }
}

function validateInput(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new TypeError("input must be an object.");
  }
  if (!Array.isArray(input.mouseEventsPosted) || input.mouseEventsPosted.length < 2) {
    throw new TypeError("input.mouseEventsPosted must include a click down/up pair.");
  }
  if (input.mouseEventsPosted[0] !== "leftDown" || input.mouseEventsPosted[1] !== "leftUp") {
    throw new TypeError("input.mouseEventsPosted must start with leftDown and leftUp.");
  }
  if (!Array.isArray(input.keyEventsPosted) || input.keyEventsPosted.length === 0) {
    throw new TypeError("input.keyEventsPosted must be a non-empty array.");
  }
  for (const event of input.keyEventsPosted) {
    requireString(event, "input.keyEventsPosted[]");
  }
  requireInteger(input.typedTextCharacterCount, "input.typedTextCharacterCount");
  if (input.typedTextCharacterCount <= 0) {
    throw new TypeError("input.typedTextCharacterCount must be positive.");
  }
  requireString(input.clipboardOrigin, "input.clipboardOrigin");
  if (input.clipboardOrigin !== "host") {
    throw new TypeError("input.clipboardOrigin must be host.");
  }
  requireInteger(input.clipboardSequence, "input.clipboardSequence");
  requireInteger(input.clipboardTextByteCount, "input.clipboardTextByteCount");
  if (input.clipboardSequence <= 0 || input.clipboardTextByteCount <= 0) {
    throw new TypeError("input clipboard sequence and byte count must be positive.");
  }
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
    throw new TypeError(`Coherence proof field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`Coherence proof field '${fieldName}' must be boolean.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`Coherence proof field '${fieldName}' must be an integer.`);
  }
}

function requireNumber(value, fieldName) {
  if (typeof value !== "number" || Number.isNaN(value)) {
    throw new TypeError(`Coherence proof field '${fieldName}' must be a number.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected coherence proof JSON on stdin.");
  }

  validateCoherenceProof(JSON.parse(input));
  process.stdout.write("coherence proof valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
