import { readFile } from "node:fs/promises";
import { test } from "node:test";
import assert from "node:assert/strict";

import { validateProviderOutput } from "../src/validate-provider-output.mjs";

test("validates the Apple and QEMU local provider fixture", async () => {
  const fixtureURL = new URL("../fixtures/providers.apple-and-qemu.json", import.meta.url);
  const providers = JSON.parse(await readFile(fixtureURL, "utf8"));

  const validated = validateProviderOutput(providers);

  assert.deepEqual(validated.map((provider) => provider.kind), [
    "appleVirtualization",
    "qemuHypervisor"
  ]);
  assert.equal(validated.every((provider) => provider.isServerBacked === false), true);
});

test("rejects provider output that implies a server-backed VM", () => {
  assert.throws(
    () => validateProviderOutput([
      {
        kind: "appleVirtualization",
        displayName: "Apple Virtualization",
        mode: "Local VM runtime",
        acceleration: "Apple Hypervisor",
        isServerBacked: false,
        status: "active",
        detail: "Runs locally."
      },
      {
        kind: "qemuHypervisor",
        displayName: "QEMU/HVF",
        mode: "Hosted VM runtime",
        acceleration: "HVF",
        isServerBacked: true,
        status: "active",
        detail: "Invalid hosted shape."
      }
    ]),
    /non-server-backed/
  );
});
