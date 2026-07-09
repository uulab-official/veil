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
  requireString(card.appFlowSummary, "appFlowSummary");
  requireString(card.nextStepTitle, "nextStepTitle");
  requireString(card.detail, "detail");
  requireString(card.statusCommand, "statusCommand");

  if (card.nextActionCommand !== undefined) {
    requireString(card.nextActionCommand, "nextActionCommand");
  }

  const status = validateAppRuntimeStatus(card.status);
  if (card.isReadyForReview !== status.releaseGate.isPassing) {
    throw new TypeError("app runtime review readiness must match the release gate.");
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
    if (slot.attachmentPath !== undefined) {
      requireString(slot.attachmentPath, `screenshotSlots.${index}.attachmentPath`);
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
    if (slot.attachmentState === "missing" && slot.attachmentPath !== undefined) {
      throw new TypeError("missing review screenshots must not include an attachment path.");
    }
  }

  validateEvidence(card.evidence, status);
  return card;
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

  if (evidence.latestAppCheckPath !== status.proofArtifacts.latestProofPath) {
    throw new TypeError("app runtime review latest app check path must match status proof artifacts.");
  }
  if (evidence.recommendedAppCheckCommand !== status.proofPlan.recommendedProofCommand) {
    throw new TypeError("app runtime review recommended app check command must match status proof plan.");
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
