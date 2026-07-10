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

test("rejects cards without top-level launch onboarding state", () => {
  const card = demoReviewCard();
  delete card.launchOnboarding;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /launchOnboarding/
  );
});

test("rejects launch onboarding drift from embedded status", () => {
  const card = demoReviewCard();
  card.launchOnboarding.state = "blocked";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /launchOnboarding/
  );
});

test("rejects latest app check latency drift from embedded status", () => {
  const card = demoReviewCard();
  card.evidence.latestAppCheckLatencyHealth = "healthy";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /latestAppCheckLatencyHealth/
  );
});

test("rejects multi-app proof coverage drift from embedded status", () => {
  const card = demoReviewCard();
  card.evidence.multiAppProofCoverageHealth = "complete";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /multiAppProofCoverageHealth/
  );
});

test("rejects Daily Use evidence drift from embedded status", () => {
  const card = demoReviewCard();
  card.evidence.dailyUseRecommendedAction = "verify-daily-use-integrations";

  assert.throws(
    () => validateAppRuntimeReview(card),
    /dailyUseRecommendedAction/
  );
});

test("rejects package identity evidence drift from embedded status", () => {
  const card = demoReviewCard();
  card.evidence.dailyUsePackageIdentitySucceeded = true;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /dailyUsePackageIdentitySucceeded/
  );
});

test("rejects latest notification proof drift from embedded status", () => {
  const card = demoReviewCard();
  Object.assign(card.status.proofArtifacts, {
    latestNotificationProofPath: "/Users/test/Library/Application Support/Veil/Diagnostics/Notification Proof/notification-proof.json",
    latestNotificationProofFileName: "notification-proof.json",
    latestNotificationProofModifiedAt: "2026-07-10T12:20:00Z",
    latestNotificationProofStatus: "proved",
    latestNotificationProofId: "toast:winapp_notepad:0001",
    latestNotificationProofTitle: "Notepad",
    latestNotificationProofReceivedAt: "2026-07-10T12:15:00Z"
  });
  Object.assign(card.evidence, {
    latestNotificationProofPath: card.status.proofArtifacts.latestNotificationProofPath,
    latestNotificationProofModifiedAt: card.status.proofArtifacts.latestNotificationProofModifiedAt,
    latestNotificationProofStatus: "unavailable",
    latestNotificationProofId: card.status.proofArtifacts.latestNotificationProofId,
    latestNotificationProofTitle: card.status.proofArtifacts.latestNotificationProofTitle,
    latestNotificationProofReceivedAt: card.status.proofArtifacts.latestNotificationProofReceivedAt
  });

  assert.throws(
    () => validateAppRuntimeReview(card),
    /latestNotificationProofStatus/
  );
});

test("rejects latest printer bridge proof drift from embedded status", () => {
  const card = demoReviewCard();
  Object.assign(card.status.proofArtifacts, {
    latestPrinterBridgeProofPath: "/Users/test/Library/Application Support/Veil/Diagnostics/Printer Proof/printer-bridge-proof.json",
    latestPrinterBridgeProofFileName: "printer-bridge-proof.json",
    latestPrinterBridgeProofModifiedAt: "2026-07-10T12:30:00Z",
    latestPrinterBridgeProofStatus: "proved",
    latestPrinterBridgeProofEvidencePath: "/Users/test/Desktop/windows-test-page.pdf",
    latestPrinterBridgeProofEvidenceFileName: "windows-test-page.pdf",
    latestPrinterBridgeProofEvidenceByteCount: 8192,
    latestPrinterBridgeProofEvidenceModifiedAt: "2026-07-10T12:29:00Z",
    latestPrinterBridgeProofSharedPrinterName: "Office Printer",
    latestPrinterBridgeProofWindowsPrinterName: "Veil Mac Printer",
    latestPrinterBridgeProofIppEndpoint: "http://10.0.2.2:631/printers/Office%20Printer"
  });
  Object.assign(card.evidence, {
    latestPrinterBridgeProofPath: card.status.proofArtifacts.latestPrinterBridgeProofPath,
    latestPrinterBridgeProofModifiedAt: card.status.proofArtifacts.latestPrinterBridgeProofModifiedAt,
    latestPrinterBridgeProofStatus: card.status.proofArtifacts.latestPrinterBridgeProofStatus,
    latestPrinterBridgeProofEvidencePath: card.status.proofArtifacts.latestPrinterBridgeProofEvidencePath,
    latestPrinterBridgeProofEvidenceFileName: "wrong-test-page.pdf",
    latestPrinterBridgeProofEvidenceByteCount: card.status.proofArtifacts.latestPrinterBridgeProofEvidenceByteCount,
    latestPrinterBridgeProofEvidenceModifiedAt: card.status.proofArtifacts.latestPrinterBridgeProofEvidenceModifiedAt,
    latestPrinterBridgeProofIppEndpoint: card.status.proofArtifacts.latestPrinterBridgeProofIppEndpoint
  });

  assert.throws(
    () => validateAppRuntimeReview(card),
    /latestPrinterBridgeProofEvidenceFileName/
  );
});

