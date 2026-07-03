import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_STATES = new Set(["unsupported", "notConfigured", "stopped", "starting", "running", "suspended", "failed"]);
const VALID_INSTALL_EVIDENCE = new Set(["notConfigured", "setupBlocked", "sparseDisk", "setupReady", "profileFlag", "guestAgent"]);
const VALID_PREVIEW_STATUSES = new Set(["fresh", "stale", "unavailable"]);

export function validateQEMUInstallStatus(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("QEMU install status report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "qemuWindowsInstallStatus") {
    throw new TypeError(`Unsupported QEMU install status kind: ${report.kind}`);
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  requireString(report.state, "state");
  if (!VALID_STATES.has(report.state)) {
    throw new TypeError(`Unsupported QEMU install status state: ${report.state}`);
  }

  requireBoolean(report.bootReady, "bootReady");
  requireBoolean(report.windowsInstalled, "windowsInstalled");
  validateInstallEvidence(report.installEvidence);
  validateOptionalPath(report.installerMediaPath, "installerMediaPath");
  validateOptionalPath(report.driverMediaPath, "driverMediaPath");
  validateOptionalPath(report.virtualDiskPath, "virtualDiskPath");
  validateOptionalPath(report.automaticInstallMediaPath, "automaticInstallMediaPath");
  validateOptionalPath(report.latestConsoleScreenshotPath, "latestConsoleScreenshotPath");
  validateNextActions(report.nextActions);

  if (report.profileName !== undefined) {
    requireString(report.profileName, "profileName");
  }

  if (report.latestConsoleLaunch !== undefined) {
    validateConsoleLaunch(report.latestConsoleLaunch);
  }

  if (report.state === "running"
    && report.latestConsoleLaunch !== undefined
    && !report.nextActions.some((action) => action.includes("qemu-capture"))) {
    throw new TypeError("running install status reports with launch evidence must include qemu-capture recovery guidance.");
  }

  return report;
}

function validateInstallEvidence(evidence) {
  if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) {
    throw new TypeError("installEvidence must be an object.");
  }

  requireString(evidence.kind, "installEvidence.kind");
  if (!VALID_INSTALL_EVIDENCE.has(evidence.kind)) {
    throw new TypeError(`Unsupported install evidence kind: ${evidence.kind}`);
  }
  requireBoolean(evidence.isInstalled, "installEvidence.isInstalled");
  requireString(evidence.title, "installEvidence.title");
  requireString(evidence.detail, "installEvidence.detail");
}

function validateConsoleLaunch(launch) {
  if (!launch || typeof launch !== "object" || Array.isArray(launch)) {
    throw new TypeError("latestConsoleLaunch must be an object.");
  }

  requireString(launch.provider, "latestConsoleLaunch.provider");
  requireString(launch.processLogPath, "latestConsoleLaunch.processLogPath");
  requireString(launch.monitorSocketPath, "latestConsoleLaunch.monitorSocketPath");
  requireString(launch.previewStatus, "latestConsoleLaunch.previewStatus");
  requireString(launch.startedAt, "latestConsoleLaunch.startedAt");

  if (launch.provider !== "QEMU/HVF") {
    throw new TypeError("latestConsoleLaunch.provider must be QEMU/HVF.");
  }
  if (!VALID_PREVIEW_STATUSES.has(launch.previewStatus)) {
    throw new TypeError(`Unsupported console preview status: ${launch.previewStatus}`);
  }
  if (Number.isNaN(Date.parse(launch.startedAt))) {
    throw new TypeError("latestConsoleLaunch.startedAt must be an ISO date.");
  }
  if (launch.pid !== undefined && launch.pid !== null) {
    requireInteger(launch.pid, "latestConsoleLaunch.pid");
  }
  if (launch.qmpSocketPath !== undefined) {
    requireString(launch.qmpSocketPath, "latestConsoleLaunch.qmpSocketPath");
  }
  if (launch.consoleScreenshotPath !== undefined) {
    validateOptionalPath(launch.consoleScreenshotPath, "latestConsoleLaunch.consoleScreenshotPath");
    if (!launch.consoleScreenshotPath.endsWith(".png")) {
      throw new TypeError("latestConsoleLaunch.consoleScreenshotPath must point to a .png image.");
    }
  }
  if (launch.consoleScreenshotRefreshedAt !== undefined && Number.isNaN(Date.parse(launch.consoleScreenshotRefreshedAt))) {
    throw new TypeError("latestConsoleLaunch.consoleScreenshotRefreshedAt must be an ISO date.");
  }
  if (launch.vncHost !== undefined) {
    requireString(launch.vncHost, "latestConsoleLaunch.vncHost");
  }
  if (launch.vncPort !== undefined) {
    requireInteger(launch.vncPort, "latestConsoleLaunch.vncPort");
    if (launch.vncPort < 5900 || launch.vncPort > 5999) {
      throw new TypeError("latestConsoleLaunch.vncPort must be a loopback VNC port.");
    }
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

function validateOptionalPath(value, fieldName) {
  if (value !== undefined && value !== null) {
    requireString(value, fieldName);
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`QEMU install status field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`QEMU install status field '${fieldName}' must be boolean.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`QEMU install status field '${fieldName}' must be an integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected QEMU install status JSON on stdin.");
  }

  validateQEMUInstallStatus(JSON.parse(input));
  process.stdout.write("qemu install status valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
