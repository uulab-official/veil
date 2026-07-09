import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeReviewVerification } from "../src/validate-app-runtime-review-verification.mjs";

function demoVerification() {
  return JSON.parse(readFileSync(new URL("../fixtures/app-runtime-review-verification.demo.json", import.meta.url), "utf8"));
}

function markInvalidScreenshot(report, slotIndex = 0, reason = "notValidPNG") {
  const slot = report.review.screenshotSlots[slotIndex];
  const invalidFile = {
    path: `${report.evidenceDirectory}/${slot.expectedFileName}`,
    reason,
    byteCount: 12,
    minimumWidth: report.minimumScreenshotWidth,
    minimumHeight: report.minimumScreenshotHeight
  };

  report.invalidScreenshotFiles = [invalidFile];
  report.review.invalidScreenshotCount = 1;
  report.review.nextStepTitle = "Replace Review Screenshots";
  slot.attachmentIssueReason = reason;
  slot.invalidAttachmentPath = invalidFile.path;
  slot.invalidAttachmentByteCount = invalidFile.byteCount;
  report.screenshotEvidenceSummary.state = "needs-replacement";
  report.screenshotEvidenceSummary.missingScreenshotCount = report.missingFiles.length - 1;
  report.screenshotEvidenceSummary.invalidScreenshotCount = 1;
  report.screenshotEvidenceSummary.nextStepKind = "replaceInvalidScreenshot";
  report.screenshotEvidenceSummary.nextStepTitle = `Replace ${slot.expectedFileName}`;
  report.screenshotEvidenceSummary.nextExpectedFileName = slot.expectedFileName;
  report.screenshotEvidenceSummary.nextCaptureCommand = report.missingCaptureSteps[slotIndex].captureCommand;
  report.nextEvidenceAction = {
    kind: "replaceInvalidScreenshot",
    title: `Replace ${slot.expectedFileName}`,
    command: report.missingCaptureSteps[slotIndex].captureCommand,
    isReadyToShare: false,
    expectedFileName: slot.expectedFileName,
    path: invalidFile.path,
    instruction: report.missingCaptureSteps[slotIndex].instruction,
    supportingCommand: report.missingCaptureSteps[slotIndex].supportingCommand
  };

  return invalidFile;
}

test("validates app runtime review verification fixture", () => {
  const report = demoVerification();

  assert.equal(validateAppRuntimeReviewVerification(report), report);
});

test("rejects verification reports whose attached count drifts from review card", () => {
  const report = demoVerification();
  report.attachedScreenshotCount = 99;
  report.screenshotEvidenceSummary.validScreenshotCount = 99;

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

test("rejects invalid screenshots without invalid capture steps", () => {
  const report = demoVerification();
  markInvalidScreenshot(report);

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /invalid capture step count/
  );
});

test("rejects invalid capture steps that drift from invalid screenshots", () => {
  const report = demoVerification();
  markInvalidScreenshot(report);
  report.invalidCaptureSteps = [report.missingCaptureSteps[1]];
  report.nextInvalidCaptureStep = report.invalidCaptureSteps[0];

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /invalid capture steps/
  );
});

test("rejects screenshot evidence summary count drift", () => {
  const report = demoVerification();
  report.screenshotEvidenceSummary.pendingScreenshotCount = 99;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /screenshot summary pending count/
  );
});

test("rejects screenshot evidence summary next step drift", () => {
  const report = demoVerification();
  report.screenshotEvidenceSummary.nextExpectedFileName = report.missingCaptureSteps[1].expectedFileName;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /screenshot summary capture step/
  );
});

test("rejects verification reports without a next evidence action", () => {
  const report = demoVerification();
  delete report.nextEvidenceAction;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /nextEvidenceAction/
  );
});

test("rejects next evidence actions that drift from the next capture step", () => {
  const report = demoVerification();
  report.nextEvidenceAction.expectedFileName = report.missingCaptureSteps[1].expectedFileName;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /nextEvidenceAction/
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
  report.screenshotEvidenceSummary.minimumHeight = 1;

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /minimum screenshot dimensions/
  );
});

