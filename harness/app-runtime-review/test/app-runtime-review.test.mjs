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

test("rejects cards whose readiness drifts from release gate", () => {
  const card = demoReviewCard();
  card.isReadyForReview = !card.status.releaseGate.isPassing;

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

test("accepts attached screenshot evidence paths", () => {
  const card = demoReviewCard();
  card.evidence.screenshotEvidenceDirectory = "/tmp/veil-review";
  card.screenshotSlots[0].attachmentState = "attached";
  card.screenshotSlots[0].attachmentPath = "/tmp/veil-review/preBootLauncher.png";
  card.attachedScreenshotCount = 1;

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

test("accepts complete screenshot evidence summary", () => {
  const card = demoReviewCard();
  card.evidence.screenshotEvidenceDirectory = "/tmp/veil-review";
  card.attachedScreenshotCount = card.requiredScreenshotCount;
  card.areRequiredScreenshotsAttached = true;
  for (const slot of card.screenshotSlots) {
    slot.attachmentState = "attached";
    slot.attachmentPath = `/tmp/veil-review/${slot.expectedFileName}`;
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
