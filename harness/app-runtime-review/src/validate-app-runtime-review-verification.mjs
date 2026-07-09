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

  if (!Array.isArray(report.missingCaptureSteps)) {
    throw new TypeError("app runtime review verification missingCaptureSteps must be an array.");
  }
  for (const [index, step] of report.missingCaptureSteps.entries()) {
    validateMissingCaptureStep(step, index, report.evidenceDirectory);
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
  if (report.missingCaptureSteps.length !== report.missingFiles.length) {
    throw new TypeError("app runtime review verification missing capture step count must match missing files.");
  }
  for (const [index, step] of report.missingCaptureSteps.entries()) {
    if (step.path !== report.missingFiles[index]) {
      throw new TypeError("app runtime review verification missing capture steps must preserve missing file order.");
    }
  }
  if (report.missingCaptureSteps.length > 0) {
    if (!report.nextMissingCaptureStep) {
      throw new TypeError("app runtime review verification must include the next missing capture step.");
    }
    validateMissingCaptureStep(report.nextMissingCaptureStep, "nextMissingCaptureStep", report.evidenceDirectory);
    const firstStep = report.missingCaptureSteps[0];
    if (
      report.nextMissingCaptureStep.slotId !== firstStep.slotId
      || report.nextMissingCaptureStep.path !== firstStep.path
    ) {
      throw new TypeError("app runtime review verification next missing capture step must match the first missing step.");
    }
  } else if (report.nextMissingCaptureStep !== undefined) {
    throw new TypeError("complete app runtime review verification must not include a next missing capture step.");
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

function validateMissingCaptureStep(step, index, evidenceDirectory) {
  if (!step || typeof step !== "object" || Array.isArray(step)) {
    throw new TypeError(`app runtime review verification missingCaptureSteps.${index} must be an object.`);
  }
  requireNonNegativeInteger(step.order, `missingCaptureSteps.${index}.order`);
  requireString(step.slotId, `missingCaptureSteps.${index}.slotId`);
  requireString(step.title, `missingCaptureSteps.${index}.title`);
  requireString(step.expectedFileName, `missingCaptureSteps.${index}.expectedFileName`);
  requireString(step.path, `missingCaptureSteps.${index}.path`);
  requireString(step.instruction, `missingCaptureSteps.${index}.instruction`);
  if (step.supportingCommand !== undefined) {
    requireString(step.supportingCommand, `missingCaptureSteps.${index}.supportingCommand`);
  }
  if (step.expectedFileName !== `${step.slotId}.png`) {
    throw new TypeError("app runtime review verification missing capture step file names must match slot ids.");
  }
  if (!step.path.endsWith(`/${step.expectedFileName}`)) {
    throw new TypeError("app runtime review verification missing capture step paths must end with expected file names.");
  }
  if (!step.path.startsWith(`${evidenceDirectory}/`)) {
    throw new TypeError("app runtime review verification missing capture step paths must live inside the evidence directory.");
  }
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
