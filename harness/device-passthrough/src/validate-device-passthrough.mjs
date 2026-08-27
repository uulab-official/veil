import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_STATES = new Set([
  "available",
  "requiresPrivilegedHelper",
  "notBuiltIntoQEMU",
  "unsupportedOnThisPlatform",
  "unknown"
]);

/// Every capability the report must cover. Silently dropping one would let a gap disappear from the
/// answer rather than be reported as unavailable.
const REQUIRED_CAPABILITY_IDS = [
  "usb-passthrough",
  "network-bridged",
  "network-host-only",
  "network-usermode-nat"
];

export function validateDevicePassthrough(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("Device passthrough report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "vmDevicePassthroughStatus") {
    throw new TypeError(`Unsupported device passthrough kind: ${report.kind}`);
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  requireString(report.provider, "provider");
  requireBoolean(report.didProbeQEMU, "didProbeQEMU");
  if (report.qemuExecutablePath !== undefined) {
    requireString(report.qemuExecutablePath, "qemuExecutablePath");
  }

  validateCapabilities(report);
  validatePrivilegedHelperDecision(report);
  validateNextActions(report);

  return report;
}

function validateCapabilities(report) {
  if (!Array.isArray(report.capabilities) || report.capabilities.length === 0) {
    throw new TypeError("capabilities must be a non-empty array.");
  }

  const seen = new Set();
  for (const capability of report.capabilities) {
    if (!capability || typeof capability !== "object" || Array.isArray(capability)) {
      throw new TypeError("capabilities[] entries must be objects.");
    }

    requireString(capability.id, "capabilities[].id");
    if (seen.has(capability.id)) {
      throw new TypeError(`capabilities[] contains a duplicate id: ${capability.id}`);
    }
    seen.add(capability.id);

    requireString(capability.title, "capabilities[].title");
    requireString(capability.state, "capabilities[].state");
    if (!VALID_STATES.has(capability.state)) {
      throw new TypeError(`Unsupported device passthrough state: ${capability.state}`);
    }
    requireBoolean(capability.isAvailable, "capabilities[].isAvailable");
    requireBoolean(capability.requiresPrivilegedHelper, "capabilities[].requiresPrivilegedHelper");
    requireString(capability.detail, "capabilities[].detail");

    if (capability.isAvailable !== (capability.state === "available")) {
      throw new TypeError("capabilities[].isAvailable must agree with capabilities[].state.");
    }

    // The whole point of this report is that a "no" comes with a reason. An unavailable capability with
    // no prerequisite is the failure mode it exists to prevent.
    if (!capability.isAvailable) {
      requireString(capability.prerequisite, `capabilities[${capability.id}].prerequisite`);
    } else if (capability.prerequisite !== undefined) {
      throw new TypeError("an available capability must not carry a prerequisite.");
    }

    if (capability.requiresPrivilegedHelper && capability.state !== "requiresPrivilegedHelper") {
      throw new TypeError("capabilities[].requiresPrivilegedHelper must agree with its state.");
    }
    if (capability.state === "requiresPrivilegedHelper" && !capability.requiresPrivilegedHelper) {
      throw new TypeError("a requiresPrivilegedHelper state must set requiresPrivilegedHelper.");
    }

    if (capability.alternative !== undefined) {
      requireString(capability.alternative, "capabilities[].alternative");
      if (capability.isAvailable) {
        throw new TypeError("an available capability must not offer an alternative to itself.");
      }
    }

    if (capability.reference !== undefined) {
      requireString(capability.reference, "capabilities[].reference");
      if (!capability.reference.startsWith("https://")) {
        throw new TypeError("capabilities[].reference must be an https URL so the claim can be checked.");
      }
    }
  }

  for (const id of REQUIRED_CAPABILITY_IDS) {
    if (!seen.has(id)) {
      throw new TypeError(`capabilities must cover ${id}.`);
    }
  }

  // Usermode NAT is what Veil actually ships. If it is ever reported unavailable the guest has no
  // network at all, which is a different and much larger problem than a missing passthrough mode.
  const nat = report.capabilities.find((capability) => capability.id === "network-usermode-nat");
  if (!nat.isAvailable) {
    throw new TypeError("usermode NAT networking is the shipping default and must be available.");
  }

  // A report that cannot see QEMU cannot know whether usb-host exists, so it must say unknown rather
  // than assert either answer.
  const usb = report.capabilities.find((capability) => capability.id === "usb-passthrough");
  if (!report.didProbeQEMU && usb.state !== "unknown") {
    throw new TypeError("USB passthrough state must be unknown when QEMU was not probed.");
  }
  if (report.didProbeQEMU && usb.state === "unknown") {
    throw new TypeError("USB passthrough state must be resolved when QEMU was probed.");
  }
}

function validatePrivilegedHelperDecision(report) {
  requireString(report.privilegedHelperDecision, "privilegedHelperDecision");

  const needsHelper = report.capabilities.some((capability) => capability.requiresPrivilegedHelper);
  if (!needsHelper) {
    return;
  }

  // The decision text is what turns "unavailable" into something a reader can act on. It has to name
  // the mechanism, and it has to rule out the dangerous shortcut rather than leaving it implied.
  if (!report.privilegedHelperDecision.includes("privileged helper")) {
    throw new TypeError("privilegedHelperDecision must name the privileged helper mechanism.");
  }
  if (!/sudo/i.test(report.privilegedHelperDecision)) {
    throw new TypeError("privilegedHelperDecision must explicitly rule out running QEMU under sudo.");
  }
}

function validateNextActions(report) {
  if (!Array.isArray(report.nextActions) || report.nextActions.length === 0) {
    throw new TypeError("nextActions must be a non-empty array.");
  }

  for (const action of report.nextActions) {
    requireString(action, "nextActions[]");
  }

  const joined = report.nextActions.join(" ");

  if (report.capabilities.some((capability) => capability.requiresPrivilegedHelper)) {
    if (!/sudo/i.test(joined)) {
      throw new TypeError("a report needing a privileged helper must warn against running QEMU under sudo.");
    }
    // Presenting this as pending implementation work would be misleading: no amount of host code closes
    // it, and a contributor should not start writing any.
    if (!joined.includes("decision")) {
      throw new TypeError("a report needing a privileged helper must present it as an open decision.");
    }
  }

  if (report.capabilities.some((capability) => capability.state === "unknown")) {
    if (!joined.includes("qemu-doctor")) {
      throw new TypeError("an unknown capability must point at qemu-doctor to resolve the installation.");
    }
  }

  // Every unavailable capability that has an alternative must surface it, or the report tells a user what
  // they cannot do without telling them what they can.
  for (const capability of report.capabilities) {
    if (capability.isAvailable || capability.alternative === undefined) {
      continue;
    }
    if (!joined.includes(capability.alternative)) {
      throw new TypeError(`nextActions must surface the alternative for ${capability.id}.`);
    }
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Device passthrough field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`Device passthrough field '${fieldName}' must be boolean.`);
  }
}

function main() {
  const input = readFileSync(0, "utf8").trim();
  if (!input) {
    throw new TypeError("Expected device passthrough JSON on stdin.");
  }

  validateDevicePassthrough(JSON.parse(input));
  process.stdout.write("device passthrough valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
