import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { validateAppRuntimeStatus } from "../../app-runtime-status/src/validate-app-runtime-status.mjs";

export function validateAppRuntimeReview(card) {
  if (!card || typeof card !== "object" || Array.isArray(card)) {
    throw new TypeError("app runtime review card must be an object.");
  }

  requireString(card.kind, "kind");
  if (card.kind !== "windowsAppRuntimeReviewCard") {
    throw new TypeError("app runtime review card kind must be windowsAppRuntimeReviewCard.");
  }

  requireString(card.generatedAt, "generatedAt");
  if (Number.isNaN(Date.parse(card.generatedAt))) {
    throw new TypeError("app runtime review card generatedAt must be an ISO date.");
  }

  requireBoolean(card.isReadyForReview, "isReadyForReview");
  requireBoolean(card.areRequiredScreenshotsAttached, "areRequiredScreenshotsAttached");
  requireNonNegativeInteger(card.requiredScreenshotCount, "requiredScreenshotCount");
  requireNonNegativeInteger(card.attachedScreenshotCount, "attachedScreenshotCount");
  requireNonNegativeInteger(card.invalidScreenshotCount, "invalidScreenshotCount");
  requirePositiveInteger(card.minimumScreenshotWidth, "minimumScreenshotWidth");
  requirePositiveInteger(card.minimumScreenshotHeight, "minimumScreenshotHeight");
  requireString(card.appFlowSummary, "appFlowSummary");
  requireString(card.nextStepTitle, "nextStepTitle");
  requireString(card.detail, "detail");
  requireString(card.statusCommand, "statusCommand");

  if (card.nextActionCommand !== undefined) {
    requireString(card.nextActionCommand, "nextActionCommand");
  }
  if (card.minimumScreenshotWidth !== 640 || card.minimumScreenshotHeight !== 360) {
    throw new TypeError("app runtime review card minimum screenshot dimensions must be 640x360.");
  }

  const status = validateAppRuntimeStatus(card.status);
  validateLaunchOnboarding(card.launchOnboarding, status.launchOnboarding);
  const hostAppBundle = validateEvidence(card.evidence, status);
  if (status.releaseGate.isPassing && !hostAppBundle.isVerificationReady) {
    if (card.nextStepTitle !== "Verify Host App Bundle") {
      throw new TypeError("app runtime review next step must verify the host app bundle when release evidence passes but bundle evidence is not ready.");
    }
    if (card.nextActionCommand !== hostAppBundle.verificationCommand) {
      throw new TypeError("app runtime review next command must run host app bundle verification when bundle evidence is not ready.");
    }
  }

  if (!Array.isArray(card.steps) || card.steps.length !== status.releaseGate.steps.length) {
    throw new TypeError("app runtime review steps must mirror releaseGate.steps.");
  }

  for (const [index, step] of card.steps.entries()) {
    const sourceStep = status.releaseGate.steps[index];
    requireString(step.id, `steps.${index}.id`);
    requireString(step.title, `steps.${index}.title`);
    requireString(step.state, `steps.${index}.state`);
    requireBoolean(step.isPassing, `steps.${index}.isPassing`);
    requireString(step.evidence, `steps.${index}.evidence`);
    if (step.nextActionCommand !== undefined) {
      requireString(step.nextActionCommand, `steps.${index}.nextActionCommand`);
    }

    if (
      step.id !== sourceStep.id
      || step.title !== sourceStep.title
      || step.state !== sourceStep.state
      || step.isPassing !== sourceStep.isPassing
    ) {
      throw new TypeError("app runtime review steps must preserve release gate identity and state.");
    }
  }

  if (!Array.isArray(card.screenshotSlots) || card.screenshotSlots.length !== status.releaseGate.screenshotSlots.length) {
    throw new TypeError("app runtime review screenshot slots must mirror releaseGate.screenshotSlots.");
  }

  let attachedScreenshotCount = 0;
  let invalidScreenshotCount = 0;
  for (const [index, slot] of card.screenshotSlots.entries()) {
    const sourceSlot = status.releaseGate.screenshotSlots[index];
    requireString(slot.id, `screenshotSlots.${index}.id`);
    requireString(slot.title, `screenshotSlots.${index}.title`);
    requireString(slot.expectedSurface, `screenshotSlots.${index}.expectedSurface`);
    requireString(slot.expectedFileName, `screenshotSlots.${index}.expectedFileName`);
    requireString(slot.attachmentState, `screenshotSlots.${index}.attachmentState`);
    if (!["attached", "missing"].includes(slot.attachmentState)) {
      throw new TypeError("app runtime review screenshot attachment state must be attached or missing.");
    }
    if (slot.attachmentByteCount !== undefined) {
      requirePositiveInteger(slot.attachmentByteCount, `screenshotSlots.${index}.attachmentByteCount`);
    }
    if (slot.attachmentWidth !== undefined) {
      requirePositiveInteger(slot.attachmentWidth, `screenshotSlots.${index}.attachmentWidth`);
    }
    if (slot.attachmentHeight !== undefined) {
      requirePositiveInteger(slot.attachmentHeight, `screenshotSlots.${index}.attachmentHeight`);
    }
    if (slot.attachmentPath !== undefined) {
      requireString(slot.attachmentPath, `screenshotSlots.${index}.attachmentPath`);
    }
    if (slot.attachmentIssueReason !== undefined) {
      requireString(slot.attachmentIssueReason, `screenshotSlots.${index}.attachmentIssueReason`);
    }
    if (slot.invalidAttachmentPath !== undefined) {
      requireString(slot.invalidAttachmentPath, `screenshotSlots.${index}.invalidAttachmentPath`);
    }
    if (slot.invalidAttachmentByteCount !== undefined) {
      requirePositiveInteger(slot.invalidAttachmentByteCount, `screenshotSlots.${index}.invalidAttachmentByteCount`);
    }
    if (slot.invalidAttachmentWidth !== undefined) {
      requirePositiveInteger(slot.invalidAttachmentWidth, `screenshotSlots.${index}.invalidAttachmentWidth`);
    }
    if (slot.invalidAttachmentHeight !== undefined) {
      requirePositiveInteger(slot.invalidAttachmentHeight, `screenshotSlots.${index}.invalidAttachmentHeight`);
    }

    if (
      slot.id !== sourceSlot.id
      || slot.title !== sourceSlot.title
      || slot.expectedSurface !== sourceSlot.expectedSurface
    ) {
      throw new TypeError("app runtime review screenshot slots must preserve release gate screenshot identity.");
    }
    if (slot.expectedFileName !== `${sourceSlot.id}.png`) {
      throw new TypeError("app runtime review screenshot file names must be derived from release gate slot ids.");
    }
    if (slot.attachmentState === "attached" && slot.attachmentPath === undefined) {
      throw new TypeError("attached review screenshots must include an attachment path.");
    }
    if (slot.attachmentState === "attached" && slot.attachmentIssueReason !== undefined) {
      throw new TypeError("attached review screenshots must not include an attachment issue reason.");
    }
    if (slot.attachmentState === "attached" && slot.invalidAttachmentPath !== undefined) {
      throw new TypeError("attached review screenshots must not include invalid attachment metadata.");
    }
    if (slot.attachmentState === "attached" && slot.attachmentByteCount === undefined) {
      throw new TypeError("attached review screenshots must include a positive PNG byte count.");
    }
    if (slot.attachmentState === "attached" && (slot.attachmentWidth === undefined || slot.attachmentHeight === undefined)) {
      throw new TypeError("attached review screenshots must include PNG dimensions.");
    }
    if (
      slot.attachmentState === "attached"
      && (
        slot.attachmentWidth < card.minimumScreenshotWidth
        || slot.attachmentHeight < card.minimumScreenshotHeight
      )
    ) {
      throw new TypeError("attached review screenshots must meet the card minimum screenshot dimensions.");
    }
    if (slot.attachmentState === "missing" && slot.attachmentPath !== undefined) {
      throw new TypeError("missing review screenshots must not include an attachment path.");
    }
    if (slot.attachmentState === "missing" && slot.attachmentByteCount !== undefined) {
      throw new TypeError("missing review screenshots must not include a byte count.");
    }
    if (slot.attachmentState === "missing" && (slot.attachmentWidth !== undefined || slot.attachmentHeight !== undefined)) {
      throw new TypeError("missing review screenshots must not include dimensions.");
    }
    if (slot.attachmentIssueReason !== undefined) {
      invalidScreenshotCount += 1;
      if (!["unreadableFile", "notValidPNG", "belowMinimumDimensions"].includes(slot.attachmentIssueReason)) {
        throw new TypeError("app runtime review screenshot issue reason is unsupported.");
      }
      if (slot.attachmentState !== "missing") {
        throw new TypeError("app runtime review screenshot issue reasons only apply to missing slots.");
      }
      if (slot.invalidAttachmentPath === undefined) {
        throw new TypeError("app runtime review screenshot issue reason must include an invalid attachment path.");
      }
      if (slot.invalidAttachmentPath !== `${card.evidence.screenshotEvidenceDirectory}/${slot.expectedFileName}`) {
        throw new TypeError("app runtime review invalid attachment path must match the evidence directory and expected file.");
      }
      if (slot.attachmentIssueReason === "belowMinimumDimensions" && (slot.invalidAttachmentWidth === undefined || slot.invalidAttachmentHeight === undefined)) {
        throw new TypeError("app runtime review below-minimum screenshot issues must include dimensions.");
      }
    } else if (
      slot.invalidAttachmentPath !== undefined
      || slot.invalidAttachmentByteCount !== undefined
      || slot.invalidAttachmentWidth !== undefined
      || slot.invalidAttachmentHeight !== undefined
    ) {
      throw new TypeError("app runtime review invalid attachment metadata requires an issue reason.");
    }
    if (slot.attachmentState === "attached") {
      attachedScreenshotCount += 1;
    }
  }

  const requiredScreenshotCount = status.releaseGate.screenshotSlots.filter((slot) => slot.isRequired).length;
  if (card.requiredScreenshotCount !== requiredScreenshotCount) {
    throw new TypeError("app runtime review required screenshot count must match release gate slots.");
  }
  if (card.attachedScreenshotCount !== attachedScreenshotCount) {
    throw new TypeError("app runtime review attached screenshot count must match attached slots.");
  }
  if (card.invalidScreenshotCount !== invalidScreenshotCount) {
    throw new TypeError("app runtime review invalid screenshot count must match screenshot slot issues.");
  }
  if (card.areRequiredScreenshotsAttached !== (attachedScreenshotCount === requiredScreenshotCount)) {
    throw new TypeError("app runtime review screenshot readiness must match attached required slots.");
  }
  if (card.isReadyForReview !== (status.releaseGate.isPassing && hostAppBundle.isVerificationReady && card.areRequiredScreenshotsAttached)) {
    throw new TypeError("app runtime review readiness must match the release gate, host app bundle evidence, and required screenshot evidence.");
  }
  if (status.releaseGate.isPassing && hostAppBundle.isVerificationReady && !card.areRequiredScreenshotsAttached) {
    if (invalidScreenshotCount > 0 && card.nextStepTitle !== "Replace Review Screenshots") {
      throw new TypeError("app runtime review next step must replace invalid review screenshots when release and bundle evidence pass but screenshots are invalid.");
    }
    if (invalidScreenshotCount === 0 && card.nextStepTitle !== "Attach Review Screenshots") {
      throw new TypeError("app runtime review next step must attach review screenshots when release and bundle evidence pass but screenshots are missing.");
    }
    if (
      card.evidence.screenshotEvidenceDirectory !== undefined
      && !isEvidenceVerifyCommand(card.nextActionCommand, card.evidence.screenshotEvidenceDirectory)
    ) {
      throw new TypeError("app runtime review next command must verify the evidence directory when screenshots are missing.");
    }
  }

  return card;
}

