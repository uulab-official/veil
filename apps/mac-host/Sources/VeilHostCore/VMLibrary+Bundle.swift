import Foundation

/// `veilvm.json` at the root of a `.veilvm` bundle. The format is documented in docs/vm-library.md.
public struct VMBundleManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public static let fileName = "veilvm.json"
    public static let bundleExtension = "veilvm"
    public static let diskFileName = "Disk.img"
    public static let firmwareVariablesFileName = "uefi-vars.fd"
    public static let tpmDirectoryName = "tpm"

    public var formatVersion: Int
    public var exportedAt: Date
    /// Host paths (installer, driver ISO, shared folder, disk) and bookmarks are removed on export:
    /// they point into the exporting Mac and would leak its user name.
    public var profile: VMProfile
    /// Bundle-relative names; nil when the machine had no such file.
    public var disk: String?
    public var firmwareVariables: String?
    public var tpmState: String?

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        exportedAt: Date,
        profile: VMProfile,
        disk: String?,
        firmwareVariables: String?,
        tpmState: String?
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.profile = profile
        self.disk = disk
        self.firmwareVariables = firmwareVariables
        self.tpmState = tpmState
    }
}

/// Disk image formats `qemu-img convert` reads, keyed by file extension.
public enum VMImportedDiskFormat: String, CaseIterable, Sendable {
    case raw
    case qcow2
    case vmdk
    case vhdx
    case vpc

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "img", "raw", "bin": self = .raw
        case "qcow2", "qcow": self = .qcow2
        case "vmdk": self = .vmdk
        case "vhdx": self = .vhdx
        case "vhd": self = .vpc
        default: return nil
        }
    }

    public static let fileExtensions = ["vhdx", "vhd", "vmdk", "qcow2", "qcow", "img", "raw"]
}

extension VMLibrary {
    // MARK: - Export

    /// Writes `<destination>` as a `.veilvm` folder. Disk and variables are APFS clones when the
    /// destination is on the same volume, so exporting next to the machine costs no space.
    public func exportMachine(id: String, to destination: URL) throws {
        let source = try machine(id: id)
        try requireStopped(source)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VMLibraryError.bundleDestinationExists(destination.path)
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            var manifest = VMBundleManifest(
                exportedAt: now(),
                profile: Self.portableProfile(source.profile),
                disk: nil,
                firmwareVariables: nil,
                tpmState: nil
            )
            if let diskPath = source.profile.virtualDiskPath, !diskPath.isEmpty {
                let disk = URL(fileURLWithPath: diskPath)
                try Self.cloneFile(from: disk, to: destination.appendingPathComponent(VMBundleManifest.diskFileName))
                manifest.disk = VMBundleManifest.diskFileName

                let directory = disk.deletingLastPathComponent()
                let vars = directory.appendingPathComponent("uefi-vars.fd")
                if FileManager.default.fileExists(atPath: vars.path) {
                    try Self.cloneFile(from: vars, to: destination.appendingPathComponent(VMBundleManifest.firmwareVariablesFileName))
                    manifest.firmwareVariables = VMBundleManifest.firmwareVariablesFileName
                }
                let tpm = directory.appendingPathComponent("tpm", isDirectory: true)
                if FileManager.default.fileExists(atPath: tpm.path) {
                    try FileManager.default.copyItem(at: tpm, to: destination.appendingPathComponent(VMBundleManifest.tpmDirectoryName, isDirectory: true))
                    manifest.tpmState = VMBundleManifest.tpmDirectoryName
                }
            }
            try JSONEncoder.veilDiagnostics.encode(manifest)
                .write(to: destination.appendingPathComponent(VMBundleManifest.fileName), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func portableProfile(_ profile: VMProfile) -> VMProfile {
        var portable = profile.withoutSecurityScopedBookmarks()
        portable.installerMediaPath = nil
        portable.driverMediaPath = nil
        portable.virtualDiskPath = nil
        portable.sharedFolderPath = ""
        portable.guestAgentConnectedAt = nil
        return portable
    }

    // MARK: - Import a bundle

    /// Adds a machine from a `.veilvm` bundle under a new id. The bundle is untrusted: every file
    /// it names must be a plain entry at its root, and its resources are clamped to this Mac.
    @discardableResult
    public func importBundle(
        from bundle: URL,
        limits: VMResourceLimits = .currentHost(),
        select: Bool = true
    ) throws -> VMProfile {
        let manifestURL = bundle.appendingPathComponent(VMBundleManifest.fileName)
        let manifest: VMBundleManifest
        do {
            manifest = try JSONDecoder.veilDiagnostics.decode(VMBundleManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw VMLibraryError.bundleUnreadable(error.localizedDescription)
        }
        guard manifest.formatVersion == VMBundleManifest.currentFormatVersion else {
            throw VMLibraryError.bundleUnsupportedVersion(manifest.formatVersion)
        }
        let disk = try manifest.disk.map { try Self.bundleEntry($0, in: bundle, directory: false) }
        let vars = try manifest.firmwareVariables.map { try Self.bundleEntry($0, in: bundle, directory: false) }
        let tpm = try manifest.tpmState.map { try Self.bundleEntry($0, in: bundle, directory: true) }

        let id = makeID()
        let destination = defaultMachineDirectory(for: id)
        var profile = Self.importedProfile(manifest.profile, id: id, homeDirectory: homeDirectory, limits: limits)
        profile.name = try uniqueName(Self.validatedName(manifest.profile.name))
        profile.createdAt = now()

        if let disk {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            do {
                let diskURL = destination.appendingPathComponent(Self.defaultDiskFileName)
                try Self.cloneFile(from: disk, to: diskURL)
                if let vars {
                    try Self.cloneFile(from: vars, to: destination.appendingPathComponent("uefi-vars.fd"))
                }
                if let tpm {
                    try FileManager.default.copyItem(at: tpm, to: destination.appendingPathComponent("tpm", isDirectory: true))
                }
                profile.virtualDiskPath = diskURL.path
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        try saveProfile(profile, id: id)
        try register(id, select: select)
        return profile
    }

    static func importedProfile(_ source: VMProfile, id: String, homeDirectory: URL, limits: VMResourceLimits) -> VMProfile {
        var profile = portableProfile(source)
        let defaults = VMProfile.defaultWindows11Arm(homeDirectory: homeDirectory)
        profile.id = id
        profile.os = defaults.os
        profile.sharedFolderPath = defaults.sharedFolderPath
        profile.cpuCount = limits.clampedCPUCount(profile.cpuCount)
        profile.memoryMB = limits.clampedMemoryMB(profile.memoryMB)
        profile.diskGB = max(1, profile.diskGB)
        profile.windowsAccountName = profile.windowsAccountName.flatMap(WindowsAccountName.sanitized)
        return profile
    }

    /// Resolves a manifest name to a regular file or folder directly inside the bundle. Symlinks
    /// and nested paths are refused so a crafted bundle cannot make Veil copy host files.
    static func bundleEntry(_ name: String, in bundle: URL, directory: Bool) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw VMLibraryError.bundleUnsafePath(name)
        }
        let url = bundle.appendingPathComponent(name, isDirectory: directory)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard let values, values.isSymbolicLink != true else {
            throw VMLibraryError.bundleUnsafePath(name)
        }
        if directory {
            guard values.isDirectory == true else {
                throw VMLibraryError.bundleUnsafePath(name)
            }
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey])
            while let child = enumerator?.nextObject() as? URL {
                if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                    throw VMLibraryError.bundleUnsafePath("\(name)/\(child.lastPathComponent)")
                }
            }
        } else {
            guard values.isRegularFile == true else {
                throw VMLibraryError.bundleUnsafePath(name)
            }
        }
        return url
    }

