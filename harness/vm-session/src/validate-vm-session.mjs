import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_ACTIONS = new Set(["suspend", "resume", "status"]);
const VALID_STATUSES = new Set(["suspended", "resumed", "running", "stopped", "unavailable", "failed"]);
const VALID_VM_STATES = new Set([
  "unsupported",
  "notConfigured",
  "stopped",
  "starting",
  "running",
  "suspended",
  "failed"
]);
const MEMORY_STATE_FILE_MODE = "memoryStateFile";
const UNSUPPORTED_MODE = "unsupported";
const VALID_PERSISTENCE_MODES = new Set([MEMORY_STATE_FILE_MODE, UNSUPPORTED_MODE]);

/// Suspend must persist guest memory outside the diagnostics tree. A diagnostics bundle is
/// metadata-only by contract, and a memory-state file is guest RAM.
const DIAGNOSTICS_PATH_MARKER = "/Diagnostics/";

export function validateVMSession(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("VM session report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "vmSessionAction") {
    throw new TypeError(`Unsupported VM session kind: ${report.kind}`);
  }

  requireString(report.action, "action");
  if (!VALID_ACTIONS.has(report.action)) {
    throw new TypeError(`Unsupported VM session action: ${report.action}`);
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  requireString(report.status, "status");
  if (!VALID_STATUSES.has(report.status)) {
    throw new TypeError(`Unsupported VM session status: ${report.status}`);
  }

  requireString(report.state, "state");
  if (!VALID_VM_STATES.has(report.state)) {
    throw new TypeError(`Unsupported VM state: ${report.state}`);
  }

  requireString(report.provider, "provider");
  requireBoolean(report.canSuspend, "canSuspend");
  requireBoolean(report.canResume, "canResume");

  validatePersistence(report.persistence);
  validateStateAgreement(report);
  validateCapabilityAgreement(report);
  validateErrorMessage(report);
  validateNextActions(report);

  return report;
}

function validatePersistence(persistence) {
  if (!persistence || typeof persistence !== "object" || Array.isArray(persistence)) {
    throw new TypeError("persistence must be an object.");
  }

  requireBoolean(persistence.isSupported, "persistence.isSupported");
  requireString(persistence.mode, "persistence.mode");
  if (!VALID_PERSISTENCE_MODES.has(persistence.mode)) {
    throw new TypeError(`Unsupported persistence mode: ${persistence.mode}`);
  }
  requireString(persistence.detail, "persistence.detail");

  if (persistence.isSupported !== (persistence.mode === MEMORY_STATE_FILE_MODE)) {
    throw new TypeError("persistence.isSupported must agree with persistence.mode.");
  }

  if (!persistence.isSupported) {
    if (persistence.stateFilePath !== undefined) {
      throw new TypeError("unsupported persistence must not advertise a memory state file path.");
    }
    return;
  }

  requireString(persistence.stateFilePath, "persistence.stateFilePath");
  if (persistence.stateFilePath.includes(DIAGNOSTICS_PATH_MARKER)) {
    throw new TypeError(
      "persistence.stateFilePath must not live under Diagnostics; guest memory is not metadata."
    );
  }
  if (!persistence.stateFilePath.startsWith("/")) {
    throw new TypeError("persistence.stateFilePath must be an absolute path.");
  }

  if (persistence.stateFileByteCount !== undefined) {
    requireInteger(persistence.stateFileByteCount, "persistence.stateFileByteCount");
    if (persistence.stateFileByteCount <= 0) {
      throw new TypeError("persistence.stateFileByteCount must be positive when present.");
    }
  }

  if (persistence.machineFingerprint !== undefined) {
    requireString(persistence.machineFingerprint, "persistence.machineFingerprint");
    // Both schemes are accepted. `fnv1a64/2` excludes host port forwarding from the hash so that
    // turning the shared folder on or off no longer invalidates a suspended session; `fnv1a64` is what
    // sessions suspended before that change recorded. A report describing an older suspend is still a
    // valid report, so the validator must not reject it -- resume is where the two are told apart.
    const recognizedSchemes = ["fnv1a64/2:", "fnv1a64:"];
    if (!recognizedSchemes.some((scheme) => persistence.machineFingerprint.startsWith(scheme))) {
      throw new TypeError("persistence.machineFingerprint must be a recognized fingerprint.");
    }
  }

  if (persistence.suspendedAt !== undefined) {
    requireString(persistence.suspendedAt, "persistence.suspendedAt");
    if (Number.isNaN(Date.parse(persistence.suspendedAt))) {
      throw new TypeError("persistence.suspendedAt must be an ISO date.");
    }
  }
}

function validateStateAgreement(report) {
  if (report.status === "suspended" && report.state !== "suspended") {
    throw new TypeError("suspended VM session reports must report state suspended.");
  }
  if (report.status === "resumed" && report.state !== "running") {
    throw new TypeError("resumed VM session reports must report state running.");
  }
  if (report.status === "stopped" && report.state !== "stopped") {
    throw new TypeError("stopped VM session reports must report state stopped.");
  }

  // A completed suspend has to leave durable evidence, otherwise "suspended" is a claim with
  // nothing behind it.
  if (report.action === "suspend" && report.status === "suspended") {
    if (!report.persistence.suspendedAt || !report.persistence.machineFingerprint) {
      throw new TypeError(
        "a completed suspend must record suspendedAt and machineFingerprint evidence."
      );
    }
  }

  // Resume consumes the stream: reusing it against a disk that has moved on would corrupt Windows.
  if (report.action === "resume" && report.status === "resumed") {
    if (report.persistence.suspendedAt !== undefined) {
      throw new TypeError("a completed resume must clear the suspended session evidence.");
    }
    if (report.canResume) {
      throw new TypeError("a completed resume must not still advertise canResume.");
    }
  }
}

function validateCapabilityAgreement(report) {
  // Checked first because it is the strongest invariant: a machine is either executing (suspendable)
  // or persisted (resumable), never both. Reporting both would let a UI offer two mutually exclusive
  // primary actions at once.
  if (report.canSuspend && report.canResume) {
    throw new TypeError("a VM session cannot be suspendable and resumable at the same time.");
  }
  if (report.canSuspend && report.state !== "running") {
    throw new TypeError("canSuspend requires a running VM state.");
  }
  if (report.canSuspend && !report.persistence.isSupported) {
    throw new TypeError("canSuspend requires supported session persistence.");
  }
  if (report.canResume && report.state !== "suspended") {
    throw new TypeError("canResume requires a suspended VM state.");
  }
  if (report.canResume && !report.persistence.suspendedAt) {
    throw new TypeError("canResume requires stored suspended session evidence.");
  }
}

function validateErrorMessage(report) {
  if (report.status === "failed") {
    requireString(report.errorMessage, "errorMessage");
    return;
  }

  if (report.status !== "unavailable" && report.errorMessage !== undefined) {
    throw new TypeError(`${report.status} VM session reports must not include errorMessage.`);
  }
}

function validateNextActions(report) {
  if (!Array.isArray(report.nextActions) || report.nextActions.length === 0) {
    throw new TypeError("nextActions must be a non-empty array.");
  }

  for (const action of report.nextActions) {
    requireString(action, "nextActions[]");
  }

  if (report.canResume && !report.nextActions.some((action) => action.includes("vm-resume"))) {
    throw new TypeError("resumable VM session reports must include a vm-resume next action.");
  }
  if (report.canSuspend && !report.nextActions.some((action) => action.includes("vm-suspend"))) {
    throw new TypeError("suspendable VM session reports must include a vm-suspend next action.");
  }
  if (report.status === "stopped" && !report.nextActions.some((action) => action.includes("qemu-start"))) {
    throw new TypeError("stopped VM session reports must include a start next action.");
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`VM session field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`VM session field '${fieldName}' must be boolean.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`VM session field '${fieldName}' must be an integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected VM session JSON on stdin.");
  }

  validateVMSession(JSON.parse(input));
  process.stdout.write("vm session valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
