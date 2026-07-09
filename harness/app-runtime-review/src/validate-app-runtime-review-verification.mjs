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
  requirePositiveInteger(report.minimumScreenshotWidth, "minimumScreenshotWidth");
  requirePositiveInteger(report.minimumScreenshotHeight, "minimumScreenshotHeight");
  requireBoolean(report.isComplete, "isComplete");
  requireString(report.reviewCommand, "reviewCommand");
  requireString(report.verifyCommand, "verifyCommand");
  requireString(report.openEvidenceDirectoryCommand, "openEvidenceDirectoryCommand");

  if (!report.reviewCommand.includes("app-runtime-review --evidence-dir")) {
    throw new TypeError("app runtime review verification reviewCommand must run app-runtime-review with an evidence directory.");
  }
  if (!report.reviewCommand.includes(report.evidenceDirectory)) {
    throw new TypeError("app runtime review verification reviewCommand must point at the evidence directory.");
  }
  if (!report.verifyCommand.includes("app-runtime-review-verify --json --evidence-dir")) {
    throw new TypeError("app runtime review verification verifyCommand must run app-runtime-review-verify with JSON output and an evidence directory.");
  }
  if (!report.verifyCommand.includes(report.evidenceDirectory)) {
    throw new TypeError("app runtime review verification verifyCommand must point at the evidence directory.");
  }
  if (!report.openEvidenceDirectoryCommand.startsWith("open ")) {
    throw new TypeError("app runtime review verification openEvidenceDirectoryCommand must open the evidence directory.");
  }
  if (!report.openEvidenceDirectoryCommand.includes(report.evidenceDirectory)) {
    throw new TypeError("app runtime review verification openEvidenceDirectoryCommand must point at the evidence directory.");
  }

  if (!Array.isArray(report.missingFiles)) {
    throw new TypeError("app runtime review verification missingFiles must be an array.");
  }
  for (const file of report.missingFiles) {
    requireString(file, "missingFiles[]");
    if (!file.startsWith(`${report.evidenceDirectory}/`)) {
      throw new TypeError("app runtime review verification missing files must live inside the evidence directory.");
    }
  }
  if (!Array.isArray(report.invalidScreenshotFiles)) {
    throw new TypeError("app runtime review verification invalidScreenshotFiles must be an array.");
  }
  for (const [index, file] of report.invalidScreenshotFiles.entries()) {
    validateInvalidScreenshotFile(file, index, report);
  }
  if (!Array.isArray(report.invalidCaptureSteps)) {
    throw new TypeError("app runtime review verification invalidCaptureSteps must be an array.");
  }
  for (const [index, step] of report.invalidCaptureSteps.entries()) {
    validateMissingCaptureStep(step, `invalidCaptureSteps.${index}`, report.evidenceDirectory);
  }

  if (!Array.isArray(report.missingCaptureSteps)) {
    throw new TypeError("app runtime review verification missingCaptureSteps must be an array.");
  }
  for (const [index, step] of report.missingCaptureSteps.entries()) {
    validateMissingCaptureStep(step, `missingCaptureSteps.${index}`, report.evidenceDirectory);
  }

  const review = validateAppRuntimeReview(report.review);
  if (report.requiredScreenshotCount !== review.requiredScreenshotCount) {
    throw new TypeError("app runtime review verification required count must match review card.");
  }
  if (report.attachedScreenshotCount !== review.attachedScreenshotCount) {
    throw new TypeError("app runtime review verification attached count must match review card.");
  }
  if (report.invalidScreenshotFiles.length !== review.invalidScreenshotCount) {
    throw new TypeError("app runtime review verification invalid screenshot count must match review card.");
  }
  if (
    report.minimumScreenshotWidth !== review.minimumScreenshotWidth
    || report.minimumScreenshotHeight !== review.minimumScreenshotHeight
  ) {
    throw new TypeError("app runtime review verification minimum screenshot dimensions must match the review card.");
  }
  if (report.missingFiles.length !== report.requiredScreenshotCount - report.attachedScreenshotCount) {
    throw new TypeError("app runtime review verification missing file count must match attached count.");
  }
  if (report.missingCaptureSteps.length !== report.missingFiles.length) {
    throw new TypeError("app runtime review verification missing capture step count must match missing files.");
  }
  if (!report.invalidScreenshotFiles.every((file) => report.missingFiles.includes(file.path))) {
    throw new TypeError("app runtime review verification invalid screenshot files must also be listed as missing files.");
  }
  if (report.invalidCaptureSteps.length !== report.invalidScreenshotFiles.length) {
    throw new TypeError("app runtime review verification invalid capture step count must match invalid screenshots.");
  }
  for (const [index, step] of report.invalidCaptureSteps.entries()) {
    if (step.path !== report.invalidScreenshotFiles[index].path) {
      throw new TypeError("app runtime review verification invalid capture steps must preserve invalid screenshot order.");
    }
  }
  if (report.invalidCaptureSteps.length > 0) {
    if (!report.nextInvalidCaptureStep) {
      throw new TypeError("app runtime review verification must include the next invalid capture step.");
    }
    validateMissingCaptureStep(report.nextInvalidCaptureStep, "nextInvalidCaptureStep", report.evidenceDirectory);
    const firstInvalidStep = report.invalidCaptureSteps[0];
    if (
      report.nextInvalidCaptureStep.slotId !== firstInvalidStep.slotId
      || report.nextInvalidCaptureStep.path !== firstInvalidStep.path
    ) {
      throw new TypeError("app runtime review verification next invalid capture step must match the first invalid step.");
    }
  } else if (report.nextInvalidCaptureStep !== undefined) {
    throw new TypeError("verification without invalid screenshots must not include a next invalid capture step.");
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
    if (
      manifest.reviewCommand !== report.reviewCommand
      || manifest.verifyCommand !== report.verifyCommand
      || manifest.openEvidenceDirectoryCommand !== report.openEvidenceDirectoryCommand
    ) {
      throw new TypeError("app runtime review verification commands must match the manifest commands.");
    }
    if (
      manifest.minimumScreenshotWidth !== report.minimumScreenshotWidth
      || manifest.minimumScreenshotHeight !== report.minimumScreenshotHeight
    ) {
      throw new TypeError("app runtime review verification minimum screenshot dimensions must match the manifest.");
    }
  }

  if (!Array.isArray(report.nextActions) || report.nextActions.length === 0) {
    throw new TypeError("app runtime review verification nextActions must be a non-empty array.");
  }
  for (const action of report.nextActions) {
    requireString(action, "nextActions[]");
  }
  if (!report.nextActions.some((action) => action.includes(report.openEvidenceDirectoryCommand))) {
    throw new TypeError("app runtime review verification next actions must include the open evidence folder command.");
  }

  return report;
}

