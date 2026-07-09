import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { validateAppRuntimeReview } from "./validate-app-runtime-review.mjs";
import { validateAppRuntimeReviewManifest } from "./validate-app-runtime-review-manifest.mjs";

export function validateAppRuntimeReviewVerification(report) {
  if (!report || typeof report !== "object" || Array.isArray(report)) {
    throw new TypeError("app runtime review verification must be an object.");
  }

  requireString(report.kind, "kind");
  if (report.kind !== "windowsAppRuntimeReviewEvidenceVerification") {
    throw new TypeError("app runtime review verification kind must be windowsAppRuntimeReviewEvidenceVerification.");
  }

  requireString(report.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(report.generatedAt))) {
    throw new TypeError("app runtime review verification generatedAt must be an ISO date.");
  }

  requireString(report.evidenceDirectory, "evidenceDirectory");
  requireString(report.manifestPath, "manifestPath");
  requireString(report.readmePath, "readmePath");
  requireBoolean(report.manifestExists, "manifestExists");
  requireBoolean(report.readmeExists, "readmeExists");
  requireNonNegativeInteger(report.requiredScreenshotCount, "requiredScreenshotCount");
  requireNonNegativeInteger(report.attachedScreenshotCount, "attachedScreenshotCount");
  requireBoolean(report.isComplete, "isComplete");

  if (!Array.isArray(report.missingFiles)) {
    throw new TypeError("app runtime review verification missingFiles must be an array.");
  }
  for (const file of report.missingFiles) {
    requireString(file, "missingFiles[]");
    if (!file.startsWith(`${report.evidenceDirectory}/`)) {
      throw new TypeError("app runtime review verification missing files must live inside the evidence directory.");
    }
  }

  const review = validateAppRuntimeReview(report.review);
  if (report.requiredScreenshotCount !== review.requiredScreenshotCount) {
    throw new TypeError("app runtime review verification required count must match review card.");
  }
  if (report.attachedScreenshotCount !== review.attachedScreenshotCount) {
    throw new TypeError("app runtime review verification attached count must match review card.");
  }
  if (report.missingFiles.length !== report.requiredScreenshotCount - report.attachedScreenshotCount) {
    throw new TypeError("app runtime review verification missing file count must match attached count.");
  }
  if (report.isComplete !== (
    report.manifestExists
    && report.readmeExists
    && report.missingFiles.length === 0
    && review.areRequiredScreenshotsAttached
  )) {
    throw new TypeError("app runtime review verification completeness must match evidence state.");
  }

  if (report.manifest !== undefined) {
    const manifest = validateAppRuntimeReviewManifest(report.manifest);
    if (manifest.evidenceDirectory !== report.evidenceDirectory) {
      throw new TypeError("app runtime review verification manifest must point at the evidence directory.");
    }
  }

  if (!Array.isArray(report.nextActions) || report.nextActions.length === 0) {
    throw new TypeError("app runtime review verification nextActions must be a non-empty array.");
  }
  for (const action of report.nextActions) {
    requireString(action, "nextActions[]");
  }

  return report;
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`App runtime review verification field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`App runtime review verification field '${fieldName}' must be boolean.`);
  }
}

function requireNonNegativeInteger(value, fieldName) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`App runtime review verification field '${fieldName}' must be a non-negative integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected app runtime review verification JSON on stdin.");
  }

  validateAppRuntimeReviewVerification(JSON.parse(input));
  process.stdout.write("app runtime review verification valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
