import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

const root = new URL("../../../", import.meta.url);
const readRootFile = (path) => readFile(new URL(path, root), "utf8");

test("installed Windows presents one responsive app-first home", async () => {
  const home = await readRootFile(
    "apps/mac-host/Sources/VeilHostShell/Views/InstalledWindowsAppHome.swift",
  );

  assert.match(home, /struct InstalledWindowsAppHome: View/);
  assert.match(home, /GeometryReader/);
  assert.match(home, /LazyVGrid/);
  assert.match(home, /GridItem\(\.adaptive/);
  assert.match(home, /Text\(presentation\.title\)/);
  assert.match(home, /Label\("Windows Desktop", systemImage: "display"\)/);
  assert.match(home, /\.accessibilityAddTraits\(\.isHeader\)/);
  assert.match(home, /\.accessibilityValue\(tilePresentation\.accessibilityValue\)/);
  assert.match(home, /Data\(base64Encoded:/);
  assert.doesNotMatch(home, /exePath|HWND|QEMU|protocol/);
});

test("installed Windows offers one consented optimization flow", async () => {
  const home = await readRootFile(
    "apps/mac-host/Sources/VeilHostShell/Views/InstalledWindowsAppHome.swift",
  );
  const runtime = await readRootFile(
    "apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift",
  );
  const presentation = await readRootFile(
    "apps/mac-host/Sources/VeilHostShell/App/InstalledAppHomePresentation.swift",
  );
  const coordinator = await readRootFile(
    "apps/mac-host/Sources/VeilHostShell/App/WindowsOptimizationCoordinator.swift",
  );

  assert.match(home, /optimizationPresentation/);
  assert.match(home, /ProgressView\(value: optimization\.progress\)/);
  assert.match(home, /optimizationPresentation == nil,[\s\S]*presentation\.recoveryTitle/);
  assert.doesNotMatch(home, /Repair App Connection/);
  assert.match(coordinator, /"Finish Windows Optimization"/);
  assert.match(coordinator, /"Optimize Windows"/);
  assert.match(coordinator, /"Try Again"/);
  assert.match(presentation, /UTM Guest Tools/);
  assert.match(presentation, /Veil guest agent/);
  assert.match(runtime, /\.alert\(WindowsOptimizationConsentPolicy\.title/);
  assert.match(runtime, /I Agree and Optimize|WindowsOptimizationConsentPolicy\.acceptButtonTitle/);
});

test("installed workspace does not auto-open or duplicate the Windows desktop", async () => {
  const detail = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/DetailView.swift");
  const runtime = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(detail, /showsWindowsDesktop = InstalledWorkspacePresentationPolicy\.initiallyShowsDesktop/);
  assert.match(runtime, /InstalledWindowsAppHome\(/);
  assert.match(runtime, /Label\("Show Apps", systemImage: "macwindow"\)/);
  assert.doesNotMatch(detail, /WindowsQuickLaunchPanel|WindowsQuickLaunchTile/);
  assert.doesNotMatch(runtime, /installedMachineContent|AppRuntimeProgressStrip|appOpenFlowItems/);
  assert.doesNotMatch(runtime, /showsFullDesktop = newState == \.running/);
  assert.doesNotMatch(runtime, /!hadDesktopDisplay[\s\S]*showsFullDesktop = true/);
});

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

test("first-run setup presents one focused edge-to-edge action", async () => {
  const runtime = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(runtime, /WindowsSetupCanvas\(/);

  const canvas = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/WindowsSetupCanvas.swift");
  assert.match(canvas, /struct WindowsSetupCanvas: View/);
  assert.match(canvas, /GeometryReader/);
  assert.match(canvas, /\.accessibilityAddTraits\(\.isHeader\)/);
  assert.match(canvas, /ProgressView\(value: progress\)/);
  assert.match(canvas, /Label\("Use Existing ISO", systemImage: "folder"\)/);
  assert.match(canvas, /\.accessibilityLabel\("Settings"\)/);
  assert.doesNotMatch(runtime, /SetupJourneyStep\(/);
  assert.doesNotMatch(runtime, /FirstRunTrustItem\(/);
  assert.doesNotMatch(runtime, /Mac app windows require QEMU or a configured endpoint/);
});

test("first-run setup reserves the bottom control bar for a live Windows display", async () => {
  const source = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(source, /if hasDesktopDisplay \{[\s\S]*installDisplaySurface[\s\S]*installControlBar[\s\S]*\} else \{[\s\S]*WindowsSetupCanvas\(/);
  assert.doesNotMatch(source, /private var firstRunSettingsButton/);
  assert.doesNotMatch(source, /private var firstRunCurrentStep/);
  assert.doesNotMatch(source, /private var firstRunTrustItems/);
});

test("window header communicates setup state and refresh progress", async () => {
  const content = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/ContentView.swift");
  const copy = await readRootFile("apps/mac-host/Sources/VeilHostShell/App/WindowsShellCopy.swift");

  assert.match(copy, /struct WindowsHeaderStatus: Equatable/);
  assert.match(copy, /title: "Setup Required", symbolName: "wand\.and\.stars", tone: \.blue/);
  assert.match(copy, /title: "Apps Ready", symbolName: "checkmark\.circle\.fill", tone: \.green/);
  assert.match(content, /private var headerStatus: WindowsHeaderStatus/);
  assert.match(content, /if isRefreshing \{[\s\S]*ProgressView\(\)/);
  assert.match(content, /\.accessibilityLabel\(isRefreshing \? "Refreshing Windows status" : "Refresh Windows status"\)/);
  assert.match(content, /\.accessibilityValue\(isRefreshing \? "In progress" : "Ready"\)/);
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

test("Windows setup assistant emphasizes one contextual action", async () => {
  const source = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(source, /enum SetupAssistantPrimaryAction[\s\S]*case prepareWindows[\s\S]*case chooseInstaller[\s\S]*case createDisk/);
  assert.match(source, /Label\("Advanced", systemImage: "ellipsis\.circle"\)/);
  assert.match(source, /\.accessibilityLabel\("Advanced setup options"\)/);
  assert.match(source, /Label\("Create Profile Only", systemImage: "rectangle\.stack\.badge\.plus"\)/);
  assert.match(source, /Text\("Next"\)/);
  assert.match(source, /title: "Windows Profile"/);
  assert.match(source, /title: "Windows Installer"/);
  assert.match(source, /title: "Windows Storage"/);
  assert.doesNotMatch(source, /Label\("Profile Only", systemImage: "plus\.circle"\)/);
});

test("Windows setup requires explicit combined consent for Windows and Guest Tools", async () => {
  const downloadSheet = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/WindowsDownloadSheet.swift");
  const runtimeView = await readRootFile("apps/mac-host/Sources/VeilHostShell/Views/VMRuntimeView.swift");

  assert.match(downloadSheet, /https:\/\/www\.microsoft\.com\/useterms/);
  assert.match(downloadSheet, /https:\/\/docs\.getutm\.app\/guest-support\/windows/);
  assert.match(downloadSheet, /Accept Windows and Guest Tools Terms\?/);
  assert.match(downloadSheet, /I Agree and Install Everything/);
  assert.match(downloadSheet, /UTM Guest Tools \(GPLv2 with the included Windows driver terms\)/);
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
  assert.match(source, /AUTOMATIC DOWNLOAD • STEP \\\(currentJourneyStepNumber\) OF/);
  assert.match(source, /Menu \{[\s\S]*Show Microsoft Page[\s\S]*Label\("Options", systemImage: "ellipsis\.circle"\)/);
  assert.match(source, /\.accessibilityLabel\("Download options"\)/);
  assert.match(source, /WindowsDownloadTrustItem\(title: "Microsoft source"/);
  assert.match(source, /WindowsDownloadTrustItem\(title: "SHA-256 verification"/);
  assert.match(source, /WindowsDownloadTrustItem\(title: "Saved locally"/);
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
