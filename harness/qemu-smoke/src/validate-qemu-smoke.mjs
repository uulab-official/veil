import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_OUTCOMES = new Set([
  "windowsBootStarted",
  "uefiShell",
  "bootImageTimeout",
  "argumentFailure",
  "runningNoDecision",
  "exitedEarly"
]);

export function validateQEMUSmoke(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("QEMU smoke report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  requireString(report.provider, "provider");
  requireString(report.outcome, "outcome");
  requireString(report.detail, "detail");
  requireString(report.serialLogPath, "serialLogPath");
  requireString(report.processLogPath, "processLogPath");
  requireString(report.consoleScreenshotPath, "consoleScreenshotPath");

  if (report.kind !== "qemuWindowsArmBootSmokeReport") {
    throw new TypeError(`Unsupported QEMU smoke kind: ${report.kind}`);
  }

  if (report.provider !== "QEMU/HVF") {
    throw new TypeError("QEMU smoke provider must be QEMU/HVF.");
  }

  if (!VALID_OUTCOMES.has(report.outcome)) {
    throw new TypeError(`Unsupported QEMU smoke outcome: ${report.outcome}`);
  }

  if (!Number.isInteger(report.durationSeconds) || report.durationSeconds < 5 || report.durationSeconds > 120) {
    throw new TypeError("QEMU smoke durationSeconds must be an integer between 5 and 120.");
  }

  if (!Array.isArray(report.evidence) || report.evidence.length === 0) {
    throw new TypeError("QEMU smoke report must include evidence.");
  }

  for (const evidence of report.evidence) {
    requireString(evidence, "evidence[]");
  }

  if (report.outcome === "uefiShell" && !report.evidence.includes("uefi-shell")) {
    throw new TypeError("QEMU smoke uefiShell reports must include uefi-shell evidence.");
  }

  if (report.outcome === "argumentFailure" && !report.evidence.includes("qemu-argument-error")) {
    throw new TypeError("QEMU smoke argumentFailure reports must include qemu-argument-error evidence.");
  }

  if (!report.consoleScreenshotPath.endsWith(".ppm")) {
    throw new TypeError("QEMU smoke consoleScreenshotPath must point to a .ppm image.");
  }

  return report;
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`QEMU smoke field '${fieldName}' must be a non-empty string.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected QEMU smoke JSON on stdin.");
  }

  validateQEMUSmoke(JSON.parse(input));
  process.stdout.write("qemu smoke valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