    // MARK: - Import a foreign disk

    /// Adds a machine around an existing Windows 11 Arm disk from Hyper-V, VMware, UTM, or another
    /// QEMU. The disk is converted to the raw image Veil boots; the source file is only read.
    /// UEFI variables and TPM state are created fresh by the next prepare step, so Windows boots
    /// through its fallback loader and BitLocker-protected disks ask for their recovery key.
    @discardableResult
    public func importDisk(
        from source: URL,
        name: String? = nil,
        converter: VMDiskConverter = VMDiskConverter(),
        resourcePlan: VMResourcePlan = VMResourcePolicy.currentHostPlan(),
        select: Bool = true
    ) throws -> VMProfile {
        guard let format = VMImportedDiskFormat(fileExtension: source.pathExtension) else {
            throw VMLibraryError.unsupportedDiskFormat(source.pathExtension)
        }
        let id = makeID()
        let destination = defaultMachineDirectory(for: id)
        let diskURL = destination.appendingPathComponent(Self.defaultDiskFileName)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            if format == .raw {
                try Self.cloneFile(from: source, to: diskURL)
            } else {
                try converter.convert(source: source, format: format, toRaw: diskURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        var profile = VMProfile.defaultWindows11Arm(createdAt: now(), homeDirectory: homeDirectory)
        profile.id = id
        profile.name = try uniqueName(Self.validatedName(name ?? source.deletingPathExtension().lastPathComponent))
        profile.cpuCount = resourcePlan.cpuCount
        profile.memoryMB = resourcePlan.memoryMB
        let bytes = (try? diskURL.resourceValues(forKeys: [URLResourceKey.fileSizeKey]))?.fileSize ?? 0
        profile.diskGB = max(1, Int((Double(bytes) / 1_073_741_824).rounded(.up)))
        profile.virtualDiskPath = diskURL.path
        profile.windowsInstalled = true
        try saveProfile(profile, id: id)
        try register(id, select: select)
        return profile
    }
}

/// Runs `qemu-img convert` to turn a foreign disk into a raw image.
///
/// `qemu-img` is looked up next to every `qemu-system-aarch64` Veil knows about: the app bundle
/// (which ships it with the engine), `~/Library/Application Support/Veil/Runtime`, then Homebrew and
/// MacPorts prefixes.
public struct VMDiskConverter: Sendable {
    public var candidatePaths: [String]
    public var run: @Sendable (_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String)

    public init(
        candidatePaths: [String] = VMDiskConverter.defaultCandidatePaths(),
        run: @escaping @Sendable (_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) = VMDiskConverter.runProcess
    ) {
        self.candidatePaths = candidatePaths
        self.run = run
    }

    public static func defaultCandidatePaths() -> [String] {
        VMRuntimeProviderProbe.qemuExecutablePaths().map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().appendingPathComponent("qemu-img").path
        }
    }

    public var executablePath: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func arguments(source: URL, format: VMImportedDiskFormat, destination: URL) -> [String] {
        ["convert", "-f", format.rawValue, "-O", "raw", source.path, destination.path]
    }

    public func convert(source: URL, format: VMImportedDiskFormat, toRaw destination: URL) throws {
        guard let executablePath else {
            throw VMLibraryError.diskConverterMissing
        }
        let result = try run(executablePath, Self.arguments(source: source, format: format, destination: destination))
        guard result.status == 0, FileManager.default.fileExists(atPath: destination.path) else {
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw VMLibraryError.diskConversionFailed(detail.isEmpty ? "qemu-img exited with \(result.status)" : detail)
        }
    }

    public static func runProcess(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