test("rejects complete verification reports without proved app check proof", () => {
  const report = demoVerification();
  report.attachedScreenshotCount = report.requiredScreenshotCount;
  report.isComplete = true;
  report.missingFiles = [];
  report.invalidScreenshotFiles = [];
  report.invalidCaptureSteps = [];
  delete report.nextInvalidCaptureStep;
  report.missingCaptureSteps = [];
  delete report.nextMissingCaptureStep;
  report.screenshotEvidenceSummary = {
    state: "ready",
    requiredScreenshotCount: report.requiredScreenshotCount,
    validScreenshotCount: report.requiredScreenshotCount,
    missingScreenshotCount: 0,
    invalidScreenshotCount: 0,
    pendingScreenshotCount: 0,
    minimumWidth: report.minimumScreenshotWidth,
    minimumHeight: report.minimumScreenshotHeight,
    isScreenshotEvidenceReady: true,
    nextStepKind: "shareEvidence",
    nextStepTitle: "Share Review Evidence"
  };
  report.nextEvidenceAction = {
    kind: "shareEvidence",
    title: "Share Review Evidence",
    command: report.openEvidenceDirectoryCommand,
    isReadyToShare: true,
    instruction: "Open the complete evidence folder and share the verified review artifacts."
  };
  report.review.attachedScreenshotCount = report.review.requiredScreenshotCount;
  report.review.areRequiredScreenshotsAttached = true;
  for (const slot of report.review.screenshotSlots) {
    slot.attachmentState = "attached";
    slot.attachmentPath = `${report.evidenceDirectory}/${slot.expectedFileName}`;
    slot.attachmentByteCount = 68;
    slot.attachmentWidth = 1440;
    slot.attachmentHeight = 900;
  }

  assert.throws(
    () => validateAppRuntimeReviewVerification(report),
    /app check proof/
  );
});

test("accepts complete verification reports", () => {
  const report = demoVerification();
  report.attachedScreenshotCount = report.requiredScreenshotCount;
  report.isComplete = true;
  report.missingFiles = [];
  report.invalidScreenshotFiles = [];
  report.invalidCaptureSteps = [];
  delete report.nextInvalidCaptureStep;
  report.screenshotEvidenceSummary = {
    state: "ready",
    requiredScreenshotCount: report.requiredScreenshotCount,
    validScreenshotCount: report.requiredScreenshotCount,
    missingScreenshotCount: 0,
    invalidScreenshotCount: 0,
    pendingScreenshotCount: 0,
    minimumWidth: report.minimumScreenshotWidth,
    minimumHeight: report.minimumScreenshotHeight,
    isScreenshotEvidenceReady: true,
    nextStepKind: "shareEvidence",
    nextStepTitle: "Share Review Evidence"
  };
  report.missingCaptureSteps = [];
  delete report.nextMissingCaptureStep;
  report.nextEvidenceAction = {
    kind: "shareEvidence",
    title: "Share Review Evidence",
    command: report.openEvidenceDirectoryCommand,
    isReadyToShare: true,
    instruction: "Open the complete evidence folder and share the verified review artifacts."
  };
  report.appCheckProof = {
    ...report.appCheckProof,
    exists: true,
    isValid: true,
    kind: "windowsMVPProof",
    status: "proved",
    appId: "winapp_notepad"
  };
  delete report.appCheckProof.issueReason;
  report.review.attachedScreenshotCount = report.review.requiredScreenshotCount;
  report.review.invalidScreenshotCount = 0;
  report.review.areRequiredScreenshotsAttached = true;
  for (const slot of report.review.screenshotSlots) {
    slot.attachmentState = "attached";
    slot.attachmentPath = `${report.evidenceDirectory}/${slot.expectedFileName}`;
    slot.attachmentByteCount = 68;
    slot.attachmentWidth = 1440;
    slot.attachmentHeight = 900;
  }

  assert.equal(validateAppRuntimeReviewVerification(report), report);
});