function validateLaunchOnboarding(launchOnboarding, sourceLaunchOnboarding) {
  if (!launchOnboarding || typeof launchOnboarding !== "object" || Array.isArray(launchOnboarding)) {
    throw new TypeError("app runtime review launchOnboarding must be an object.");
  }

  for (const fieldName of [
    "isEnabled",
    "usesSinglePrimarySurface",
    "canContinueInApp",
    "heroRunsPrimaryAction",
    "keepsRecoveryInMenuOrDock",
    "keepsVMDisplayManual",
    "pendingLiveProof"
  ]) {
    requireBoolean(launchOnboarding[fieldName], `launchOnboarding.${fieldName}`);
  }

  for (const fieldName of [
    "state",
    "currentStepId",
    "currentStepTitle",
    "progressLabel",
    "reason"
  ]) {
    requireString(launchOnboarding[fieldName], `launchOnboarding.${fieldName}`);
  }
  requireNonNegativeInteger(launchOnboarding.expectedVisibleSurfaceCount, "launchOnboarding.expectedVisibleSurfaceCount");
  requireNonNegativeInteger(launchOnboarding.completedStepCount, "launchOnboarding.completedStepCount");
  requireNonNegativeInteger(launchOnboarding.totalStepCount, "launchOnboarding.totalStepCount");
  requireNonNegativeInteger(launchOnboarding.currentStepNumber, "launchOnboarding.currentStepNumber");

  for (const fieldName of ["primaryActionId", "primaryCommand"]) {
    if (launchOnboarding[fieldName] !== undefined) {
      requireString(launchOnboarding[fieldName], `launchOnboarding.${fieldName}`);
    }
  }

  for (const fieldName of [
    "isEnabled",
    "state",
    "currentStepId",
    "currentStepTitle",
    "usesSinglePrimarySurface",
    "expectedVisibleSurfaceCount",
    "canContinueInApp",
    "heroRunsPrimaryAction",
    "keepsRecoveryInMenuOrDock",
    "keepsVMDisplayManual",
    "pendingLiveProof",
    "completedStepCount",
    "totalStepCount",
    "currentStepNumber",
    "progressLabel",
    "primaryActionId",
    "primaryCommand",
    "reason"
  ]) {
    if (launchOnboarding[fieldName] !== sourceLaunchOnboarding[fieldName]) {
      throw new TypeError("app runtime review launchOnboarding must match status.launchOnboarding.");
    }
  }
}

