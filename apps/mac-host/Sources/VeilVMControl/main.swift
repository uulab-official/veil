import Foundation
import VeilHostCore

enum VMControlError: Error, LocalizedError {
    case missingCommand
    case unsupportedCommand(String)
    case missingInstallerPath
    case installerNotFound(String)
    case missingProfileForQEMUPlan

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            Self.usage
        case .unsupportedCommand(let command):
            "Unsupported command '\(command)'. \(Self.usage)"
        case .missingInstallerPath:
            "Missing installer path. \(Self.usage)"
        case .installerNotFound(let path):
            "Installer file does not exist: \(path)"
        case .missingProfileForQEMUPlan:
            "No prepared VM profile found. Run veil-vmctl prepare --installer /path/to/Windows.iso first."
        }
    }

    private static let usage = "Usage: veil-vmctl prepare --installer /path/to/Windows.iso | veil-vmctl providers [--json] | veil-vmctl qemu-plan [--json] | veil-vmctl qemu-doctor [--json]"
}

struct VMControlArguments {
    enum Command: Equatable {
        case prepare(installerPath: String)
        case providers(json: Bool)
        case qemuPlan(json: Bool)
        case qemuDoctor(json: Bool)
    }

    var command: Command

    static func parse(_ arguments: [String]) throws -> VMControlArguments {
        guard let command = arguments.first else {
            throw VMControlError.missingCommand
        }

        if command == "providers" {
            return VMControlArguments(command: .providers(json: arguments.contains("--json")))
        }

        if command == "qemu-plan" {
            return VMControlArguments(command: .qemuPlan(json: arguments.contains("--json")))
        }

        if command == "qemu-doctor" {
            return VMControlArguments(command: .qemuDoctor(json: arguments.contains("--json")))
        }

        guard command == "prepare" else {
            throw VMControlError.unsupportedCommand(command)
        }

        guard let installerFlagIndex = arguments.firstIndex(of: "--installer"),
              arguments.indices.contains(installerFlagIndex + 1) else {
            throw VMControlError.missingInstallerPath
        }

        return VMControlArguments(command: .prepare(installerPath: arguments[installerFlagIndex + 1]))
    }
}

@main
struct VeilVMControl {
    static func main() async {
        do {
            let arguments = try VMControlArguments.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(arguments)
        } catch {
            let message: String
            if let localized = error as? LocalizedError,
               let description = localized.errorDescription {
                message = description
            } else {
                message = String(describing: error)
            }

            FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: VMControlArguments) async throws {
        switch arguments.command {
        case .prepare(let installerPath):
            try await prepare(installerPath: installerPath)
        case .providers(let json):
            try printProviders(json: json)
        case .qemuPlan(let json):
            try await printQEMUPlan(json: json)
        case .qemuDoctor(let json):
            try await printQEMUDoctor(json: json)
        }
    }

    private static func prepare(installerPath: String) async throws {
        let installerURL = URL(fileURLWithPath: installerPath)
        guard FileManager.default.fileExists(atPath: installerURL.path) else {
            throw VMControlError.installerNotFound(installerURL.path)
        }

        let service = LocalVMRuntimeService()
        let preparedSnapshot = try await service.prepareDefaultVM()
        let configuredSnapshot = try await service.updateProfilePaths(
            installerMediaPath: installerURL.path,
            virtualDiskPath: preparedSnapshot.virtualDiskPath
        )
        let diagnosticsURL = try await service.exportDiagnostics(to: diagnosticsDirectory())
        let profile = try await JSONVMProfileStore().load()

        print("Veil VM prepared")
        print("Profile: \(configuredSnapshot.profileName ?? "Not configured")")
        print("Installer: \(configuredSnapshot.installerMediaPath ?? "Not selected")")
        print("Virtual disk: \(configuredSnapshot.virtualDiskPath ?? "Not selected")")
        print("Shared folder: \(profile?.sharedFolderPath ?? "Not configured")")
        print("Boot ready: \(configuredSnapshot.bootReady ? "yes" : "no")")
        print("Detail: \(configuredSnapshot.detail)")
        print("Diagnostics: \(diagnosticsURL.path)")
    }

    private static func printProviders(json: Bool) throws {
        let architecture = hostArchitecture()
        let minimumOSSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        let providers = VMRuntimeProviderProbe().localProviders(
            architecture: architecture,
            minimumOSSupported: minimumOSSupported
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(providers)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        for provider in providers {
            let pathSuffix = provider.executablePath.map { " at \($0)" } ?? ""
            print("\(provider.displayName): \(provider.status.rawValue), \(provider.mode), \(provider.acceleration)\(pathSuffix)")
            print("  \(provider.detail)")
        }
    }

    private static func printQEMUPlan(json: Bool) async throws {
        guard let profile = try await JSONVMProfileStore().load() else {
            throw VMControlError.missingProfileForQEMUPlan
        }

        let plan = try makeQEMUPlan(for: profile)

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(plan)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print(plan.summary)
        print("\(plan.executablePath) \(plan.arguments.map(shellQuoted).joined(separator: " "))")
        if !plan.warnings.isEmpty {
            print("Warnings:")
            for warning in plan.warnings {
                print("  - \(warning)")
            }
        }
    }

    private static func printQEMUDoctor(json: Bool) async throws {
        let profile = try await JSONVMProfileStore().load()
        let plan = try? profile.map(makeQEMUPlan(for:))
        let report = QEMUWindowsReadinessDoctor().makeReport(
            profile: profile,
            plan: plan
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(report)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("QEMU/HVF readiness: \(report.overallState.rawValue)")
        for check in report.checks {
            print("\(check.title): \(check.state.rawValue)")
            print("  \(check.detail)")
        }
        print("Next actions:")
        for action in report.nextActions {
            print("  - \(action)")
        }
    }

    private static func makeQEMUPlan(for profile: VMProfile) throws -> QEMUWindowsBootPlan {
        let qemuProvider = VMRuntimeProviderProbe()
            .localProviders(
                architecture: hostArchitecture(),
                minimumOSSupported: ProcessInfo.processInfo.isOperatingSystemAtLeast(
                    OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
                )
            )
            .first { $0.kind == .qemuHypervisor }
        let executablePath = qemuProvider?.executablePath
            ?? VMRuntimeProviderProbe.defaultQEMUExecutablePaths[0]
        let firmwarePath = qemuFirmwarePath()
        let planner = QEMUWindowsBootPlanner(
            executablePath: executablePath,
            isExecutableAvailable: qemuProvider?.status == .active && qemuProvider?.executablePath != nil,
            firmwarePath: firmwarePath ?? defaultQEMUFirmwarePaths[0],
            isFirmwareAvailable: firmwarePath != nil
        )
        return try planner.makePlan(for: profile)
    }

    private static var defaultQEMUFirmwarePaths: [String] {
        [
            "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            "/usr/local/share/qemu/edk2-aarch64-code.fd",
            "/opt/local/share/qemu/edk2-aarch64-code.fd"
        ]
    }

    private static func qemuFirmwarePath() -> String? {
        let fileManager = FileManager.default
        return defaultQEMUFirmwarePaths.first { fileManager.fileExists(atPath: $0) }
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func hostArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func diagnosticsDirectory() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return downloads.appendingPathComponent("Veil Diagnostics", isDirectory: true)
    }

}
