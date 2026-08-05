import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../../..", import.meta.url));
const regressionScriptPath = fileURLToPath(new URL("../../../script/test_all.sh", import.meta.url));
const productionReadinessScriptPath = fileURLToPath(new URL("../../../script/production_readiness.sh", import.meta.url));

test("regression gate help documents every intentional skip", () => {
  const result = spawnSync("/bin/bash", [regressionScriptPath, "--help"], {
    cwd: repositoryRoot,
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /--skip-windows-agent/);
  assert.match(result.stdout, /--skip-app-verify/);
  assert.match(result.stdout, /--skip-node-install/);
  assert.match(result.stdout, /partial run cannot be mistaken for a passing full gate/);
});

test("regression gate lists every component without requiring toolchains", () => {
  const result = spawnSync("/bin/bash", [regressionScriptPath, "--list"], {
    cwd: repositoryRoot,
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Swift: apps\/mac-host/);
  assert.match(result.stdout, /Windows agent: apps\/windows-agent\/tests\/VeilAgent.Tests/);
  assert.match(result.stdout, /packages\/protocol/);
  assert.match(result.stdout, /harness\/fake-agent/);
  assert.match(result.stdout, /harness\/regression-gate/);
  assert.match(result.stdout, /build_and_run\.sh --verify/);
});

test("regression gate preflights before running deterministic component commands", async () => {
  const script = await readFile(regressionScriptPath, "utf8");
  const preflightCall = script.indexOf("\npreflight\n");
  const swiftTest = script.indexOf("swift test --disable-sandbox");

  assert.ok(preflightCall >= 0);
  assert.ok(swiftTest > preflightCall);
  assert.match(script, /\"\$DOTNET_BIN\" test/);
  assert.match(script, /npm --prefix "\$package_dir" ci/);
  assert.match(script, /npm --prefix "\$package_dir" test/);
  assert.match(script, /build_and_run\.sh" --verify/);
  assert.match(script, /no Node test packages were discovered/);
});

test("regression gate discovers Veil's installed .NET toolchain when dotnet is absent from PATH", async () => {
  const script = await readFile(regressionScriptPath, "utf8");

  assert.match(script, /VEIL_DOTNET_BIN/);
  assert.match(script, /Toolchains\/dotnet8\/dotnet/);
  assert.match(script, /DOTNET_BIN/);
  assert.match(script, /"\$DOTNET_BIN" test/);
});

test("production readiness gate blocks release while P0 checklist items remain unresolved", () => {
  const result = spawnSync("/bin/bash", [productionReadinessScriptPath, "--checklist-only", "--json"], {
    cwd: repositoryRoot,
    encoding: "utf8"
  });

  assert.equal(result.status, 2, result.stderr);
  const report = JSON.parse(result.stdout);
  assert.equal(report.status, "blocked");
  assert.equal(report.releaseReady, false);
  assert.ok(report.unresolvedP0Count > 0);
  assert.equal(report.automatedGate, "not-run");
});