function validateEvidence(evidence, status) {
  if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) {
    throw new TypeError("app runtime review evidence must be an object.");
  }

  requireString(evidence.diagnosticsDirectory, "evidence.diagnosticsDirectory");
  if (evidence.screenshotEvidenceDirectory !== undefined) {
    requireString(evidence.screenshotEvidenceDirectory, "evidence.screenshotEvidenceDirectory");
  }

  if (evidence.latestAppCheckKind !== undefined) {
    requireString(evidence.latestAppCheckKind, "evidence.latestAppCheckKind");
  }
  if (evidence.latestAppCheckPath !== undefined) {
    requireString(evidence.latestAppCheckPath, "evidence.latestAppCheckPath");
  }
  if (evidence.latestAppCheckModifiedAt !== undefined && Number.isNaN(Date.parse(evidence.latestAppCheckModifiedAt))) {
    throw new TypeError("evidence.latestAppCheckModifiedAt must be an ISO date.");
  }
  if (evidence.recommendedAppCheckCommand !== undefined) {
    requireString(evidence.recommendedAppCheckCommand, "evidence.recommendedAppCheckCommand");
  }
  validateHostAppBundleEvidence(evidence.hostAppBundle);

  if (evidence.latestAppCheckPath !== status.proofArtifacts.latestProofPath) {
    throw new TypeError("app runtime review latest app check path must match status proof artifacts.");
  }
  if (evidence.recommendedAppCheckCommand !== status.proofPlan.recommendedProofCommand) {
    throw new TypeError("app runtime review recommended app check command must match status proof plan.");
  }

  return evidence.hostAppBundle;
}