function validateInvalidScreenshotFile(file, index, report) {
  if (!file || typeof file !== "object" || Array.isArray(file)) {
    throw new TypeError(`app runtime review verification invalidScreenshotFiles.${index} must be an object.`);
  }
  requireString(file.path, `invalidScreenshotFiles.${index}.path`);
  requireString(file.reason, `invalidScreenshotFiles.${index}.reason`);
  requirePositiveInteger(file.minimumWidth, `invalidScreenshotFiles.${index}.minimumWidth`);
  requirePositiveInteger(file.minimumHeight, `invalidScreenshotFiles.${index}.minimumHeight`);
  if (file.byteCount !== undefined) {
    requirePositiveInteger(file.byteCount, `invalidScreenshotFiles.${index}.byteCount`);
  }
  if (file.width !== undefined) {
    requirePositiveInteger(file.width, `invalidScreenshotFiles.${index}.width`);
  }
  if (file.height !== undefined) {
    requirePositiveInteger(file.height, `invalidScreenshotFiles.${index}.height`);
  }
  if (!["unreadableFile", "notValidPNG", "belowMinimumDimensions"].includes(file.reason)) {
    throw new TypeError("app runtime review verification invalid screenshot reason is unsupported.");
  }
  if (!file.path.startsWith(`${report.evidenceDirectory}/`)) {
    throw new TypeError("app runtime review verification invalid screenshot files must live inside the evidence directory.");
  }
  if (file.minimumWidth !== report.minimumScreenshotWidth || file.minimumHeight !== report.minimumScreenshotHeight) {
    throw new TypeError("app runtime review verification invalid screenshot minimum dimensions must match the report.");
  }
  if (file.reason === "belowMinimumDimensions" && (file.width === undefined || file.height === undefined)) {
    throw new TypeError("app runtime review verification below-minimum screenshots must include dimensions.");
  }
}

function validateMissingCaptureStep(step, index, evidenceDirectory) {
  if (!step || typeof step !== "object" || Array.isArray(step)) {
    throw new TypeError(`app runtime review verification ${index} must be an object.`);
  }
  requireNonNegativeInteger(step.order, `${index}.order`);
  requireString(step.slotId, `${index}.slotId`);
  requireString(step.title, `${index}.title`);
  requireString(step.expectedFileName, `${index}.expectedFileName`);
  requireString(step.path, `${index}.path`);
  requireString(step.instruction, `${index}.instruction`);
  requireString(step.captureCommand, `${index}.captureCommand`);
  if (step.supportingCommand !== undefined) {
    requireString(step.supportingCommand, `${index}.supportingCommand`);
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
  if (!step.captureCommand.includes("screencapture -i")) {
    throw new TypeError("app runtime review verification missing capture steps must use interactive macOS screenshot capture.");
  }
  if (!step.captureCommand.includes(step.path)) {
    throw new TypeError("app runtime review verification missing capture commands must save to the missing file path.");
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

function requirePositiveInteger(value, fieldName) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new TypeError(`App runtime review verification field '${fieldName}' must be a positive integer.`);
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
