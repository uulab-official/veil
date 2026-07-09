import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeReviewVerification } from "../src/validate-app-runtime-review-verification.mjs";

function demoVerification() {
  return JSON.parse(readFileSync(new URL("../fixtures/app-runtime-review-verification.demo.json", import.meta.url), "utf8"));
}

test("validates app runtime review verification fixture", () => {
  const report = demoVerification();

  assert.equal(validateAppRuntimeReviewVerification(report), report);
});

test("rejects verification reports whose attached count drifts from review card", () => {
  const report = demoVerification();
  report.attachedScreenshotCount = 99;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /attached count/
  );
});

test("rejects verification missing files outside evidence directory", () => {
  const report = demoVerification();
  report.missingFiles[0] = "/tmp/other/preBootLauncher.png";

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /evidence directory/
  );
});

test("rejects invalid screenshot files outside evidence directory", () => {
  const report = demoVerification();
  report.invalidScreenshotFiles = [{
    path: "/tmp/other/preBootLauncher.png",
    reason: "notValidPNG",
    byteCount: 12,
    minimumWidth: report.minimumScreenshotWidth,
    minimumHeight: report.minimumScreenshotHeight
  }];

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /evidence directory/
  );
});

test("rejects invalid screenshot files with drifted minimum dimensions", () => {
  const report = demoVerification();
  report.invalidScreenshotFiles = [{
    path: report.missingFiles[0],
    reason: "belowMinimumDimensions",
    byteCount: 68,
    width: 1,
    height: 1,
    minimumWidth: 1,
    minimumHeight: report.minimumScreenshotHeight
  }];

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /minimum dimensions/
  );
});

test("rejects verification missing capture steps that drift from missing files", () => {
  const report = demoVerification();
  report.missingFiles[0] = report.missingFiles[1];

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /missing capture steps/
  );
});

test("rejects verification reports without a next missing capture step", () => {
  const report = demoVerification();
  delete report.nextMissingCaptureStep;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /next missing capture step/
  );
});

test("rejects verification missing capture commands that do not save the missing file", () => {
  const report = demoVerification();
  report.missingCaptureSteps[0].captureCommand = "screencapture -i /tmp/other/preBootLauncher.png";

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /capture commands/
  );
});

test("rejects verification commands that drift from manifest commands", () => {
  const report = demoVerification();
  report.verifyCommand = "veil-vmctl app-runtime-review-verify --json --evidence-dir /tmp/other";

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /verifyCommand/
  );
});

test("rejects verification minimum screenshot dimensions that drift from manifest", () => {
  const report = demoVerification();
  report.minimumScreenshotHeight = 1;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /minimum screenshot dimensions/
  );
});

test("accepts complete verification reports", () => {
  const report = demoVerification();
  report.attachedScreenshotCount = report.requiredScreenshotCount;
  report.isComplete = true;
  report.missingFiles = [];
  report.invalidScreenshotFiles = [];
  report.missingCaptureSteps = [];
  delete report.nextMissingCaptureStep;
  report.review.attachedScreenshotCount = report.review.requiredScreenshotCount;
  report.review.invalidScreenshotCount = 0;
  report.review.areRequiredScreenshotsAttached = true;
  report.review.isReadyForReview = true;
  report.review.appFlowSummary = "ready (5/5)";
  report.review.nextStepTitle = "Ready For App Review";
  delete report.review.nextActionCommand;
  report.review.detail = "Setup, launch, app checks, and close controls are covered.";
  for (const slot of report.review.screenshotSlots) {
    slot.attachmentState = "attached";
    slot.attachmentPath = `${report.evidenceDirectory}/${slot.expectedFileName}`;
    slot.attachmentByteCount = 68;
    slot.attachmentWidth = 1440;
    slot.attachmentHeight = 900;
  }

  assert.equal(validateAppRuntimeReviewVerification(report), report);
});