function isEvidenceVerifyCommand(command, evidenceDirectory) {
  return command === `veil-vmctl app-runtime-review-verify --json --evidence-dir ${evidenceDirectory}`
    || command === `veil-vmctl app-runtime-review-verify --json --evidence-dir '${evidenceDirectory}'`;
}

function validateHostAppBundleEvidence(hostAppBundle) {
  if (!hostAppBundle || typeof hostAppBundle !== "object" || Array.isArray(hostAppBundle)) {
    throw new TypeError("app runtime review host app bundle evidence must be an object.");
  }

  requireString(hostAppBundle.verificationCommand, "evidence.hostAppBundle.verificationCommand");
  requireString(hostAppBundle.appBundlePath, "evidence.hostAppBundle.appBundlePath");
  requireBoolean(hostAppBundle.isStagedBundlePresent, "evidence.hostAppBundle.isStagedBundlePresent");
  requireBoolean(hostAppBundle.infoPlistExists, "evidence.hostAppBundle.infoPlistExists");
  requireBoolean(hostAppBundle.executableExists, "evidence.hostAppBundle.executableExists");
  requireBoolean(hostAppBundle.appIconExists, "evidence.hostAppBundle.appIconExists");
  requireString(hostAppBundle.expectedBundleIdentifier, "evidence.hostAppBundle.expectedBundleIdentifier");
  requireBoolean(hostAppBundle.isVerificationReady, "evidence.hostAppBundle.isVerificationReady");
  validateHostAppLaunchReportEvidence(hostAppBundle.latestLaunchReport, hostAppBundle.expectedBundleIdentifier);

  if (hostAppBundle.bundleIdentifier !== undefined) {
    requireString(hostAppBundle.bundleIdentifier, "evidence.hostAppBundle.bundleIdentifier");
  }
  if (hostAppBundle.latestFailedLaunchReportPath !== undefined) {
    requireString(hostAppBundle.latestFailedLaunchReportPath, "evidence.hostAppBundle.latestFailedLaunchReportPath");
  }
  if (
    hostAppBundle.latestFailedLaunchReportModifiedAt !== undefined
    && Number.isNaN(Date.parse(hostAppBundle.latestFailedLaunchReportModifiedAt))
  ) {
    throw new TypeError("evidence.hostAppBundle.latestFailedLaunchReportModifiedAt must be an ISO date.");
  }

  if (hostAppBundle.verificationCommand !== "./script/build_and_run.sh --verify") {
    throw new TypeError("app runtime review host app bundle verification command must use the bundled launcher verification.");
  }
  if (!hostAppBundle.appBundlePath.endsWith("/dist/Veil.app")) {
    throw new TypeError("app runtime review host app bundle path must point at dist/Veil.app.");
  }
  if (hostAppBundle.expectedBundleIdentifier !== "org.uulab.veil.host-shell") {
    throw new TypeError("app runtime review host app bundle expected bundle id is wrong.");
  }
  if (
    hostAppBundle.isVerificationReady
    !== (
      hostAppBundle.isStagedBundlePresent
      && hostAppBundle.infoPlistExists
      && hostAppBundle.executableExists
      && hostAppBundle.appIconExists
      && hostAppBundle.bundleIdentifier === hostAppBundle.expectedBundleIdentifier
      && hostAppBundle.latestLaunchReport.meetsLauncherContract
      && hostAppBundle.latestLaunchReport.isCurrentForBundle
      && hostAppBundle.latestLaunchReport.bundleIdentifier === hostAppBundle.expectedBundleIdentifier
    )
  ) {
    throw new TypeError("app runtime review host app bundle readiness must match bundle evidence.");
  }
}

