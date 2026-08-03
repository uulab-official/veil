import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const root = new URL("../../../", import.meta.url);
const readRootFile = (path) => readFile(new URL(path, root), "utf8");

test("installer validates identity and signature before replacing an app", async () => {
  const source = await readRootFile("script/install_macos.sh");

  assert.match(source, /org\.uulab\.veil\.host-shell/);
  assert.match(source, /codesign --verify --deep --strict/);
  assert.match(source, /Destination already exists/);
  assert.match(source, /validate_veil_bundle \"\$DESTINATION_APP\" \"Existing destination\"/);
  assert.match(source, /\.installing\.\$\$/);
  assert.match(source, /\.backup\.\$\$/);
});

test("uninstaller moves only the verified app bundle to a recoverable trash target", async () => {
  const source = await readRootFile("script/uninstall_macos.sh");

  assert.match(source, /Refusing to move bundle/);
  assert.match(source, /mv \"\$DESTINATION_APP\" \"\$TRASH_APP\"/);
  assert.doesNotMatch(source, /rm -rf/);
  assert.doesNotMatch(source, /default-vm-profile|Virtual Machines|Windows 11 Arm\.img/);
  assert.match(source, /user data was preserved/i);
});

test("lifecycle gate covers install, guarded replace, uninstall, preservation, and reinstall", async () => {
  const source = await readRootFile("script/test_macos_lifecycle.sh");
  const gate = await readRootFile("script/test_all.sh");

  assert.match(source, /install_macos\.sh/);
  assert.match(source, /--replace/);
  assert.match(source, /uninstall_macos\.sh/);
  assert.match(source, /SUPPORT_SENTINEL/);
  assert.match(source, /com\.example\.foreign/);
  assert.ok(source.match(/install_macos\.sh/g)?.length >= 3);
  assert.match(source, /CFFIXED_USER_HOME/);
  assert.match(source, /meetsLauncherContract/);
  assert.match(gate, /test_macos_lifecycle\.sh\" --skip-build/);
});

test("first-run hero exposes a named action and unambiguous compatibility copy", async () => {
  const source = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(source, /\.accessibilityLabel\(effectivePrimaryTitle\)/);
  assert.match(source, /\.accessibilityHint\(effectivePrimaryHelp\)/);
  assert.match(source, /Apple Virtualization compatibility mode/);
  assert.match(source, /Windows setup is available • Mac app windows require QEMU/);
  assert.doesNotMatch(source, /Console available • Windows app integration needs QEMU/);
});
