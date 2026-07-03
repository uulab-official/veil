import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_STATUSES = new Set(["proved", "unavailable"]);

export function validateMVPProof(report, options = {}) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("MVP proof report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "windowsMVPProof") {
    throw new TypeError(`Unsupported MVP proof kind: ${report.kind}`);
  }
  requireString(report.endpoint, "endpoint");
  if (!report.endpoint.startsWith("ws://")) {
    throw new TypeError("endpoint must be a WebSocket URL.");
  }
  requireString(report.appId, "appId");
  requireString(report.status, "status");
  if (!VALID_STATUSES.has(report.status)) {
    throw new TypeError(`Unsupported MVP proof status: ${report.status}`);
  }
  if (options.requireProved === true && report.status !== "proved") {
    throw new TypeError("MVP release proof requires status=proved.");
  }
  requireString(report.provedAt, "provedAt");
  if (Number.isNaN(Date.parse(report.provedAt))) {
    throw new TypeError("provedAt must be an ISO date.");
  }

  validateWait(report.wait, report.status);
  validateSavedProofPath(report.savedProofPath);
  validateNextActions(report.nextActions);

  if (report.status === "proved") {
    validateCoherence(report.coherence, report.appId);
    if (!report.nextActions.some((action) => action.includes("MVP proof artifact"))) {
      throw new TypeError("proved MVP reports must mention the MVP proof artifact next action.");
    }
  } else {
    if (report.coherence !== undefined) {
      throw new TypeError("unavailable MVP reports must not include coherence proof evidence.");
    }
    if (!report.nextActions.some((action) => action.includes("Install Veil Agent.cmd"))) {
      throw new TypeError("unavailable MVP reports must include guest agent install recovery guidance.");
    }
  }

  return report;
}

function validateWait(wait, status) {
  if (!wait || typeof wait !== "object" || Array.isArray(wait)) {
    throw new TypeError("wait must be an object.");
  }
  requireString(wait.kind, "wait.kind");
  if (wait.kind !== "guestAgentWait") {
    throw new TypeError("wait.kind must be guestAgentWait.");
  }
  requireString(wait.status, "wait.status");
  if (status === "proved" && wait.status !== "connected") {
    throw new TypeError("proved MVP reports must include connected guest wait evidence.");
  }
  if (status === "unavailable" && wait.status !== "unavailable") {
    throw new TypeError("unavailable MVP reports must include unavailable guest wait evidence.");
  }
  requireInteger(wait.attempts, "wait.attempts");
  requireInteger(wait.waitedSeconds, "wait.waitedSeconds");
  validateNextActions(wait.nextActions);
}

function validateCoherence(coherence, appId) {
  if (!coherence || typeof coherence !== "object" || Array.isArray(coherence)) {
    throw new TypeError("proved MVP reports must include coherence proof evidence.");
  }
  requireString(coherence.kind, "coherence.kind");
  if (coherence.kind !== "windowsAppCoherenceProof") {
    throw new TypeError("coherence.kind must be windowsAppCoherenceProof.");
  }
  if (coherence.appId !== appId) {
    throw new TypeError("coherence.appId must match report appId.");
  }
  validateLaunch(coherence.launch);
  validateWindow(coherence.window, appId, coherence.launch.processId);
  validateFrame(coherence.initialFrame, coherence.window.windowId, "coherence.initialFrame");
  validateFrame(coherence.postInputFrame, coherence.window.windowId, "coherence.postInputFrame");
  if (coherence.postInputFrame.sequence <= coherence.initialFrame.sequence) {
    throw new TypeError("coherence.postInputFrame.sequence must be greater than initialFrame.sequence.");
  }
  validateInput(coherence.input);
}

function validateLaunch(launch) {
  if (!launch || typeof launch !== "object" || Array.isArray(launch)) {
    throw new TypeError("coherence.launch must be an object.");
  }
  requireString(launch.type, "coherence.launch.type");
  if (launch.type !== "app.launch.response") {
    throw new TypeError("coherence.launch.type must be app.launch.response.");
  }
  requireBoolean(launch.accepted, "coherence.launch.accepted");
  requireInteger(launch.processId, "coherence.launch.processId");
}

function validateWindow(window, appId, processId) {
  if (!window || typeof window !== "object" || Array.isArray(window)) {
    throw new TypeError("coherence.window must be an object.");
  }
  requireString(window.type, "coherence.window.type");
  if (window.type !== "window.created") {
    throw new TypeError("coherence.window.type must be window.created.");
  }
  requireString(window.windowId, "coherence.window.windowId");
  if (!/^hwnd:[0-9A-Fa-f]+$/.test(window.windowId)) {
    throw new TypeError("coherence.window.windowId must be an hwnd id.");
  }
  if (window.appId !== appId) {
    throw new TypeError("coherence.window.appId must match report appId.");
  }
  if (window.processId !== processId) {
    throw new TypeError("coherence.window.processId must match launch.processId.");
  }
}

function validateFrame(frame, windowId, fieldName) {
  if (!frame || typeof frame !== "object" || Array.isArray(frame)) {
    throw new TypeError(`${fieldName} must be an object.`);
  }
  requireString(frame.windowId, `${fieldName}.windowId`);
  if (frame.windowId !== windowId) {
    throw new TypeError(`${fieldName}.windowId must match coherence.window.windowId.`);
  }
  requireString(frame.frameId, `${fieldName}.frameId`);
  requireInteger(frame.sequence, `${fieldName}.sequence`);
  requireString(frame.format, `${fieldName}.format`);
  if (frame.format !== "png") {
    throw new TypeError(`${fieldName}.format must be png.`);
  }
  requireInteger(frame.encodedByteCount, `${fieldName}.encodedByteCount`);
  if (frame.encodedByteCount <= 0) {
    throw new TypeError(`${fieldName}.encodedByteCount must be positive.`);
  }
}

function validateInput(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new TypeError("coherence.input must be an object.");
  }
  if (!Array.isArray(input.mouseEventsPosted) || input.mouseEventsPosted[0] !== "leftDown" || input.mouseEventsPosted[1] !== "leftUp") {
    throw new TypeError("coherence.input.mouseEventsPosted must start with leftDown and leftUp.");
  }
  if (!Array.isArray(input.keyEventsPosted) || input.keyEventsPosted.length === 0) {
    throw new TypeError("coherence.input.keyEventsPosted must be non-empty.");
  }
  requireInteger(input.typedTextCharacterCount, "coherence.input.typedTextCharacterCount");
  requireString(input.clipboardOrigin, "coherence.input.clipboardOrigin");
  if (input.clipboardOrigin !== "host") {
    throw new TypeError("coherence.input.clipboardOrigin must be host.");
  }
  requireInteger(input.clipboardSequence, "coherence.input.clipboardSequence");
  requireInteger(input.clipboardTextByteCount, "coherence.input.clipboardTextByteCount");
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
    throw new TypeError(`MVP proof field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`MVP proof field '${fieldName}' must be boolean.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`MVP proof field '${fieldName}' must be an integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected MVP proof JSON on stdin.");
  }

  validateMVPProof(JSON.parse(input), {
    requireProved: process.argv.includes("--require-proved")
  });
  process.stdout.write("mvp proof valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
