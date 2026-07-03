import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export function validateQEMUDisplaySmoke(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("QEMU display smoke report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  requireString(report.endpoint, "endpoint");
  requireInteger(report.width, "width");
  requireInteger(report.height, "height");
  requireInteger(report.frameSequence, "frameSequence");
  requireInteger(report.pixelByteCount, "pixelByteCount");
  requireInteger(report.waitedSeconds, "waitedSeconds");
  requireString(report.capturedAt, "capturedAt");

  if (report.kind !== "qemuDisplaySmoke") {
    throw new TypeError(`Unsupported QEMU display smoke kind: ${report.kind}`);
  }

  if (!/^127\.0\.0\.1:\d+$/.test(report.endpoint)) {
    throw new TypeError("QEMU display smoke endpoint must be a loopback VNC endpoint.");
  }

  if (report.width <= 0 || report.height <= 0) {
    throw new TypeError("QEMU display smoke dimensions must be positive.");
  }

  if (report.frameSequence < 1) {
    throw new TypeError("QEMU display smoke frameSequence must start at 1.");
  }

  if (report.pixelByteCount !== report.width * report.height * 4) {
    throw new TypeError("QEMU display smoke pixelByteCount must match RGBA dimensions.");
  }

  if (report.waitedSeconds < 1 || report.waitedSeconds > 30) {
    throw new TypeError("QEMU display smoke waitedSeconds must be between 1 and 30.");
  }

  if (Number.isNaN(Date.parse(report.capturedAt))) {
    throw new TypeError("QEMU display smoke capturedAt must be an ISO date.");
  }

  if (report.pid !== null && report.pid !== undefined) {
    requireInteger(report.pid, "pid");
  }

  return report;
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`QEMU display smoke field '${fieldName}' must be a non-empty string.`);
  }
}

function requireInteger(value, fieldName) {
  if (!Number.isInteger(value)) {
    throw new TypeError(`QEMU display smoke field '${fieldName}' must be an integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected QEMU display smoke JSON on stdin.");
  }

  validateQEMUDisplaySmoke(JSON.parse(input));
  process.stdout.write("qemu display smoke valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
