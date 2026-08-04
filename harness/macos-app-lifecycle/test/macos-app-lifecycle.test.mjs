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

test("first-run hero presents one clear setup journey without runtime jargon", async () => {
  const source = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(source, /\.accessibilityLabel\(effectivePrimaryTitle\)/);
  assert.match(source, /\.accessibilityHint\(effectivePrimaryHelp\)/);
  assert.match(source, /Windows apps, right on your Mac/);
  assert.match(source, /SetupJourneyStep\(number: 1, title: "Get Windows"/);
  assert.match(source, /SetupJourneyStep\(number: 2, title: "Install"/);
  assert.match(source, /SetupJourneyStep\(number: 3, title: "Open Apps"/);
  assert.match(source, /Button\("Use an Existing ISO", action: selectInstallerAction\)/);
  assert.doesNotMatch(source, /Mac app windows require QEMU or a configured endpoint/);
});

test("first-run setup removes the redundant bottom bar while keeping settings available", async () => {
  const source = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(source, /if shouldShowInstallControlBar \{[\s\S]*installControlBar/);
  assert.match(source, /private var shouldShowInstallControlBar: Bool/);
  assert.match(source, /ZStack\(alignment: \.topTrailing\)[\s\S]*firstRunSettingsButton/);
  assert.match(source, /private var firstRunSettingsButton: some View[\s\S]*Button\(action: detailsAction\)/);
  assert.match(source, /\.accessibilityLabel\("Settings"\)/);
});

test("Windows settings separates setup, runtime, and integration controls", async () => {
  const settings = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMSettingsSheet.swift");
  const runtime = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(settings, /enum VMSettingsSection[\s\S]*case setup[\s\S]*case runtime[\s\S]*case integration/);
  assert.match(settings, /Picker\("Settings Section", selection: \$selectedSection\)/);
  assert.match(settings, /\.pickerStyle\(\.segmented\)/);
  assert.match(settings, /\.labelsHidden\(\)/);
  assert.match(settings, /\.accessibilityLabel\("Settings Section"\)/);
  assert.match(settings, /selectedContent\(snapshot, policy: policy\)/);
  assert.match(runtime, /runtimeContent:[\s\S]*runtimeSettingsColumn/);
  assert.match(runtime, /integrationContent:[\s\S]*integrationSettingsColumn/);
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

test("Windows download occupies the main content area instead of a nested sheet", async () => {
  const downloadScreen = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/WindowsDownloadSheet.swift");
  const runtimeView = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");
  const settingsSheet = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMSettingsSheet.swift");

  assert.match(downloadScreen, /struct WindowsDownloadScreen: View/);
  assert.match(downloadScreen, /Image\(systemName: "chevron\.left"\)/);
  assert.match(downloadScreen, /\.accessibilityLabel\("Back"\)/);
  assert.match(downloadScreen, /\.frame\(maxWidth: \.infinity, maxHeight: \.infinity\)/);
  assert.doesNotMatch(downloadScreen, /@Environment\(\\\.dismiss\)/);
  assert.doesNotMatch(downloadScreen, /\.frame\(minWidth: 820, minHeight: 560\)/);
  assert.match(runtimeView, /VMRuntimeContentRoute/);
  assert.match(runtimeView, /case \.windowsDownload:[\s\S]*WindowsDownloadScreen/);
  assert.doesNotMatch(settingsSheet, /case windowsDownload/);
});

test("Windows download communicates its staged progress and source", async () => {
  const source = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/WindowsDownloadSheet.swift");

  assert.match(source, /WindowsDownloadJourney\(items: journeyItems\)/);
  assert.match(source, /\("Find", "magnifyingglass"\)/);
  assert.match(source, /\("Download", "arrow\.down"\)/);
  assert.match(source, /\("Verify", "checkmark\.shield"\)/);
  assert.match(source, /\("Prepare", "internaldrive"\)/);
  assert.match(source, /Text\("\\\(Int\(progress \* 100\)\)%"\)/);
  assert.match(source, /Secure download from microsoft\.com • Saved only on this Mac/);
});

test("Windows download offers direct cancel and recovery actions", async () => {
  const source = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/WindowsDownloadSheet.swift");

  assert.match(source, /Button\("Cancel"\)[\s\S]*controller\.cancelDownload\(\)[\s\S]*closeAction\(\)/);
  assert.match(source, /Button\("Try Download Again", action: retryDownload\)/);
  assert.match(source, /Button\("Try Preparing Again"\)/);
  assert.match(source, /private func retryDownload\(\)[\s\S]*controller\.reloadLandingPage\(\)/);
});

test("Windows setup enters native macOS full screen without toggling an existing full-screen window", async () => {
  const runtimeView = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");
  const appSource = await readRootFile("apps/mac-host/Sources/VeilHostShell/App/VeilHostShellApp.swift");

  assert.match(runtimeView, /route == \.windowsDownload[\s\S]*MainWindowChrome\.enterFullScreen\(\)/);
  assert.match(appSource, /MainWindowFullscreenPolicy\.shouldRequestFullScreen/);
  assert.match(appSource, /window\.collectionBehavior\.insert\(\.fullScreenPrimary\)/);
  assert.match(appSource, /window\.toggleFullScreen\(nil\)/);
  assert.ok((appSource.match(/MainWindowChrome\.enterFullScreen\(\)/g) ?? []).length >= 2);
});
