import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_ACTIONS = new Set(["list", "create", "restore", "delete"]);
const VALID_STATUSES = new Set(["succeeded", "unavailable", "failed"]);
const VALID_SUPPORT_STATES = new Set([
  "supported",
  "unsupportedDiskFormat",
  "unsupportedProvider",
  "notConfigured"
]);
const VALID_VM_STATES = new Set([
  "unsupported",
  "notConfigured",
  "stopped",
  "starting",
  "running",
  "suspended",
  "failed"
]);
const REQUIRED_DISK_FORMAT = "qcow2";
/// Actions that mutate guest state need a running machine so RAM and disk stay consistent. `list` is
/// intentionally excluded because it is read-only and also works offline through qemu-img.
const RUNNING_ONLY_ACTIONS = new Set(["create", "restore", "delete"]);

export function validateVMSnapshots(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("VM snapshot report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "vmSnapshotAction") {
    throw new TypeError(`Unsupported VM snapshot kind: ${report.kind}`);
  }

  requireString(report.action, "action");
  if (!VALID_ACTIONS.has(report.action)) {
    throw new TypeError(`Unsupported VM snapshot action: ${report.action}`);
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  requireString(report.status, "status");
  if (!VALID_STATUSES.has(report.status)) {
    throw new TypeError(`Unsupported VM snapshot status: ${report.status}`);
  }

  requireString(report.vmState, "vmState");
  if (!VALID_VM_STATES.has(report.vmState)) {
    throw new TypeError(`Unsupported VM state: ${report.vmState}`);
  }

  requireString(report.provider, "provider");
  validateCapability(report.capability);
  validateStatusAgreement(report);
  validateSnapshots(report);
  validateRequestedTag(report);
  validateNextActions(report);

  return report;
}

function validateCapability(capability) {
  if (!capability || typeof capability !== "object" || Array.isArray(capability)) {
    throw new TypeError("capability must be an object.");
  }

  requireString(capability.state, "capability.state");
  if (!VALID_SUPPORT_STATES.has(capability.state)) {
    throw new TypeError(`Unsupported snapshot support state: ${capability.state}`);
  }
  requireBoolean(capability.isSupported, "capability.isSupported");
  if (capability.isSupported !== (capability.state === "supported")) {
    throw new TypeError("capability.isSupported must agree with capability.state.");
  }

  requireString(capability.requiredDiskFormat, "capability.requiredDiskFormat");
  if (capability.requiredDiskFormat !== REQUIRED_DISK_FORMAT) {
    throw new TypeError(`QEMU internal snapshots require ${REQUIRED_DISK_FORMAT}.`);
  }
  requireString(capability.detail, "capability.detail");

  if (capability.state === "supported") {
    requireString(capability.systemDiskFormat, "capability.systemDiskFormat");
    if (capability.systemDiskFormat !== REQUIRED_DISK_FORMAT) {
      throw new TypeError("supported snapshot capability must report a qcow2 system disk.");
    }
    requireString(capability.systemDiskPath, "capability.systemDiskPath");
    if (capability.conversionCommand !== undefined) {
      throw new TypeError("supported snapshot capability must not advertise a disk conversion.");
    }
    return;
  }

  // An unsupported-format report is only actionable if it names the conversion. Without it the user
  // is told "no" with no way forward, which is the failure mode this contract exists to prevent.
  if (capability.state === "unsupportedDiskFormat") {
    requireString(capability.systemDiskFormat, "capability.systemDiskFormat");
    if (capability.systemDiskFormat === REQUIRED_DISK_FORMAT) {
      throw new TypeError("unsupportedDiskFormat must not report a qcow2 system disk.");
    }
    requireString(capability.systemDiskPath, "capability.systemDiskPath");
    requireString(capability.convertedDiskPath, "capability.convertedDiskPath");
    requireString(capability.conversionCommand, "capability.conversionCommand");
    if (!capability.conversionCommand.includes("qemu-img convert")) {
      throw new TypeError("capability.conversionCommand must use qemu-img convert.");
    }
    if (!capability.conversionCommand.includes(`-O ${REQUIRED_DISK_FORMAT}`)) {
      throw new TypeError(`capability.conversionCommand must target ${REQUIRED_DISK_FORMAT}.`);
    }
    if (!capability.convertedDiskPath.endsWith(`.${REQUIRED_DISK_FORMAT}`)) {
      throw new TypeError(`capability.convertedDiskPath must be a .${REQUIRED_DISK_FORMAT} file.`);
    }
  }
}

function validateStatusAgreement(report) {
  if (report.status === "unavailable" && report.capability.isSupported) {
    throw new TypeError("unavailable snapshot reports must carry an unsupported capability.");
  }
  if (report.status !== "unavailable" && !report.capability.isSupported) {
    throw new TypeError("only unavailable snapshot reports may carry an unsupported capability.");
  }

  if (report.status === "failed") {
    requireString(report.errorMessage, "errorMessage");
  } else if (report.status === "succeeded" && report.errorMessage !== undefined) {
    throw new TypeError("succeeded snapshot reports must not include errorMessage.");
  }

  // A mutating snapshot action can only have succeeded against a live machine.
  if (report.status === "succeeded" && RUNNING_ONLY_ACTIONS.has(report.action) && report.vmState !== "running") {
    throw new TypeError(`a succeeded ${report.action} requires a running VM state.`);
  }
}

function validateSnapshots(report) {
  if (!Array.isArray(report.snapshots)) {
    throw new TypeError("snapshots must be an array.");
  }

  if (!report.capability.isSupported && report.snapshots.length > 0) {
    throw new TypeError("unsupported snapshot capability must not list snapshots.");
  }

  const tags = new Set();
  for (const snapshot of report.snapshots) {
    if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
      throw new TypeError("snapshots[] entries must be objects.");
    }

    requireString(snapshot.id, "snapshots[].id");
    requireString(snapshot.tag, "snapshots[].tag");
    // The snapshot table is parsed positionally, so a tag with whitespace would silently shift every
    // later column.
    if (/\s/.test(snapshot.tag)) {
      throw new TypeError("snapshots[].tag must not contain whitespace.");
    }
    if (tags.has(snapshot.tag)) {
      throw new TypeError(`snapshots[] contains a duplicate tag: ${snapshot.tag}`);
    }
    tags.add(snapshot.tag);

    requireString(snapshot.vmStateSize, "snapshots[].vmStateSize");
    requireString(snapshot.createdAt, "snapshots[].createdAt");
    if (Number.isNaN(Date.parse(snapshot.createdAt))) {
      throw new TypeError("snapshots[].createdAt must be parseable as a date.");
    }
    requireString(snapshot.vmClock, "snapshots[].vmClock");
  }

  if (report.status === "succeeded" && report.action === "create") {
    if (!tags.has(report.requestedTag)) {
      throw new TypeError("a succeeded create must list the newly created snapshot tag.");
    }
  }
  if (report.status === "succeeded" && report.action === "delete") {
    if (tags.has(report.requestedTag)) {
      throw new TypeError("a succeeded delete must not still list the deleted snapshot tag.");
    }
  }
}

