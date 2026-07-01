import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const VALID_STATES = new Set(["passed", "warning", "blocked", "ready"]);
const REQUIRED_CHECK_IDS = [
  "vm-profile",
  "installer-media",
  "system-disk",
  "qemu-executable",
  "hvf-plan"
];

export function validateQEMUDoctor(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("QEMU doctor report must be a JSON object.");
  }

  requireString(report.kind, "kind");
  requireString(report.provider, "provider");
  requireString(report.overallState, "overallState");

  if (report.kind !== "qemuWindowsArmReadinessReport") {
    throw new TypeError(`Unsupported QEMU doctor kind: ${report.kind}`);
  }

  if (report.provider !== "QEMU/HVF") {
    throw new TypeError("QEMU doctor provider must be QEMU/HVF.");
  }

  if (report.isServerBacked !== false) {
    throw new TypeError("QEMU doctor report must be local and non-server-backed.");
  }

  if (!VALID_STATES.has(report.overallState)) {
    throw new TypeError(`Unsupported QEMU doctor state: ${report.overallState}`);
  }

  if (!Array.isArray(report.checks) || report.checks.length < REQUIRED_CHECK_IDS.length) {
    throw new TypeError("QEMU doctor report must include all readiness checks.");
  }

  const checkIds = report.checks.map((check) => check.id);
  for (const id of REQUIRED_CHECK_IDS) {
    if (!checkIds.includes(id)) {
      throw new TypeError(`QEMU doctor report must include check: ${id}`);
    }
  }

  for (const check of report.checks) {
    validateCheck(check);
  }

  if (!Array.isArray(report.nextActions) || report.nextActions.length === 0) {
    throw new TypeError("QEMU doctor report must include at least one next action.");
  }

  for (const action of report.nextActions) {
    requireString(action, "nextActions[]");
  }

  const hasBlockedCheck = report.checks.some((check) => check.state === "blocked");
  if (hasBlockedCheck && report.overallState !== "blocked") {
    throw new TypeError("QEMU doctor report must be blocked when any check is blocked.");
  }

  if (!hasBlockedCheck && report.overallState !== "ready") {
    throw new TypeError("QEMU doctor report must be ready when no check is blocked.");
  }

  if (hasBlockedCheck && report.nextActions.every((action) => !action.includes("Install QEMU") && !action.includes("prepare"))) {
    throw new TypeError("Blocked QEMU doctor reports must include actionable recovery guidance.");
  }

  return report;
}

function validateCheck(check) {
  if (!check || typeof check !== "object" || Array.isArray(check)) {
    throw new TypeError("QEMU doctor check must be an object.");
  }

  requireString(check.id, "checks[].id");
  requireString(check.title, "checks[].title");
  requireString(check.state, "checks[].state");
  requireString(check.detail, "checks[].detail");

  if (!VALID_STATES.has(check.state)) {
    throw new TypeError(`Unsupported QEMU doctor check state: ${check.state}`);
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`QEMU doctor field '${fieldName}' must be a non-empty string.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected QEMU doctor JSON on stdin.");
  }

  validateQEMUDoctor(JSON.parse(input));
  process.stdout.write("qemu doctor valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
