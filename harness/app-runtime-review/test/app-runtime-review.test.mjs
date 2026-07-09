import { readFileSync } from "node:fs";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateAppRuntimeReview } from "../src/validate-app-runtime-review.mjs";

function demoReviewCard() {
  return JSON.parse(readFileSync(new URL("../fixtures/app-runtime-review.demo.json", import.meta.url), "utf8"));
}

test("validates app runtime review fixture", () => {
  const card = demoReviewCard();

  assert.equal(validateAppRuntimeReview(card), card);
});

test("rejects cards whose readiness ignores missing review screenshots", () => {
  const card = demoReviewCard();
  card.isReadyForReview = true;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /readiness/
  );
});

test("rejects screenshot slots that drift from release gate", () => {
  const card = demoReviewCard();
  card.screenshotSlots[0].title = "Different Slot";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /screenshot/
  );
});

test("rejects cards with drifted minimum screenshot dimensions", () => {
  const card = demoReviewCard();
  card.minimumScreenshotWidth = 1;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /minimum screenshot dimensions/
  );
});

test("accepts attached screenshot evidence paths", () => {
  const card = demoReviewCard();
  card.evidence.screenshotEvidenceDirectory = "/tmp/veil-review";
  card.screenshotSlots[0].attachmentState = "attached";
  card.screenshotSlots[0].attachmentPath = "/tmp/veil-review/preBootLauncher.png";
  card.screenshotSlots[0].attachmentByteCount = 68;
  card.screenshotSlots[0].attachmentWidth = 1440;
  card.screenshotSlots[0].attachmentHeight = 900;
  card.attachedScreenshotCount = 1;
  card.nextActionCommand = "veil-vmctl app-runtime-review-verify --json --evidence-dir /tmp/veil-review";

  assert.equal(validateAppRuntimeReview(card), card);
});

test("rejects attached screenshot slots without paths", () => {
  const card = demoReviewCard();
  card.screenshotSlots[0].attachmentState = "attached";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /attachment path/
  );
});

test("rejects attached screenshot slots without byte counts", () => {
  const card = demoReviewCard();
  card.screenshotSlots[0].attachmentState = "attached";
  card.screenshotSlots[0].attachmentPath = "/tmp/veil-review/preBootLauncher.png";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /byte count/
  );
});

test("rejects attached screenshot slots without dimensions", () => {
  const card = demoReviewCard();
  card.screenshotSlots[0].attachmentState = "attached";
  card.screenshotSlots[0].attachmentPath = "/tmp/veil-review/preBootLauncher.png";
  card.screenshotSlots[0].attachmentByteCount = 68;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /dimensions/
  );
});

test("rejects attached screenshot slots below minimum dimensions", () => {
  const card = demoReviewCard();
  card.screenshotSlots[0].attachmentState = "attached";
  card.screenshotSlots[0].attachmentPath = "/tmp/veil-review/preBootLauncher.png";
  card.screenshotSlots[0].attachmentByteCount = 68;
  card.screenshotSlots[0].attachmentWidth = 1;
  card.screenshotSlots[0].attachmentHeight = 1;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /minimum screenshot dimensions/
  );
});

test("accepts missing screenshot slots with invalid attachment issues", () => {
  const card = demoReviewCard();
  card.evidence.screenshotEvidenceDirectory = "/tmp/veil-review";
  card.nextActionCommand = "veil-vmctl app-runtime-review-verify --json --evidence-dir /tmp/veil-review";
  card.screenshotSlots[0].attachmentIssueReason = "belowMinimumDimensions";
  card.screenshotSlots[0].invalidAttachmentPath = "/tmp/veil-review/preBootLauncher.png";
  card.screenshotSlots[0].invalidAttachmentByteCount = 68;
  card.screenshotSlots[0].invalidAttachmentWidth = 1;
  card.screenshotSlots[0].invalidAttachmentHeight = 1;

  assert.equal(validateAppRuntimeReview(card), card);
});

test("rejects screenshot issue reasons without invalid attachment paths", () => {
  const card = demoReviewCard();
  card.screenshotSlots[0].attachmentIssueReason = "notValidPNG";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /invalid attachment path/
  );
});

test("accepts complete screenshot evidence summary", () => {
  const card = demoReviewCard();
  card.evidence.screenshotEvidenceDirectory = "/tmp/veil-review";
  card.attachedScreenshotCount = card.requiredScreenshotCount;
  card.areRequiredScreenshotsAttached = true;
  card.isReadyForReview = true;
  card.appFlowSummary = "ready (5/5)";
  card.nextStepTitle = "Ready For App Review";
  delete card.nextActionCommand;
  card.detail = "Setup, launch, app checks, and close controls are covered.";
  for (const slot of card.screenshotSlots) {
    slot.attachmentState = "attached";
    slot.attachmentPath = `/tmp/veil-review/${slot.expectedFileName}`;
    slot.attachmentByteCount = 68;
    slot.attachmentWidth = 1440;
    slot.attachmentHeight = 900;
  }

  assert.equal(validateAppRuntimeReview(card), card);
});

test("rejects screenshot evidence summary drift", () => {
  const card = demoReviewCard();
  card.attachedScreenshotCount = 99;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /attached screenshot count/
  );
});

test("rejects host app bundle verification command drift", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.verificationCommand = "./script/build_and_run.sh";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /host app bundle verification command/
  );
});

test("rejects host app bundle readiness drift", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.appIconExists = false;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /host app bundle readiness/
  );
});

test("rejects host app bundle readiness when latest launch report is stale", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.latestLaunchReport.isCurrentForBundle = false;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /host app bundle readiness/
  );
});

test("rejects launcher contract reports that do not prove one visible main window", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.latestLaunchReport.mainWindowCount = 2;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /one visible main window/
  );
});

test("accepts release-ready cards that are blocked on host app bundle verification", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.appIconExists = false;
  card.evidence.hostAppBundle.isVerificationReady = false;
  card.isReadyForReview = false;
  card.appFlowSummary = "ready (5/5); host app bundle needs verification";
  card.nextStepTitle = "Verify Host App Bundle";
  card.nextActionCommand = card.evidence.hostAppBundle.verificationCommand;
  card.detail = "Setup, launch, app checks, and close controls are covered. Run bundled launcher verification and attach all 5 review screenshots before sharing evidence.";

  assert.equal(validateAppRuntimeReview(card), card);
});

test("accepts release-ready cards that are blocked on stale host launch verification", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.latestLaunchReport.isCurrentForBundle = false;
  card.evidence.hostAppBundle.isVerificationReady = false;
  card.isReadyForReview = false;
  card.appFlowSummary = "ready (5/5); host app bundle needs verification";
  card.nextStepTitle = "Verify Host App Bundle";
  card.nextActionCommand = card.evidence.hostAppBundle.verificationCommand;
  card.detail = "Setup, launch, app checks, and close controls are covered. Run bundled launcher verification and attach all 5 review screenshots before sharing evidence.";

  assert.equal(validateAppRuntimeReview(card), card);
});

test("rejects bundle-blocked cards without host verification next command", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.appIconExists = false;
  card.evidence.hostAppBundle.isVerificationReady = false;
  card.isReadyForReview = false;
  card.nextStepTitle = "Verify Host App Bundle";
  card.nextActionCommand = "veil-vmctl app-runtime-review --json";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /next command/
  );
});