function validateHostAppLaunchReportEvidence(launchReport, expectedBundleIdentifier) {
  if (!launchReport || typeof launchReport !== "object" || Array.isArray(launchReport)) {
    throw new TypeError("app runtime review host app launch report evidence must be an object.");
  }

  requireBoolean(launchReport.meetsLauncherContract, "evidence.hostAppBundle.latestLaunchReport.meetsLauncherContract");
  requireBoolean(launchReport.isCurrentForBundle, "evidence.hostAppBundle.latestLaunchReport.isCurrentForBundle");
  requireString(launchReport.expectedBundleIdentifier, "evidence.hostAppBundle.latestLaunchReport.expectedBundleIdentifier");

  if (launchReport.reportPath !== undefined) {
    requireString(launchReport.reportPath, "evidence.hostAppBundle.latestLaunchReport.reportPath");
    if (!launchReport.reportPath.endsWith("/dist/veil-launch-report-latest.plist")) {
      throw new TypeError("app runtime review host app launch report path must point at dist/veil-launch-report-latest.plist.");
    }
  }
  if (launchReport.modifiedAt !== undefined && Number.isNaN(Date.parse(launchReport.modifiedAt))) {
    throw new TypeError("evidence.hostAppBundle.latestLaunchReport.modifiedAt must be an ISO date.");
  }
  if (launchReport.bundleIdentifier !== undefined) {
    requireString(launchReport.bundleIdentifier, "evidence.hostAppBundle.latestLaunchReport.bundleIdentifier");
  }
  if (launchReport.appIconSource !== undefined) {
    requireString(launchReport.appIconSource, "evidence.hostAppBundle.latestLaunchReport.appIconSource");
  }

  for (const fieldName of [
    "mainWindowCount",
    "visibleMainWindowCount",
    "duplicateMainWindowCount"
  ]) {
    if (launchReport[fieldName] !== undefined) {
      requireNonNegativeInteger(launchReport[fieldName], `evidence.hostAppBundle.latestLaunchReport.${fieldName}`);
    }
  }
  for (const fieldName of ["frameWidth", "frameHeight", "minWidth", "minHeight"]) {
    if (launchReport[fieldName] !== undefined) {
      requirePositiveNumber(launchReport[fieldName], `evidence.hostAppBundle.latestLaunchReport.${fieldName}`);
    }
  }
  for (const fieldName of ["titlebarAppearsTransparent", "hasFullSizeContentView"]) {
    if (launchReport[fieldName] !== undefined) {
      requireBoolean(launchReport[fieldName], `evidence.hostAppBundle.latestLaunchReport.${fieldName}`);
    }
  }

  if (launchReport.expectedBundleIdentifier !== expectedBundleIdentifier) {
    throw new TypeError("app runtime review host app launch report expected bundle id must match host bundle evidence.");
  }
  if (launchReport.meetsLauncherContract) {
    if (launchReport.bundleIdentifier !== expectedBundleIdentifier) {
      throw new TypeError("app runtime review host app launch report bundle id must match the staged app.");
    }
    if (launchReport.mainWindowCount !== 1 || launchReport.visibleMainWindowCount !== 1 || launchReport.duplicateMainWindowCount !== 0) {
      throw new TypeError("app runtime review host app launch report must prove exactly one visible main window.");
    }
    if (launchReport.frameWidth < 1180 || launchReport.frameHeight < 760 || launchReport.minWidth < 1180 || launchReport.minHeight < 760) {
      throw new TypeError("app runtime review host app launch report must prove launcher sizing.");
    }
    if (launchReport.titlebarAppearsTransparent !== true || launchReport.hasFullSizeContentView !== true) {
      throw new TypeError("app runtime review host app launch report must prove custom titlebar coverage.");
    }
    if (launchReport.appIconSource !== "bundled") {
      throw new TypeError("app runtime review host app launch report must prove bundled app icon usage.");
    }
  }
}

function requireString(value, fieldName) {
  if (typeof value !== "string" || value.length === 0) {
    throw new TypeError(`App runtime review field '${fieldName}' must be a non-empty string.`);
  }
}

function requireBoolean(value, fieldName) {
  if (typeof value !== "boolean") {
    throw new TypeError(`App runtime review field '${fieldName}' must be boolean.`);
  }
}

function requireNonNegativeInteger(value, fieldName) {
  if (!Number.isInteger(value) || value < 0) {
    throw new TypeError(`App runtime review field '${fieldName}' must be a non-negative integer.`);
  }
}

function requirePositiveInteger(value, fieldName) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new TypeError(`App runtime review field '${fieldName}' must be a positive integer.`);
  }
}

function requirePositiveNumber(value, fieldName) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new TypeError(`App runtime review field '${fieldName}' must be a positive number.`);
  }
}

function readStdin() {
  return readFileSync(0, "utf8");
}

function main() {
  const input = readStdin().trim();
  if (!input) {
    throw new TypeError("Expected app runtime review JSON on stdin.");
  }

  validateAppRuntimeReview(JSON.parse(input));
  process.stdout.write("app runtime review valid\n");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
