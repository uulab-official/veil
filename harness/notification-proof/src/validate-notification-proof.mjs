#!/usr/bin/env node
import { readFileSync } from "node:fs";

const allowedStatuses = new Set(["proved", "unavailable"]);

export function validateNotificationProof(report, options = {}) {
  requireObject(report, "report");
  requireString(report.kind, "kind");
  if (report.kind !== "windowsNotificationProof") {
    throw new TypeError("kind must be windowsNotificationProof.");
  }

  requireString(report.endpoint, "endpoint");
  requireString(report.status, "status");
  if (!allowedStatuses.has(report.status)) {
    throw new TypeError("status must be proved or unavailable.");
  }

  requireString(report.provedAt, "provedAt");
  requireObject(report.wait, "wait");
  requireString(report.wait.kind, "wait.kind");
  if (report.wait.kind !== "guestAgentWait") {
    throw new TypeError("wait.kind must be guestAgentWait.");
  }
  requireString(report.wait.status, "wait.status");
  requireNumber(report.wait.waitedSeconds, "wait.waitedSeconds");
  requireNumber(report.wait.attempts, "wait.attempts");
  requireObject(report.wait.diagnostic, "wait.diagnostic");
  requireArray(report.nextActions, "nextActions");
  requireNumber(report.waitedForNotificationSeconds, "waitedForNotificationSeconds");

  if (report.status === "proved") {
    requireObject(report.notification, "notification");
    validateNotification(report.notification);
    if (report.wait.status !== "connected") {
      throw new TypeError("proved notification proof requires wait.status=connected.");
    }
    if (!report.nextActions.some((action) => action.includes("notificationBridge.recommendedAction"))) {
      throw new TypeError("proved notification proof must point back to notificationBridge status.");
    }
  } else if (report.notification !== undefined && report.notification !== null) {
    throw new TypeError("unavailable notification proof must not include notification evidence.");
  }

  if (options.requireProved && report.status !== "proved") {
    throw new TypeError("notification proof is not proved.");
  }

  return report;
}

function validateNotification(notification) {
  requireString(notification.type, "notification.type");
  if (notification.type !== "notification.received") {
    throw new TypeError("notification.type must be notification.received.");
  }
  requireString(notification.notificationId, "notification.notificationId");
  requireString(notification.title, "notification.title");
  requireString(notification.receivedAt, "notification.receivedAt");
  for (const field of ["appId", "appName", "body", "sourceAumid"]) {
    if (notification[field] !== undefined && notification[field] !== null) {
      requireString(notification[field], `notification.${field}`);
    }
  }
}

function requireObject(value, name) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object.`);
  }
}

function requireArray(value, name) {
  if (!Array.isArray(value)) {
    throw new TypeError(`${name} must be an array.`);
  }
}

function requireString(value, name) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new TypeError(`${name} must be a non-empty string.`);
  }
}

function requireNumber(value, name) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${name} must be a finite number.`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const options = {
    requireProved: process.argv.includes("--require-proved")
  };
  const input = readFileSync(0, "utf8");
  validateNotificationProof(JSON.parse(input), options);
}
