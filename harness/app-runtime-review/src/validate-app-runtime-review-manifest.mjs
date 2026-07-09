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
  requireNonNegativeInteger(manifest.requiredScreenshotCount, "requiredScreenshotCount");
  requireString(manifest.reviewCommand, "reviewCommand");

  if (!Array.isArray(manifest.screenshotFiles)) {
    throw new TypeError("app runtime review manifest screenshotFiles must be an array.");
  }
  if (manifest.requiredScreenshotCount !== expectedSlotIds.length) {
    throw new TypeError("app runtime review manifest requiredScreenshotCount must match the release card.");
  }
  if (manifest.screenshotFiles.length !== expectedSlotIds.length) {
    throw new TypeError("app runtime review manifest must list every required screenshot file.");
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
  }

  if (!Array.isArray(manifest.nextActions) || manifest.nextActions.length === 0) {
    throw new TypeError("app runtime review manifest nextActions must be a non-empty array.");
  }
  for (const action of manifest.nextActions) {
    requireString(action, "nextActions[]");
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
