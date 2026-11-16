import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmod, copyFile, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import test from "node:test";

const sourceScript = resolve(import.meta.dirname, "../../../apps/windows-agent/scripts/publish-veil-agent-bundle.sh");
const requiredFiles = ["VeilAgent.exe", "VeilAgent.dll", "VeilAgent.deps.json", "VeilAgent.runtimeconfig.json"];
const shellOnly = { skip: process.platform === "win32" ? "Bash publisher runs on macOS/Linux" : false };

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "veil-publish-test-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const agent = join(root, "agent with spaces");
  const scripts = join(agent, "scripts");
  const bin = join(root, "bin");
  await mkdir(scripts, { recursive: true });
  await mkdir(bin);
  await mkdir(join(agent, "app"));
  await mkdir(join(agent, "app.previous"));
  await writeFile(join(agent, "app", "VeilAgent.exe"), "last known good");
  await writeFile(join(agent, "app", "old-only.txt"), "old dependency");
  await writeFile(join(agent, "app.previous", "VeilAgent.exe"), "earlier backup");
  const script = join(scripts, "publish-veil-agent-bundle.sh");
  await copyFile(sourceScript, script);
  // Only the external compiler is substituted. The actual publisher, files, moves, and exit status run.
  const dotnet = join(bin, "dotnet");
  await writeFile(dotnet, `#!${process.execPath}
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
const output = args[args.indexOf('--output') + 1];
if (args[0] !== 'publish' || !output) process.exit(91);
if (process.env.VEIL_TEST_ARGS) fs.writeFileSync(process.env.VEIL_TEST_ARGS, JSON.stringify(args));
fs.mkdirSync(output, { recursive: true });
const mode = process.env.VEIL_TEST_PUBLISH_MODE;
const files = ${JSON.stringify(requiredFiles)};
for (const file of files) {
  if (mode === 'missing-dll' && file === 'VeilAgent.dll') continue;
  fs.writeFileSync(path.join(output, file), mode === 'empty-exe' && file.endsWith('.exe') ? '' : 'new build');
}
if (mode === 'fail') process.exit(42);
if (mode === 'gated') {
  fs.writeFileSync(process.env.VEIL_TEST_STARTED, 'started');
  const timer = setInterval(() => {
    if (fs.existsSync(process.env.VEIL_TEST_RELEASE)) { clearInterval(timer); process.exit(0); }
  }, 10);
}
`);
  await chmod(dotnet, 0o755);
  function start(mode = "success", extraEnv = {}, extraArgs = []) {
    const child = spawn("/bin/bash", [script, "--dotnet", dotnet, ...extraArgs], {
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, VEIL_TEST_PUBLISH_MODE: mode, ...extraEnv },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    child.stdout.on("data", data => { output += data; });
    child.stderr.on("data", data => { output += data; });
    const done = new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("close", (code, signal) => resolve({ code, signal, output }));
    });
    return { child, done };
  }
  return { root, agent, bin, start };
}

async function assertOldBundle(agent) {
  assert.equal(await readFile(join(agent, "app", "VeilAgent.exe"), "utf8"), "last known good");
  assert.equal(await readFile(join(agent, "app", "old-only.txt"), "utf8"), "old dependency");
  assert.equal(await readFile(join(agent, "app.previous", "VeilAgent.exe"), "utf8"), "earlier backup");
}

async function assertNoScratch(agent) {
  assert.deepEqual((await readdir(agent)).filter(name => name.startsWith(".app-publish")), []);
}

test("failed compiler preserves the current bundle and backup", shellOnly, async t => {
  const { agent, start } = await fixture(t);
  const result = await start("fail").done;
  assert.equal(result.code, 42, result.output);
  await assertOldBundle(agent);
  await assertNoScratch(agent);
});

for (const mode of ["missing-dll", "empty-exe"]) {
  test(`incomplete compiler output (${mode}) cannot replace the current bundle`, shellOnly, async t => {
    const { agent, start } = await fixture(t);
    const result = await start(mode).done;
    assert.notEqual(result.code, 0, result.output);
    await assertOldBundle(agent);
    await assertNoScratch(agent);
  });
}

test("successful publish replaces the whole bundle and retains exactly the previous bundle", shellOnly, async t => {
  const { agent, start } = await fixture(t);
  const result = await start().done;
  assert.equal(result.code, 0, result.output);
  assert.deepEqual((await readdir(join(agent, "app"))).sort(), [...requiredFiles].sort());
  for (const file of requiredFiles) assert.equal(await readFile(join(agent, "app", file), "utf8"), "new build");
  assert.equal(await readFile(join(agent, "app.previous", "VeilAgent.exe"), "utf8"), "last known good");
  assert.equal(await readFile(join(agent, "app.previous", "old-only.txt"), "utf8"), "old dependency");
  await assertNoScratch(agent);
});

