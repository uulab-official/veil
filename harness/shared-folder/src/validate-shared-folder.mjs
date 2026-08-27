import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_TRANSPORTS = new Set(["guest-smb", "host-smb", "none"]);
const VALID_SUPPORT_STATES = new Set([
  "supported",
  "unsupportedTransport",
  "disabled",
  "hostPortUnavailable",
  "forwardMissingFromPlan",
  "notConfigured"
]);
const VALID_READINESS = new Set([
  "ready",
  "awaitingVM",
  "awaitingGuestAgent",
  "awaitingGuestShare",
  "awaitingHostMount",
  "unavailable"
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
const SHARE_PORT = 18445;

export function validateSharedFolder(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("Shared folder report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "vmSharedFolderStatus") {
    throw new TypeError(`Unsupported shared folder kind: ${report.kind}`);
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  requireString(report.provider, "provider");

  requireString(report.vmState, "vmState");
  if (!VALID_VM_STATES.has(report.vmState)) {
    throw new TypeError(`Unsupported VM state: ${report.vmState}`);
  }

  requireString(report.readiness, "readiness");
  if (!VALID_READINESS.has(report.readiness)) {
    throw new TypeError(`Unsupported shared folder readiness: ${report.readiness}`);
  }

  validateCapability(report.capability);
  validateHostMount(report.hostMount);
  if (report.guest !== undefined) {
    validateGuest(report.guest, report.capability);
  }
  validateReadinessAgreement(report);
  validateStagingFolderIsNotTheShare(report);
  validateNextActions(report);

  return report;
}

function validateCapability(capability) {
  if (!capability || typeof capability !== "object" || Array.isArray(capability)) {
    throw new TypeError("capability must be an object.");
  }

  requireString(capability.state, "capability.state");
  if (!VALID_SUPPORT_STATES.has(capability.state)) {
    throw new TypeError(`Unsupported shared folder support state: ${capability.state}`);
  }
  requireBoolean(capability.isSupported, "capability.isSupported");
  if (capability.isSupported !== (capability.state === "supported")) {
    throw new TypeError("capability.isSupported must agree with capability.state.");
  }

  requireString(capability.transport, "capability.transport");
  if (!VALID_TRANSPORTS.has(capability.transport)) {
    throw new TypeError(`Unsupported shared folder transport: ${capability.transport}`);
  }

  requireBoolean(capability.isWiredIntoBootPlan, "capability.isWiredIntoBootPlan");
  requireString(capability.detail, "capability.detail");
  requireString(capability.overrideEnvironmentVariable, "capability.overrideEnvironmentVariable");
  if (capability.overrideEnvironmentVariable !== "VEIL_QEMU_SHARED_FOLDER") {
    throw new TypeError("capability.overrideEnvironmentVariable must name the documented override.");
  }

  // Checked before the per-state completeness rules. "This transport can never be supported" is a more
  // fundamental disagreement than "a supported report is missing a field", and reporting the missing
  // field first would send a reader off filling in values for a state that is itself impossible.
  //
  // host-smb is the direction Veil does not ship. Reporting it as anything but unsupported would offer
  // an action that cannot work until the user turns on macOS File Sharing themselves.
  if (capability.transport === "host-smb" && capability.state !== "unsupportedTransport") {
    throw new TypeError("the host-smb transport must be reported as unsupportedTransport.");
  }
  if (capability.transport === "none" && capability.state !== "disabled") {
    throw new TypeError("the none transport must be reported as disabled.");
  }
  if (capability.state === "supported" && capability.transport !== "guest-smb") {
    throw new TypeError("only the guest-smb transport can be supported.");
  }

  // A supported capability is the one state that promises the whole path exists, so it has to name
  // every part of it. Anything less would let the report claim support while leaving the user without
  // a share name, a guest folder, or a URL to mount.
  if (capability.state === "supported") {
    if (!capability.isWiredIntoBootPlan) {
      throw new TypeError("a supported shared folder capability must be wired into the boot plan.");
    }
    requireString(capability.shareName, "capability.shareName");
    requireString(capability.expectedGuestDirectoryPath, "capability.expectedGuestDirectoryPath");
    requireString(capability.hostMountURL, "capability.hostMountURL");
    requireString(capability.expectedHostMountPath, "capability.expectedHostMountPath");
    requireString(capability.hostForwardClause, "capability.hostForwardClause");
  } else if (capability.isWiredIntoBootPlan) {
    throw new TypeError("only a supported shared folder capability may report being wired into the boot plan.");
  }

  if (capability.hostForwardClause !== undefined) {
    // An empty host address in a hostfwd clause binds every interface, which would publish the guest's
    // SMB server to the local network. The loopback address is the whole reason this is safe.
    if (!capability.hostForwardClause.startsWith(`hostfwd=tcp:127.0.0.1:${SHARE_PORT}-`)) {
      throw new TypeError(
        "capability.hostForwardClause must bind the shared folder port to 127.0.0.1 only."
      );
    }
    if (!capability.hostForwardClause.endsWith(":445")) {
      throw new TypeError("capability.hostForwardClause must forward to the guest SMB port.");
    }
  }

  if (capability.hostMountURL !== undefined) {
    if (!capability.hostMountURL.startsWith(`smb://127.0.0.1:${SHARE_PORT}/`)) {
      throw new TypeError("capability.hostMountURL must mount the loopback forward, not a network host.");
    }
    if (capability.shareName !== undefined
      && !capability.hostMountURL.endsWith(`/${capability.shareName}`)) {
      throw new TypeError("capability.hostMountURL must end with capability.shareName.");
    }
  }
}

function validateGuest(guest, capability) {
  if (!guest || typeof guest !== "object" || Array.isArray(guest)) {
    throw new TypeError("guest must be an object when present.");
  }

  for (const field of [
    "isSupported",
    "directoryExists",
    "isShared",
    "isWritable",
    "serverListening",
    "requiresElevation",
    "requiresCredentials"
  ]) {
    requireBoolean(guest[field], `guest.${field}`);
  }

  requireString(guest.shareName, "guest.shareName");
  requireString(guest.guestDirectoryPath, "guest.guestDirectoryPath");
  requireString(guest.recommendedAction, "guest.recommendedAction");

  if (guest.isShared && !guest.directoryExists) {
    throw new TypeError("guest.isShared cannot be true while guest.directoryExists is false.");
  }
  if (guest.isWritable && !guest.isShared) {
    throw new TypeError("guest.isWritable cannot be true while guest.isShared is false.");
  }
  if (!guest.isSupported && (guest.isShared || guest.serverListening)) {
    throw new TypeError("guest.isSupported must be true when the guest reports a share or a listening server.");
  }
  if (guest.requiresElevation && !guest.isShared) {
    requireString(guest.shareCommand, "guest.shareCommand");
    if (!guest.shareCommand.includes("New-SmbShare")) {
      throw new TypeError("guest.shareCommand must be the elevated New-SmbShare command.");
    }
  }
  if (!guest.requiresElevation && !guest.isShared) {
    throw new TypeError("a missing share always still needs an administrator to publish it.");
  }

  // The host names the share so the Mac cannot mount something other than what Windows published.
  // A disagreement here is exactly the silent failure the request/response pair exists to prevent.
  if (capability.shareName !== undefined && guest.shareName !== capability.shareName) {
    throw new TypeError("guest.shareName must match the share name the host asked for.");
  }
  if (capability.expectedGuestDirectoryPath !== undefined
    && guest.guestDirectoryPath !== capability.expectedGuestDirectoryPath) {
    throw new TypeError("guest.guestDirectoryPath must match the folder the host asked for.");
  }
}

function validateHostMount(hostMount) {
  if (!hostMount || typeof hostMount !== "object" || Array.isArray(hostMount)) {
    throw new TypeError("hostMount must be an object.");
  }

  requireBoolean(hostMount.isMounted, "hostMount.isMounted");
  requireString(hostMount.detail, "hostMount.detail");

  if (hostMount.isMounted) {
    requireString(hostMount.mountPath, "hostMount.mountPath");
    if (!hostMount.mountPath.startsWith("/Volumes/")) {
      throw new TypeError("hostMount.mountPath must be under /Volumes.");
    }
  } else if (hostMount.mountPath !== undefined) {
    throw new TypeError("hostMount.mountPath must be absent when nothing is mounted.");
  }
}

function validateReadinessAgreement(report) {
  const { capability, guest, hostMount, readiness, vmState } = report;

  if (!capability.isSupported) {
    if (readiness !== "unavailable") {
      throw new TypeError("an unsupported capability must report readiness 'unavailable'.");
    }
    return;
  }

  if (readiness === "unavailable") {
    throw new TypeError("readiness 'unavailable' requires an unsupported capability.");
  }

  // Checked before the guest, because an unreachable agent on a machine that is off is expected rather
  // than a fault, and reporting it as an agent problem sends the user diagnosing the wrong thing.
  if (vmState !== "running") {
    if (readiness !== "awaitingVM") {
      throw new TypeError("a supported shared folder on a VM that is not running must report 'awaitingVM'.");
    }
    if (guest !== undefined) {
      throw new TypeError("a guest report cannot exist while the VM is not running.");
    }
    return;
  }

  if (guest === undefined) {
    if (readiness !== "awaitingGuestAgent") {
      throw new TypeError("a missing guest report must report readiness 'awaitingGuestAgent'.");
    }
    return;
  }

  const guestReady = guest.isShared && guest.isWritable && guest.serverListening;
  if (!guestReady) {
    if (readiness !== "awaitingGuestShare") {
      throw new TypeError("a guest that is not sharing a writable, reachable folder must report 'awaitingGuestShare'.");
    }
    return;
  }

  if (!hostMount.isMounted) {
    if (readiness !== "awaitingHostMount") {
      throw new TypeError("a guest-ready share that is not mounted must report 'awaitingHostMount'.");
    }
    return;
  }

  if (readiness !== "ready") {
    throw new TypeError("a mounted, guest-ready, supported share must report readiness 'ready'.");
  }
}

function validateStagingFolderIsNotTheShare(report) {
  if (report.hostStagingFolderPath === undefined) {
    return;
  }

  requireString(report.hostStagingFolderPath, "hostStagingFolderPath");
  // `sharedFolderPath` on the VM profile is named like the feature but is a macOS install-media staging
  // directory that was never shared with the guest. Confusing the two would tell a user their Mac
  // folder is visible in Windows when it is not.
  if (report.hostStagingFolderPath === report.hostMount.mountPath) {
    throw new TypeError("hostStagingFolderPath is the macOS install-media folder and must not be the mount path.");
  }
  if (report.capability.expectedGuestDirectoryPath !== undefined
    && report.hostStagingFolderPath === report.capability.expectedGuestDirectoryPath) {
    throw new TypeError("hostStagingFolderPath must not be reported as the guest share folder.");
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

  switch (report.readiness) {
    case "unavailable":
      // An unsupported transport is only actionable if the report names the way forward. host-smb has to
      // offer the guest-served transport that needs no host setup, and it has to admit the security
      // tradeoff of turning on macOS File Sharing rather than presenting it as a plain fix.
      if (report.capability.transport === "host-smb") {
        if (!joined.includes("guest-smb")) {
          throw new TypeError("an unsupported host-smb report must offer the guest-smb transport.");
        }
        if (!joined.includes("every network interface")) {
          throw new TypeError("an unsupported host-smb report must state that File Sharing is not guest-only.");
        }
      }
      if (report.capability.state === "hostPortUnavailable" && !joined.includes(String(SHARE_PORT))) {
        throw new TypeError("a port-conflict report must name the port that is in use.");
      }
      break;

    case "awaitingVM":
      if (!joined.includes("qemu-start")) {
        throw new TypeError("an awaitingVM report must say how to start Windows.");
      }
      break;

    case "awaitingGuestAgent":
      if (!joined.includes("guest-agent-wait")) {
        throw new TypeError("an awaitingGuestAgent report must point at the guest-agent wait command.");
      }
      // An agent that predates the shared folder protocol is indistinguishable from an unreachable one
      // here, so the report has to mention reinstalling rather than only reconnecting.
      if (!joined.includes("qemu-install-agent")) {
        throw new TypeError("an awaitingGuestAgent report must cover an agent that predates this protocol.");
      }
      break;

    case "awaitingGuestShare":
      if (report.guest?.requiresElevation && !joined.includes("New-SmbShare")) {
        throw new TypeError("an elevation-blocked report must include the elevated share command.");
      }
      if (report.guest?.serverListening === false) {
        if (!joined.includes("Enable-NetFirewallRule")) {
          throw new TypeError("an unreachable SMB server report must include the firewall command.");
        }
        // Opening SMB inside the guest is only safe because the guest's only network is an isolated
        // usermode NAT. Saying so keeps the instruction from reading as "expose SMB to your network".
        if (!joined.includes("usermode NAT")) {
          throw new TypeError("a firewall next action must state that the guest network is isolated.");
        }
      }
      break;

    case "awaitingHostMount":
      if (!joined.includes(report.capability.hostMountURL)) {
        throw new TypeError("an awaitingHostMount report must include the URL that mounts the share.");
      }
      break;

    case "ready":
      // The share exists to replace the capped one-shot copy for anything large, so a ready report says
      // so rather than leaving the user on the old path out of habit.
      if (!joined.includes("50 MB")) {
        throw new TypeError("a ready report must contrast the share with the 50 MB file-open cap.");
      }
      break;

    default:
      throw new TypeError(`Unhandled readiness: ${report.readiness}`);
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Shared folder field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`Shared folder field '${fieldName}' must be boolean.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected shared folder JSON on stdin.");
  }

  validateSharedFolder(JSON.parse(input));
  process.stdout.write("shared folder valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
