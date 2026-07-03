import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_STATES = new Set(["unsupported", "notConfigured", "stopped", "starting", "running", "suspended", "failed"]);
const VALID_INSTALL_EVIDENCE = new Set(["notConfigured", "setupBlocked", "sparseDisk", "setupReady", "profileFlag", "guestAgent"]);
const VALID_PREVIEW_STATUSES = new Set(["fresh", "stale", "unavailable"]);
const VALID_DISPLAY_SURFACES = new Set(["vncLoopback", "screenshot", "unavailable"]);

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
  validateDisplaySurface(report.displaySurface);
  validateNextActions(report.nextActions);

  if (report.profileName !== undefined) {
    requireString(report.profileName, "profileName");
  }

  if (report.latestConsoleLaunch !== undefined) {
    validateConsoleLaunch(report.latestConsoleLaunch);
  }

  if (report.runningQEMUProcess !== undefined) {
    validateRunningQEMUProcess(report.runningQEMUProcess);
  }

  if (report.state === "running"
    && report.latestConsoleLaunch !== undefined
    && !report.nextActions.some((action) => action.includes("qemu-capture"))) {
    throw new TypeError("running install status reports with launch evidence must include qemu-capture recovery guidance.");
  }

  if (report.state === "running"
    && report.latestConsoleLaunch === undefined
    && report.runningQEMUProcess === undefined) {
    throw new TypeError("running install status reports without launch evidence must include runningQEMUProcess evidence.");
  }

  if (report.state === "running"
    && report.latestConsoleLaunch === undefined
    && !report.nextActions.some((action) => action.includes("existing QEMU") && action.includes("PID"))) {
    throw new TypeError("running install status reports without launch evidence must include existing QEMU recovery guidance.");
  }

  return report;
}

function validateDisplaySurface(surface) {
  if (!surface || typeof surface !== "object" || Array.isArray(surface)) {
    throw new TypeError("displaySurface must be an object.");
  }

  requireString(surface.kind, "displaySurface.kind");
  if (!VALID_DISPLAY_SURFACES.has(surface.kind)) {
    throw new TypeError(`Unsupported display surface kind: ${surface.kind}`);
  }
  requireBoolean(surface.isLiveCapable, "displaySurface.isLiveCapable");
  requireInteger(surface.plannedWidthInPixels, "displaySurface.plannedWidthInPixels");
  requireInteger(surface.plannedHeightInPixels, "displaySurface.plannedHeightInPixels");
  requireString(surface.scalingMode, "displaySurface.scalingMode");
  requireString(surface.dynamicResolution, "displaySurface.dynamicResolution");
  requireString(surface.retinaScaling, "displaySurface.retinaScaling");

  if (surface.plannedWidthInPixels <= 0 || surface.plannedHeightInPixels <= 0) {
    throw new TypeError("displaySurface planned dimensions must be positive.");
  }

  if (surface.kind === "vncLoopback") {
    requireString(surface.endpoint, "displaySurface.endpoint");
    if (!/^127\.0\.0\.1:\d+$/.test(surface.endpoint)) {
      throw new TypeError("displaySurface.endpoint must be a loopback VNC endpoint.");
    }
    if (surface.isLiveCapable !== true) {
      throw new TypeError("vncLoopback display surfaces must be live capable.");
    }
    if (typeof surface.validationCommand !== "string" || !surface.validationCommand.includes("qemu-display-smoke")) {
      throw new TypeError("vncLoopback display surfaces must include qemu-display-smoke validation guidance.");
    }
  }

  if (surface.kind === "screenshot") {
    validateOptionalPath(surface.screenshotPath, "displaySurface.screenshotPath");
    if (surface.screenshotPath && !surface.screenshotPath.endsWith(".png")) {
      throw new TypeError("displaySurface.screenshotPath must point to a .png image.");
    }
  }

  if (surface.kind === "unavailable" && surface.isLiveCapable !== false) {
    throw new TypeError("unavailable display surfaces cannot be live capable.");
  }

  validateOptionalPath(surface.screenshotPath, "displaySurface.screenshotPath");
  if (surface.endpoint !== undefined && surface.kind !== "vncLoopback") {
    requireString(surface.endpoint, "displaySurface.endpoint");
  }
  if (surface.validationCommand !== undefined && surface.kind !== "vncLoopback") {
    requireString(surface.validationCommand, "displaySurface.validationCommand");
  }
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

function validateRunningQEMUProcess(process) {
  if (!process || typeof process !== "object" || Array.isArray(process)) {
    throw new TypeError("runningQEMUProcess must be an object.");
  }

  requireInteger(process.pid, "runningQEMUProcess.pid");
  if (process.pid <= 0) {
    throw new TypeError("runningQEMUProcess.pid must be positive.");
  }
  requireString(process.commandLine, "runningQEMUProcess.commandLine");
  if (!process.commandLine.includes("qemu-system-aarch64")) {
    throw new TypeError("runningQEMUProcess.commandLine must identify qemu-system-aarch64.");
  }
  if (process.monitorSocketPath !== undefined) {
    requireString(process.monitorSocketPath, "runningQEMUProcess.monitorSocketPath");
  }
  if (process.qmpSocketPath !== undefined) {
    requireString(process.qmpSocketPath, "runningQEMUProcess.qmpSocketPath");
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
