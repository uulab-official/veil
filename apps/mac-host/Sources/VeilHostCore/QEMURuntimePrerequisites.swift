import Foundation

public struct QEMURuntimePrerequisite: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var isReady: Bool
    public var detail: String
}

public struct QEMURuntimePrerequisiteReport: Equatable, Sendable {
    public static let installCommand = "brew install qemu swtpm"
    public var checks: [QEMURuntimePrerequisite]
    public var isReady: Bool { checks.allSatisfy(\.isReady) }

    public static func probe(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> Self {
        let qemu = overrideCandidate(environment[VMRuntimeProviderProbe.qemuEnvironmentKey])
            + VMRuntimeProviderProbe.qemuExecutablePaths(homeDirectory: homeDirectory)
        let firmware = LocalQEMUWindowsBootPlanFactory.defaultSecureFirmwarePaths()
            + LocalQEMUWindowsBootPlanFactory.defaultFirmwarePaths
        let swtpm = overrideCandidate(environment[LocalQEMUWindowsBootPlanFactory.tpmEmulatorEnvironmentKey])
            + LocalQEMUWindowsBootPlanFactory.tpmEmulatorPaths(homeDirectory: homeDirectory)
        return QEMURuntimePrerequisiteReport(checks: [
            check(id: "qemu", title: "QEMU Arm runtime", candidates: qemu, missing: "Install the QEMU formula." , fileExists: fileExists),
            check(id: "uefi", title: "Arm UEFI firmware", candidates: firmware, missing: "QEMU is installed but Arm UEFI firmware was not found.", fileExists: fileExists),
            check(id: "swtpm", title: "Windows 11 TPM", candidates: swtpm, missing: "Install swtpm for Windows 11 TPM 2.0.", fileExists: fileExists)
        ])
    }

    private static func overrideCandidate(_ path: String?) -> [String] {
        guard let path, !path.isEmpty else { return [] }
        return [path]
    }

    private static func check(id: String, title: String, candidates: [String], missing: String, fileExists: (String) -> Bool) -> QEMURuntimePrerequisite {
        let path = candidates.first(where: fileExists)
        return QEMURuntimePrerequisite(id: id, title: title, isReady: path != nil, detail: path ?? missing)
    }
}
