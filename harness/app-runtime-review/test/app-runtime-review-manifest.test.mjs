import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeReviewManifest } from "../src/validate-app-runtime-review-manifest.mjs";

function demoManifest() {
  return JSON.parse(readFileSync(new URL("../fixtures/app-runtime-review-manifest.demo.json", import.meta.url), "utf8"));
}

test("validates app runtime review manifest fixture", () => {
  const manifest = demoManifest();

  assert.equal(validateAppRuntimeReviewManifest(manifest), manifest);
});

test("rejects manifests with missing screenshot files", () => {
  const manifest = demoManifest();
  manifest.screenshotFiles.pop();

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /every required screenshot/
  );
});

test("rejects manifests with drifted minimum screenshot dimensions", () => {
  const manifest = demoManifest();
  manifest.minimumScreenshotWidth = 1;

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /minimum screenshot dimensions/
  );
});

test("rejects manifests with missing capture steps", () => {
  const manifest = demoManifest();
  manifest.captureSteps.pop();

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /every capture step/
  );
});

test("rejects manifests with drifted screenshot file names", () => {
  const manifest = demoManifest();
  manifest.screenshotFiles[0].expectedFileName = "wrong.png";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /file names/
  );
});

test("rejects manifests with drifted capture step order", () => {
  const manifest = demoManifest();
  manifest.captureSteps[0].order = 2;

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /order/
  );
});

test("rejects manifests with capture commands that do not save the expected file", () => {
  const manifest = demoManifest();
  manifest.captureSteps[0].captureCommand = "screencapture -i /tmp/other/preBootLauncher.png";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /capture commands/
  );
});

test("rejects manifests with open commands outside evidence directory", () => {
  const manifest = demoManifest();
  manifest.openEvidenceDirectoryCommand = "open /tmp/other";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /openEvidenceDirectoryCommand/
  );
});

test("rejects review commands that do not point at evidence directory", () => {
  const manifest = demoManifest();
  manifest.reviewCommand = "veil-vmctl app-runtime-review --evidence-dir '/tmp/other'";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /reviewCommand/
  );
});

test("rejects screenshot paths outside evidence directory", () => {
  const manifest = demoManifest();
  manifest.screenshotFiles[0].path = "/tmp/other/preBootLauncher.png";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /evidence directory/
  );
});

test("rejects readme paths outside evidence directory", () => {
  const manifest = demoManifest();
  manifest.readmePath = "/tmp/other/README.md";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /readmePath/
  );
});

test("rejects next actions without minimum screenshot size", () => {
  const manifest = demoManifest();
  manifest.nextActions = manifest.nextActions.map((action) => action.replace(" of at least 640 x 360", ""));

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /minimum screenshot size/
  );
});

test("rejects next actions without supplemental notification proof guidance", () => {
  const manifest = demoManifest();
  manifest.nextActions = manifest.nextActions.filter((action) => !action.includes("notification-proof"));

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /notification proof/
  );
});

test("rejects next actions without supplemental printer proof guidance", () => {
  const manifest = demoManifest();
  manifest.nextActions = manifest.nextActions.filter((action) => !action.includes("printer-bridge-proof"));

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /printer proof/
  );
});

test("rejects app check proof commands that do not save to the evidence file", () => {
  const manifest = demoManifest();
  manifest.appCheckProofFile.command = "veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved";

  assert.throws(
    () => validateAppRuntimeReviewManifest(manifest),
    /proof file path/
  );
});