function validateRequestedTag(report) {
  if (report.action === "list") {
    return;
  }

  requireString(report.requestedTag, "requestedTag");
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(report.requestedTag)) {
    throw new TypeError("requestedTag must be 1-64 characters of letters, digits, dot, dash, or underscore.");
  }
}

function validateNextActions(report) {
  if (!Array.isArray(report.nextActions) || report.nextActions.length === 0) {
    throw new TypeError("nextActions must be a non-empty array.");
  }

  for (const action of report.nextActions) {
    requireString(action, "nextActions[]");
  }

  if (report.status === "unavailable") {
    if (!report.nextActions.some((action) => action.includes("vm-suspend"))) {
      throw new TypeError(
        "unavailable snapshot reports must point at vm-suspend, which works on the shipping disk format."
      );
    }
    if (
      report.capability.state === "unsupportedDiskFormat"
      && !report.nextActions.some((action) => action.includes("qemu-img convert"))
    ) {
      throw new TypeError("unsupportedDiskFormat reports must include the qemu-img convert next action.");
    }
  }

  if (report.status === "succeeded" && report.action === "restore") {
    if (!report.nextActions.some((action) => action.includes("guest-agent-wait"))) {
      throw new TypeError(
        "a restored snapshot must point at guest-agent reconnection before Windows apps are launched."
      );
    }
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`VM snapshot field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`VM snapshot field '${fieldName}' must be boolean.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected VM snapshot JSON on stdin.");
  }

  validateVMSnapshots(JSON.parse(input));
  process.stdout.write("vm snapshots valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