test("promotion failure rolls back the current bundle without changing its backup", shellOnly, async t => {
  const { agent, bin, start } = await fixture(t);
  const mover = join(bin, "mv");
  await writeFile(mover, `#!${process.execPath}
const { spawnSync } = require('node:child_process');
const args = process.argv.slice(2);
if (args.some(value => value.endsWith('/next'))) process.exit(73);
process.exit(spawnSync('/bin/mv', args, { stdio: 'inherit' }).status ?? 74);
`);
  await chmod(mover, 0o755);
  const result = await start().done;
  assert.notEqual(result.code, 0, result.output);
  await assertOldBundle(agent);
  await assertNoScratch(agent);
});

test("a concurrent publisher cannot disturb the in-flight build or current bundle", { ...shellOnly, timeout: 10_000 }, async t => {
  const { root, agent, start } = await fixture(t);
  const started = join(root, "started");
  const release = join(root, "release");
  const first = start("gated", { VEIL_TEST_STARTED: started, VEIL_TEST_RELEASE: release });
  try {
    let ready = false;
    for (let i = 0; i < 200; i += 1) {
      try { await readFile(started); ready = true; break; } catch { await delay(10); }
    }
    assert.ok(ready, "the compiler did not reach its controlled gate");
    const second = await start().done;
    assert.notEqual(second.code, 0, second.output);
    await assertOldBundle(agent);
  } finally {
    await writeFile(release, "continue");
    assert.equal((await first.done).code, 0);
  }
  await assertNoScratch(agent);
});

test("a symlink bundle target is refused without touching its destination", shellOnly, async t => {
  const { root, agent, start } = await fixture(t);
  const outside = join(root, "external");
  await mkdir(outside);
  await writeFile(join(outside, "sentinel"), "preserve");
  await rm(join(agent, "app"), { recursive: true });
  await symlink(outside, join(agent, "app"));
  const result = await start().done;
  assert.notEqual(result.code, 0, result.output);
  assert.equal(await readFile(join(outside, "sentinel"), "utf8"), "preserve");
  await assertNoScratch(agent);
});

test("failed rollback retains the complete old bundle at the reported recovery path", shellOnly, async t => {
  const { agent, bin, start } = await fixture(t);
  const mover = join(bin, "mv");
  await writeFile(mover, `#!${process.execPath}
const { spawnSync } = require('node:child_process');
const args = process.argv.slice(2);
if (args[0].endsWith('/next') || args[0].endsWith('/previous')) process.exit(73);
process.exit(spawnSync('/bin/mv', args, { stdio: 'inherit' }).status ?? 74);
`);
  await chmod(mover, 0o755);
  const result = await start().done;
  assert.notEqual(result.code, 0, result.output);
  const retained = (await readdir(agent)).filter(name => name.startsWith(".app-publish."));
  assert.equal(retained.length, 1, result.output);
  assert.notEqual(retained[0], ".app-publish.lock");
  const recovery = join(agent, retained[0], "previous");
  assert.ok(result.output.includes(recovery), result.output);
  assert.equal(await readFile(join(recovery, "VeilAgent.exe"), "utf8"), "last known good");
  assert.equal(await readFile(join(recovery, "old-only.txt"), "utf8"), "old dependency");
  assert.equal(await readFile(join(agent, "app.previous", "VeilAgent.exe"), "utf8"), "earlier backup");
});

test("first publish succeeds without inventing a previous bundle", shellOnly, async t => {
  const { agent, start } = await fixture(t);
  await rm(join(agent, "app"), { recursive: true });
  await rm(join(agent, "app.previous"), { recursive: true });
  const result = await start().done;
  assert.equal(result.code, 0, result.output);
  assert.deepEqual((await readdir(join(agent, "app"))).sort(), [...requiredFiles].sort());
  await assert.rejects(readFile(join(agent, "app.previous", "VeilAgent.exe")), { code: "ENOENT" });
  await assertNoScratch(agent);
});

test("a build id stamps the agent version and records it next to the bundle", shellOnly, async t => {
  const { root, agent, start } = await fixture(t);
  const argsPath = join(root, "publish-args.json");
  const result = await start("success", { VEIL_TEST_ARGS: argsPath }).done;
  assert.equal(result.code, 0, result.output);
  await assert.rejects(readFile(join(agent, "app", "veil-agent-version.txt"), "utf8"));
  assert.ok(!JSON.parse(await readFile(argsPath, "utf8"))
    .some(arg => arg.startsWith("-p:InformationalVersion=")));

  const stamped = await start("success", { VEIL_TEST_ARGS: argsPath }, ["--build-id", "abc123"]).done;
  assert.equal(stamped.code, 0, stamped.output);
  assert.equal(await readFile(join(agent, "app", "veil-agent-version.txt"), "utf8"), "0.1.0+abc123\n");
  assert.ok(JSON.parse(await readFile(argsPath, "utf8"))
    .includes("-p:InformationalVersion=0.1.0+abc123"));
});
