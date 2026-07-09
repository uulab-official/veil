import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const expectedSlotIds = [
  "preBootLauncher",
  "firstAppLaunch",
  "appWindowOnly",
  "menuRestore",
  "closeQuiet"
];

export function validateAppRuntimeReviewManifest(manifest) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new TypeError("app runtime review manifest must be an object.");
  }

  requireString(manifest.kind, "kind");
  if (manifest.kind !== "windowsAppRuntimeReviewEvidenceManifest") {
    throw new TypeError("app runtime review manifest kind must be windowsAppRuntimeReviewEvidenceManifest.");
  }

  requireString(manifest.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(manifest.generatedAt))) {
    throw new TypeError("app runtime review manifest generatedAt must be an ISO date.");
  }
  requireString(manifest.evidenceDirectory, "evidenceDirectory");
  requireString(manifest.manifestPath, "manifestPath");
  requireString(manifest.readmePath, "readmePath");
  requireNonNegativeInteger(manifest.requiredScreenshotCount, "requiredScreenshotCount");
  requireString(manifest.reviewCommand, "reviewCommand");

  if (!manifest.manifestPath.endsWith("/review-manifest.json")) {
    throw new TypeError("app runtime review manifest path must end with review-manifest.json.");
  }
  if (!manifest.manifestPath.startsWith(`${manifest.evidenceDirectory}/`)) {
    throw new TypeError("app runtime review manifest path must live inside the evidence directory.");
  }
  if (!manifest.readmePath.endsWith("/README.md")) {
    throw new TypeError("app runtime review manifest readmePath must end with README.md.");
  }
  if (!manifest.readmePath.startsWith(`${manifest.evidenceDirectory}/`)) {
    throw new TypeError("app runtime review manifest readmePath must live inside the evidence directory.");
  }
  if (!manifest.reviewCommand.includes("app-runtime-review --evidence-dir")) {
    throw new TypeError("app runtime review manifest reviewCommand must run app-runtime-review with an evidence directory.");
  }
  if (!manifest.reviewCommand.includes(manifest.evidenceDirectory)) {
    throw new TypeError("app runtime review manifest reviewCommand must point at the evidence directory.");
  }

  if (!Array.isArray(manifest.screenshotFiles)) {
    throw new TypeError("app runtime review manifest screenshotFiles must be an array.");
  }
  if (!Array.isArray(manifest.captureSteps)) {
    throw new TypeError("app runtime review manifest captureSteps must be an array.");
  }
  if (manifest.requiredScreenshotCount !== expectedSlotIds.length) {
    throw new TypeError("app runtime review manifest requiredScreenshotCount must match the release card.");
  }
  if (manifest.screenshotFiles.length !== expectedSlotIds.length) {
    throw new TypeError("app runtime review manifest must list every required screenshot file.");
  }
  if (manifest.captureSteps.length !== expectedSlotIds.length) {
    throw new TypeError("app runtime review manifest must list every capture step.");
  }

  for (const [index, file] of manifest.screenshotFiles.entries()) {
    if (!file || typeof file !== "object" || Array.isArray(file)) {
      throw new TypeError("app runtime review manifest screenshot files must be objects.");
    }
    requireString(file.slotId, `screenshotFiles.${index}.slotId`);
    requireString(file.title, `screenshotFiles.${index}.title`);
    requireString(file.expectedFileName, `screenshotFiles.${index}.expectedFileName`);
    requireString(file.path, `screenshotFiles.${index}.path`);
    requireString(file.expectedSurface, `screenshotFiles.${index}.expectedSurface`);

    if (file.slotId !== expectedSlotIds[index]) {
      throw new TypeError("app runtime review manifest screenshot files must preserve release card order.");
    }
    if (file.expectedFileName !== `${file.slotId}.png`) {
      throw new TypeError("app runtime review manifest screenshot file names must match slot ids.");
    }
    if (!file.path.endsWith(`/${file.expectedFileName}`)) {
      throw new TypeError("app runtime review manifest screenshot paths must end with expected file names.");
    }
    if (!file.path.startsWith(`${manifest.evidenceDirectory}/`)) {
      throw new TypeError("app runtime review manifest screenshot paths must live inside the evidence directory.");
    }
  }

  for (const [index, step] of manifest.captureSteps.entries()) {
    if (!step || typeof step !== "object" || Array.isArray(step)) {
      throw new TypeError("app runtime review manifest capture steps must be objects.");
    }
    requireNonNegativeInteger(step.order, `captureSteps.${index}.order`);
    requireString(step.slotId, `captureSteps.${index}.slotId`);
    requireString(step.title, `captureSteps.${index}.title`);
    requireString(step.expectedFileName, `captureSteps.${index}.expectedFileName`);
    requireString(step.instruction, `captureSteps.${index}.instruction`);
    requireString(step.captureCommand, `captureSteps.${index}.captureCommand`);
    if (step.supportingCommand !== undefined) {
      requireString(step.supportingCommand, `captureSteps.${index}.supportingCommand`);
    }

    const file = manifest.screenshotFiles[index];
    if (step.order !== index + 1) {
      throw new TypeError("app runtime review manifest capture step order must be one-based and sequential.");
    }
    if (step.slotId !== file.slotId || step.expectedFileName !== file.expectedFileName) {
      throw new TypeError("app runtime review manifest capture steps must match screenshot files.");
    }
    if (!step.captureCommand.includes("screencapture -i")) {
      throw new TypeError("app runtime review manifest capture steps must use interactive macOS screenshot capture.");
    }
    if (!step.captureCommand.includes(file.path)) {
      throw new TypeError("app runtime review manifest capture commands must save to the expected screenshot path.");
    }
  }

  if (!Array.isArray(manifest.nextActions) || manifest.nextActions.length === 0) {
    throw new TypeError("app runtime review manifest nextActions must be a non-empty array.");
  }
  for (const action of manifest.nextActions) {
    requireString(action, "nextActions[]");
  }
  if (!manifest.nextActions.some((action) => action.includes(manifest.evidenceDirectory))) {
    throw new TypeError("app runtime review manifest next actions must reference the evidence directory.");
  }
  if (!manifest.nextActions.some((action) => action.includes("5/5 attached"))) {
    throw new TypeError("app runtime review manifest next actions must include the 5/5 attached gate.");
  }

  return manifest;
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`App runtime review manifest field '${fieldName}' must be a non-empty string.`);
  }
}

function requireNonNegativeInteger(value, fieldName) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`App runtime review manifest field '${fieldName}' must be a non-negative integer.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected app runtime review manifest JSON on stdin.");
  }

  validateAppRuntimeReviewManifest(JSON.parse(input));
  process.stdout.write("app runtime review manifest valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
