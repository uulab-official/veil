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
  assert.match(source, /xattr -w com\.apple\.quarantine/);
  assert.match(source, /Installer left quarantine metadata/);
  assert.ok(source.match(/uninstall_macos\.sh/g)?.length >= 2);
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

test("Windows setup requires explicit license consent for downloaded and selected ISOs", async () => {
  const downloadSheet = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/WindowsDownloadSheet.swift");
  const runtimeView = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(downloadSheet, /https:\/\/www\.microsoft\.com\/useterms/);
  assert.match(downloadSheet, /I Agree and Install Windows/);
  assert.match(downloadSheet, /Review and Prepare Windows/);
  assert.match(downloadSheet, /\.alert\(WindowsLicenseConsentPolicy\.title/);
  assert.doesNotMatch(downloadSheet, /\.onChange\(of: controller\.phase\)[\s\S]*prepareDownloadedISO/);
  assert.match(runtimeView, /pendingInstallerConsent = \.selected/);
  assert.match(runtimeView, /\.alert\(WindowsLicenseConsentPolicy\.title/);
  assert.match(runtimeView, /prepareAcceptedInstallation/);
  assert.match(runtimeView, /snapshot\.windowsInstalled[\s\S]*pendingInstallerConsent = \.prepared/);

  const appSource = await readRootFile("apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift");
  assert.match(appSource, /startWindowsFromMenuAction/);
  assert.match(appSource, /guard vmModel\.snapshot\?\.windowsInstalled == true/);
});
