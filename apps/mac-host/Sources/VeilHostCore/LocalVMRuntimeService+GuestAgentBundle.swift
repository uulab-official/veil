import Foundation

extension LocalVMRuntimeService {
    static func prepareGuestAgentInstallerBundle(for profile: VMProfile) throws {
        let fileManager = FileManager.default
        let bundleURL = guestAgentInstallerBundleURL(for: profile)
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let sourceURL = GuestToolsBundle.sourceURL()
        try copyWindowsAgentSubdirectory(
            named: "scripts",
            from: sourceURL,
            to: bundleURL
        )
        try copyWindowsAgentSubdirectoryIfPresent(
            named: "app",
            from: sourceURL,
            to: bundleURL
        )
        try copyWindowsAgentSubdirectory(
            named: "src",
            from: sourceURL,
            to: bundleURL
        )
        try copyWindowsAgentSubdirectoryIfPresent(
            named: "package",
            from: sourceURL,
            to: bundleURL
        )

        try installAgentCommandText.write(
            to: bundleURL.appendingPathComponent("Install Veil Agent.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try startAgentCommandText.write(
            to: bundleURL.appendingPathComponent("Start Veil Agent.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try collectAgentDiagnosticsCommandText.write(
            to: bundleURL.appendingPathComponent("Collect Veil Agent Diagnostics.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try repairAgentConnectivityCommandText.write(
            to: bundleURL.appendingPathComponent("Repair Veil Agent Connectivity.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try prepareSparsePackageCommandText.write(
            to: bundleURL.appendingPathComponent("Prepare Sparse Package.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try sparsePackageBootstrapCommandText.write(
            to: bundleURL.appendingPathComponent("P.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try agentBootstrapCommandText.write(
            to: bundleURL.appendingPathComponent("V.cmd"),
            atomically: true,
            encoding: .utf8
        )
        try guestAgentReadmeText.write(
            to: bundleURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func copyWindowsAgentSubdirectory(named name: String, from sourceRootURL: URL, to bundleURL: URL) throws {
        let fileManager = FileManager.default
        let sourceURL = sourceRootURL.appendingPathComponent(name, isDirectory: true)
        let destinationURL = bundleURL.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw VMRuntimeError.automaticInstallMediaCreationFailed(
                "Windows agent source folder is missing at \(sourceURL.path)."
            )
        }

        if directoryContentsMatch(sourceURL, destinationURL) {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func copyWindowsAgentSubdirectoryIfPresent(named name: String, from sourceRootURL: URL, to bundleURL: URL) throws {
        let fileManager = FileManager.default
        let sourceURL = sourceRootURL.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return
        }

        let destinationURL = bundleURL.appendingPathComponent(name, isDirectory: true)
        if directoryContentsMatch(sourceURL, destinationURL) {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    struct DirectoryFileManifestEntry: Equatable {
        var relativePath: String
        var byteCount: Int?
        var modifiedAt: Date?
    }

    private static func directoryContentsMatch(_ sourceURL: URL, _ destinationURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              FileManager.default.fileExists(atPath: destinationURL.path) else {
            return false
        }

        return directoryFileManifest(for: sourceURL) == directoryFileManifest(for: destinationURL)
    }

    private static func directoryFileManifest(for directoryURL: URL) -> [DirectoryFileManifestEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { item -> DirectoryFileManifestEntry? in
                guard let url = item as? URL,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }

                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let relativePath = String(url.path.dropFirst(directoryURL.path.count + 1))
                return DirectoryFileManifestEntry(
                    relativePath: relativePath,
                    byteCount: values?.fileSize,
                    modifiedAt: values?.contentModificationDate
                )
            }
            .sorted { $0.relativePath < $1.relativePath }
    }

    /// The first-logon bootstrap sets VEIL_UNATTENDED, so a failure returns its exit code instead of
    /// waiting at `pause` in a minimized window nobody sees.
    private static let installAgentCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Install-VeilAgent.ps1" %*
    set VEIL_EXIT_CODE=%errorlevel%
    if not "%VEIL_EXIT_CODE%"=="0" if not defined VEIL_UNATTENDED pause
    exit /b %VEIL_EXIT_CODE%

    """

    private static let startAgentCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Start-VeilAgent.ps1" %*
    if errorlevel 1 pause

    """

    private static let collectAgentDiagnosticsCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Collect-VeilAgentDiagnostics.ps1" %*
    if errorlevel 1 pause

    """

    private static let repairAgentConnectivityCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Repair-VeilAgentConnectivity.ps1" %*
    if errorlevel 1 pause

    """

    private static let prepareSparsePackageCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    set "VEIL_SPARSE_PACKAGE_ROOT=%LOCALAPPDATA%\\Veil\\Agent\\package"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\\Build-VeilAgentSparsePackage.ps1" -OutputRoot "%VEIL_SPARSE_PACKAGE_ROOT%" -StatusPath "%VEIL_SPARSE_PACKAGE_ROOT%\\sparse-package-status.json" -CreateDevelopmentCertificate -TrustDevelopmentCertificate
    if errorlevel 1 (
        set VEIL_EXIT_CODE=%errorlevel%
        pause
        exit /b %VEIL_EXIT_CODE%
    )
    call "%~dp0Install Veil Agent.cmd" -SparsePackagePath "%VEIL_SPARSE_PACKAGE_ROOT%\\VeilAgent.Identity.msix" -SparsePackageCertificatePath "%VEIL_SPARSE_PACKAGE_ROOT%\\VeilAgent.Identity.cer" -RequirePackageIdentity %*
    if errorlevel 1 pause

    """

    private static let sparsePackageBootstrapCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    if "%VEIL_AGENT_AUTOMATION_HOLD%"=="" set VEIL_AGENT_AUTOMATION_HOLD=75
    call "%~dp0Prepare Sparse Package.cmd" %*
    set VEIL_EXIT_CODE=%errorlevel%
    if not "%VEIL_AGENT_AUTOMATION_HOLD%"=="0" (
        echo.
        echo Veil sparse package status will remain visible for %VEIL_AGENT_AUTOMATION_HOLD% seconds.
        timeout /t %VEIL_AGENT_AUTOMATION_HOLD% /nobreak >nul
    )
    exit /b %VEIL_EXIT_CODE%

    """

    private static let agentBootstrapCommandText = """
    @echo off
    setlocal
    cd /d "%~dp0"
    if "%VEIL_AGENT_AUTOMATION_HOLD%"=="" set VEIL_AGENT_AUTOMATION_HOLD=75
    if exist "%~dp0Repair Veil Agent Connectivity.cmd" (
        call "%~dp0Repair Veil Agent Connectivity.cmd" %*
        goto veil_after_agent_command
    )
    call "%~dp0Install Veil Agent.cmd" %*
    :veil_after_agent_command
    set VEIL_EXIT_CODE=%errorlevel%
    if "%VEIL_EXIT_CODE%"=="0" exit /b 0
    if not "%VEIL_AGENT_AUTOMATION_HOLD%"=="0" (
        echo.
        echo Veil automation status will remain visible for %VEIL_AGENT_AUTOMATION_HOLD% seconds.
        timeout /t %VEIL_AGENT_AUTOMATION_HOLD% /nobreak >nul
    )
    exit /b %VEIL_EXIT_CODE%

    """

    private static let guestAgentReadmeText = """
    Veil Guest Agent

    Run Install Veil Agent.cmd after Windows 11 reaches the desktop.
    V.cmd is the short automation entrypoint used by the macOS host. It runs Repair Veil Agent Connectivity.cmd when present, falls back to Install Veil Agent.cmd for older media layouts, and, when it fails, keeps the console visible briefly so macOS post-attempt screenshots can capture the failure text. A success closes the console at once, since the agent's health reply already proves it.
    P.cmd is the short sparse-package automation entrypoint used by veil-vmctl qemu-prepare-sparse-package. It runs Prepare Sparse Package.cmd and keeps the console visible briefly so package identity status is visible in post-attempt screenshots.
    The installer uses the packaged VeilAgent.exe bundle when present, registers the VeilAgent user logon task when Windows allows it, and listens inside Windows on 0.0.0.0:18444 so the macOS host can connect through QEMU at ws://127.0.0.1:18444/.
    Bootstrap and installer logs are written under %LOCALAPPDATA%\\Veil\\Agent\\logs.
    If this media does not include app\\VeilAgent.exe, build it on the Mac with apps/windows-agent/scripts/publish-veil-agent-bundle.sh before preparing the VM again.

    Run Start Veil Agent.cmd to start the agent immediately after installation.
    Run Prepare Sparse Package.cmd to build a local development identity package in %LOCALAPPDATA%\\Veil\\Agent\\package and reinstall the agent with package identity. This writes sparse-package-status.json next to the generated package without storing certificate passwords. This requires the Windows SDK inside the guest; if it succeeds, agent.health.response.capabilities.packageIdentity should become true after the agent restarts.
    Run Repair Veil Agent Connectivity.cmd when macOS can open QEMU port 18444 but the agent health check still times out. The repair path requests administrator approval, refreshes Windows Firewall rules, restarts VeilAgent, and writes repair-status.json when the in-guest loopback plus guest IPv4 agent.health.response probes succeed or fail.
    Run Collect Veil Agent Diagnostics.cmd to write a metadata-only diagnostics ZIP to the Windows desktop when install, start, or connection checks fail.
    Keep this folder in the Veil Shared drive while Veil is in pre-alpha.

    """
}
