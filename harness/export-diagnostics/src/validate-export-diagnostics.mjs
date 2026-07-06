import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const CONFIGURATION_SECTIONS = ["system", "display", "sharing", "storage", "network", "input", "guestAgent"];
const BOOKMARK_FIELDS = ["installerMediaBookmarkData", "driverMediaBookmarkData", "virtualDiskBookmarkData"];

export function validateExportDiagnostics(bundle) {
  if (!bundle || typeof bundle !== "object" || Array.isArray(bundle)) {
    throw new TypeError("Diagnostics bundle must be a JSON object.");
  }

  requireString(bundle.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(bundle.generatedAt))) {
    throw new TypeError("generatedAt must be an ISO date.");
  }

  validateHost(bundle.host);
  validateSnapshot(bundle.snapshot);

  if (bundle.profile !== null && bundle.profile !== undefined) {
    validateProfile(bundle.profile, "profile");
  }

  if (bundle.lastBootReport !== null && bundle.lastBootReport !== undefined) {
    validateBootReport(bundle.lastBootReport);
  }

  return bundle;
}

function validateHost(host) {
  if (!host || typeof host !== "object" || Array.isArray(host)) {
    throw new TypeError("host must be an object.");
  }

  requireString(host.architecture, "host.architecture");
  requireString(host.operatingSystemVersion, "host.operatingSystemVersion");
  requireInteger(host.processorCount, "host.processorCount");
  if (host.processorCount < 1) {
    throw new TypeError("host.processorCount must be positive.");
  }
  requireInteger(host.physicalMemoryBytes, "host.physicalMemoryBytes");
  if (host.physicalMemoryBytes < 1) {
    throw new TypeError("host.physicalMemoryBytes must be positive.");
  }
}

function validateSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    throw new TypeError("snapshot must be an object.");
  }

  requireString(snapshot.state, "snapshot.state");
  requireInteger(snapshot.cpuCount, "snapshot.cpuCount");
  requireInteger(snapshot.memoryMB, "snapshot.memoryMB");
  requireInteger(snapshot.diskGB, "snapshot.diskGB");

  if (!Array.isArray(snapshot.preflightChecks)) {
    throw new TypeError("snapshot.preflightChecks must be an array.");
  }
  for (const check of snapshot.preflightChecks) {
    requireString(check.id, "snapshot.preflightChecks[].id");
    requireString(check.title, "snapshot.preflightChecks[].title");
    requireString(check.detail, "snapshot.preflightChecks[].detail");
    if (!["passed", "failed"].includes(check.state)) {
      throw new TypeError(`Unsupported preflight check state: ${check.state}`);
    }
  }

  validateConfigurationSummary(snapshot.configurationSummary);
  validateDeviceSummary(snapshot.deviceSummary);
}

function validateConfigurationSummary(summary) {
  if (!summary || typeof summary !== "object" || Array.isArray(summary)) {
    throw new TypeError("snapshot.configurationSummary must be an object.");
  }

  for (const section of CONFIGURATION_SECTIONS) {
    if (!(section in summary)) {
      throw new TypeError(`snapshot.configurationSummary is missing the '${section}' typed section.`);
    }
  }
}

function validateDeviceSummary(deviceSummary) {
  if (!deviceSummary || typeof deviceSummary !== "object" || Array.isArray(deviceSummary)) {
    throw new TypeError("snapshot.deviceSummary must be an object.");
  }

  requireString(deviceSummary.bootLoader, "snapshot.deviceSummary.bootLoader");
  requireString(deviceSummary.networkMode, "snapshot.deviceSummary.networkMode");
  if (!Array.isArray(deviceSummary.storageDevices)) {
    throw new TypeError("snapshot.deviceSummary.storageDevices must be an array.");
  }
  for (const device of deviceSummary.storageDevices) {
    requireString(device.role, "snapshot.deviceSummary.storageDevices[].role");
    requireString(device.attachment, "snapshot.deviceSummary.storageDevices[].attachment");
    requireBoolean(device.readOnly, "snapshot.deviceSummary.storageDevices[].readOnly");
  }
}

function validateProfile(profile, fieldPrefix) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) {
    throw new TypeError(`${fieldPrefix} must be an object.`);
  }

  requireString(profile.id, `${fieldPrefix}.id`);
  requireString(profile.name, `${fieldPrefix}.name`);
  requireString(profile.os, `${fieldPrefix}.os`);
  requireInteger(profile.cpuCount, `${fieldPrefix}.cpuCount`);
  requireInteger(profile.memoryMB, `${fieldPrefix}.memoryMB`);
  requireInteger(profile.diskGB, `${fieldPrefix}.diskGB`);

  for (const bookmarkField of BOOKMARK_FIELDS) {
    if (bookmarkField in profile) {
      throw new TypeError(
        `${fieldPrefix} must be metadata-only and must not include '${bookmarkField}' (security-scoped bookmark bytes).`
      );
    }
  }
}

function validateBootReport(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("lastBootReport must be an object.");
  }

  requireString(report.startedAt, "lastBootReport.startedAt");
  requireString(report.completedAt, "lastBootReport.completedAt");
  if (!["succeeded", "failed"].includes(report.result)) {
    throw new TypeError(`Unsupported lastBootReport.result: ${report.result}`);
  }
  requireString(report.resultingState, "lastBootReport.resultingState");
  validateProfile(report.profile, "lastBootReport.profile");
  validateDeviceSummary(report.deviceSummary);
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`Diagnostics field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`Diagnostics field '${fieldName}' must be boolean.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`Diagnostics field '${fieldName}' must be an integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected diagnostics bundle JSON on stdin.");
  }

  validateExportDiagnostics(JSON.parse(input));
  process.stdout.write("export diagnostics valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