test("accepts latest printer bridge proof evidence mirrored from status", () => {
  const card = demoReviewCard();
  Object.assign(card.status.proofArtifacts, {
    latestPrinterBridgeProofPath: "/Users/test/Library/Application Support/Veil/Diagnostics/Printer Proof/printer-bridge-proof.json",
    latestPrinterBridgeProofFileName: "printer-bridge-proof.json",
    latestPrinterBridgeProofModifiedAt: "2026-07-10T12:30:00Z",
    latestPrinterBridgeProofStatus: "proved",
    latestPrinterBridgeProofEvidencePath: "/Users/test/Desktop/windows-test-page.pdf",
    latestPrinterBridgeProofEvidenceFileName: "windows-test-page.pdf",
    latestPrinterBridgeProofEvidenceByteCount: 8192,
    latestPrinterBridgeProofEvidenceModifiedAt: "2026-07-10T12:29:00Z",
    latestPrinterBridgeProofSharedPrinterName: "Office Printer",
    latestPrinterBridgeProofWindowsPrinterName: "Veil Mac Printer",
    latestPrinterBridgeProofIppEndpoint: "http://10.0.2.2:631/printers/Office%20Printer"
  });
  Object.assign(card.evidence, {
    latestPrinterBridgeProofPath: card.status.proofArtifacts.latestPrinterBridgeProofPath,
    latestPrinterBridgeProofModifiedAt: card.status.proofArtifacts.latestPrinterBridgeProofModifiedAt,
    latestPrinterBridgeProofStatus: card.status.proofArtifacts.latestPrinterBridgeProofStatus,
    latestPrinterBridgeProofEvidencePath: card.status.proofArtifacts.latestPrinterBridgeProofEvidencePath,
    latestPrinterBridgeProofEvidenceFileName: card.status.proofArtifacts.latestPrinterBridgeProofEvidenceFileName,
    latestPrinterBridgeProofEvidenceByteCount: card.status.proofArtifacts.latestPrinterBridgeProofEvidenceByteCount,
    latestPrinterBridgeProofEvidenceModifiedAt: card.status.proofArtifacts.latestPrinterBridgeProofEvidenceModifiedAt,
    latestPrinterBridgeProofIppEndpoint: card.status.proofArtifacts.latestPrinterBridgeProofIppEndpoint
  });

  assert.equal(validateAppRuntimeReview(card), card);
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
  card.invalidScreenshotCount = 1;
  card.nextStepTitle = "Replace Review Screenshots";
  card.screenshotSlots[0].attachmentIssueReason = "belowMinimumDimensions";
  card.screenshotSlots[0].invalidAttachmentPath = "/tmp/veil-review/preBootLauncher.png";
  card.screenshotSlots[0].invalidAttachmentByteCount = 68;
  card.screenshotSlots[0].invalidAttachmentWidth = 1;
  card.screenshotSlots[0].invalidAttachmentHeight = 1;

  assert.equal(validateAppRuntimeReview(card), card);
});

test("rejects invalid screenshot count drift", () => {
  const card = demoReviewCard();
  card.invalidScreenshotCount = 1;

  assert.throws(
    () => validateAppRuntimeReview(card),
    /invalid screenshot count/
  );
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
  card.invalidScreenshotCount = 0;
  card.areRequiredScreenshotsAttached = true;
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

test("allows bundle-blocked cards to keep the earlier release-gate next command", () => {
  const card = demoReviewCard();
  card.evidence.hostAppBundle.appIconExists = false;
  card.evidence.hostAppBundle.isVerificationReady = false;
  card.isReadyForReview = false;
  card.nextStepTitle = "Verify Host App Bundle";
  card.nextActionCommand = "veil-vmctl app-runtime-review --json";

  assert.equal(validateAppRuntimeReview(card), card);
});
