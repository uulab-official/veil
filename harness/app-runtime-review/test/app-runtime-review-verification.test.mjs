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

test("accepts complete verification reports", () => {
  const report = demoVerification();
  report.attachedScreenshotCount = report.requiredScreenshotCount;
  report.isComplete = true;
  report.missingFiles = [];
  report.missingCaptureSteps = [];
  delete report.nextMissingCaptureStep;
  report.review.attachedScreenshotCount = report.review.requiredScreenshotCount;
  report.review.areRequiredScreenshotsAttached = true;
  for (const slot of report.review.screenshotSlots) {
    slot.attachmentState = "attached";
    slot.attachmentPath = `${report.evidenceDirectory}/${slot.expectedFileName}`;
  }

  assert.equal(validateAppRuntimeReviewVerification(report), report);
});
