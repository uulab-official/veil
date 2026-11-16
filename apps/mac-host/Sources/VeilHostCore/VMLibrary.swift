import Darwin
import Foundation

/// The order of Veil's Windows machines and which one the app is showing.
///
/// Stored at `Profiles/library.json`. Every runtime store resolves the selected machine through
/// ``VMLibrary/activeMachineID()``, so switching machines changes which profile, launch record,
/// suspension record, and boot report the app reads without rebuilding any service.
public struct VMLibraryIndex: Codable, Equatable, Sendable {
    public var selectedMachineID: String?
    public var machineIDs: [String]

    public init(selectedMachineID: String? = nil, machineIDs: [String] = []) {
        self.selectedMachineID = selectedMachineID
        self.machineIDs = machineIDs
    }
}

/// One machine in the library, with the files that belong to it.
public struct VMLibraryMachine: Equatable, Identifiable, Sendable {
    public var id: String
    public var profile: VMProfile
    public var profileURL: URL
    /// Where the disk, `uefi-vars.fd` and `tpm/` live: the disk's folder once it exists.
    public var machineDirectory: URL
    public var diagnosticsDirectory: URL
    /// The machine Veil kept in `default-vm-profile.json` and `~/Virtual Machines/Veil` before the
    /// library existed. Its files are referenced in place and never moved.
    public var isLegacyMachine: Bool
}

public enum VMLibraryError: Error, LocalizedError, Equatable, Sendable {
    case machineNotFound(String)
    case machineIsRunning(String)
    case machineIsSuspended(String)
    case invalidName
    case bundleUnreadable(String)
    case bundleUnsupportedVersion(Int)
    case bundleUnsafePath(String)
    case bundleDestinationExists(String)
    case unsupportedDiskFormat(String)
    case diskConverterMissing
    case diskConversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .machineNotFound(let id):
            "No Windows machine with id \(id) is in the library."
        case .machineIsRunning(let name):
            "\(name) is running. Shut it down first."
        case .machineIsSuspended(let name):
            "\(name) is suspended. Resume and shut it down first, so its disk matches its saved state."
        case .invalidName:
            "Enter a name for the machine."
        case .bundleUnreadable(let detail):
            "This is not a Veil machine bundle: \(detail)"
        case .bundleUnsupportedVersion(let version):
            "This bundle uses format version \(version), which this Veil cannot read."
        case .bundleUnsafePath(let path):
            "The bundle refers to a file outside itself (\(path)), so it was not imported."
        case .bundleDestinationExists(let path):
            "\(path) already exists."
        case .unsupportedDiskFormat(let ext):
            "Veil cannot import .\(ext) disks. Use VHDX, VHD, VMDK, QCOW2, or a raw image."
        case .diskConverterMissing:
            "qemu-img was not found. Install QEMU with Homebrew (brew install qemu) to import this disk."
        case .diskConversionFailed(let detail):
            "The disk could not be converted: \(detail)"
        }
    }
}

/// Veil's set of Windows machines: create, clone, rename, delete, export, and import.
///
/// Layout, all under `VeilApplicationSupport.directory` and the user's home:
/// - The legacy machine keeps `Profiles/default-vm-profile.json`, `Diagnostics/`, and
///   `~/Virtual Machines/Veil/`, exactly where Veil put them before multiple machines existed.
/// - Every other machine has `Profiles/Machines/<id>.json`, `Machines/<id>/Diagnostics/`, and
///   `~/Virtual Machines/Veil Machines/<id>/`.
///
/// Only one machine runs at a time: the app's runtime booter tracks a single QEMU process and the
/// guest agent uses one forwarded port, so mutating or switching away from a live machine is refused.
public struct VMLibrary: Sendable {
    public static let legacyMachineID = "vm_default_windows11"
    public static let legacyProfileFileName = "default-vm-profile.json"
    public static let defaultDiskFileName = "Windows.img"
    public static let maximumNameLength = 64

    public let applicationSupportDirectory: URL
    public let homeDirectory: URL
    private let isDiskInUse: @Sendable (String?) -> Bool
    let now: @Sendable () -> Date
    let makeID: @Sendable () -> String

    public init(
        applicationSupportDirectory: URL = VeilApplicationSupport.directory,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isDiskInUse: @escaping @Sendable (String?) -> Bool = { QEMUVMRuntimeBooter.runningProcess(attachedToVirtualDiskPath: $0) != nil },
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> String = { "vm_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12) }
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.homeDirectory = homeDirectory
        self.isDiskInUse = isDiskInUse
        self.now = now
        self.makeID = makeID
    }

    // MARK: - Paths

    var profilesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Profiles", isDirectory: true)
    }

    var indexURL: URL {
        profilesDirectory.appendingPathComponent("library.json")
    }

    public func profileURL(for id: String) -> URL {
        if id == Self.legacyMachineID {
            return profilesDirectory.appendingPathComponent(Self.legacyProfileFileName)
        }
        return profilesDirectory
            .appendingPathComponent("Machines", isDirectory: true)
            .appendingPathComponent("\(id).json")
    }

    public func diagnosticsDirectory(for id: String) -> URL {
        if id == Self.legacyMachineID {
            return applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        }
        return machineStateDirectory(for: id).appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func machineStateDirectory(for id: String) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("Machines", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    public func defaultMachineDirectory(for id: String) -> URL {
        Self.defaultMachineDirectory(for: id, homeDirectory: homeDirectory)
    }

    public static func defaultMachineDirectory(for id: String, homeDirectory: URL) -> URL {
        let virtualMachines = homeDirectory.appendingPathComponent("Virtual Machines", isDirectory: true)
        if id == legacyMachineID {
            return virtualMachines.appendingPathComponent("Veil", isDirectory: true)
        }
        return virtualMachines
            .appendingPathComponent("Veil Machines", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    func machineDirectory(for id: String, profile: VMProfile) -> URL {
        if let diskPath = profile.virtualDiskPath, !diskPath.isEmpty {
            return URL(fileURLWithPath: diskPath).deletingLastPathComponent()
        }
        return defaultMachineDirectory(for: id)
    }

    // MARK: - Index

    public func loadIndex() -> VMLibraryIndex {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder.veilDiagnostics.decode(VMLibraryIndex.self, from: data) else {
            return VMLibraryIndex()
        }
        return index
    }

    func saveIndex(_ index: VMLibraryIndex) throws {
        try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        try JSONEncoder.veilDiagnostics.encode(index).write(to: indexURL, options: .atomic)
    }

    /// The machine every default store reads. Falls back to the first machine, then to the legacy
    /// machine, so a Mac that never used the library behaves exactly as before.
    public func activeMachineID() -> String {
        let index = loadIndex()
        if let selected = index.selectedMachineID, profileExists(selected) {
            return selected
        }
        return orderedMachineIDs(index: index).first ?? Self.legacyMachineID
    }

    private func profileExists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: profileURL(for: id).path)
    }

    private func orderedMachineIDs(index: VMLibraryIndex) -> [String] {
        var ids = index.machineIDs.filter(profileExists)
        if profileExists(Self.legacyMachineID), !ids.contains(Self.legacyMachineID) {
            ids.insert(Self.legacyMachineID, at: 0)
        }
        let machinesDirectory = profilesDirectory.appendingPathComponent("Machines", isDirectory: true)
        let stray = ((try? FileManager.default.contentsOfDirectory(atPath: machinesDirectory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .filter { !ids.contains($0) }
            .sorted()
        return ids + stray
    }

    public func machines() -> [VMLibraryMachine] {
        orderedMachineIDs(index: loadIndex()).compactMap { id in
            guard let profile = try? loadProfile(id: id) else {
                return nil
            }
            return machine(id: id, profile: profile)
        }
    }

    public func machine(id: String) throws -> VMLibraryMachine {
        guard profileExists(id) else {
            throw VMLibraryError.machineNotFound(id)
        }
        return machine(id: id, profile: try loadProfile(id: id))
    }

    private func machine(id: String, profile: VMProfile) -> VMLibraryMachine {
        VMLibraryMachine(
            id: id,
            profile: profile,
            profileURL: profileURL(for: id),
            machineDirectory: machineDirectory(for: id, profile: profile),
            diagnosticsDirectory: diagnosticsDirectory(for: id),
            isLegacyMachine: id == Self.legacyMachineID
        )
    }

    public func loadProfile(id: String) throws -> VMProfile {
        let data = try Data(contentsOf: profileURL(for: id))
        return try JSONDecoder.veilDiagnostics.decode(VMProfile.self, from: data)
    }

    func saveProfile(_ profile: VMProfile, id: String) throws {
        let url = profileURL(for: id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.veilDiagnostics.encode(profile).write(to: url, options: .atomic)
    }

    /// Records the machine order with the legacy machine first, so the list stays stable once a
    /// second machine exists.
    func register(_ id: String, select: Bool) throws {
        var index = loadIndex()
        var ids = orderedMachineIDs(index: index)
        if !ids.contains(id) {
            ids.append(id)
        }
        index.machineIDs = ids
        if select {
            index.selectedMachineID = id
        }
        try saveIndex(index)
    }

    public func select(id: String) throws {
        guard profileExists(id) else {
            throw VMLibraryError.machineNotFound(id)
        }
        try register(id, select: true)
    }

    // MARK: - Create, rename

    /// A new, empty machine; Windows setup fills in its disk the same way it does on first run.
    @discardableResult
    public func createMachine(
        name: String,
        resourcePlan: VMResourcePlan = VMResourcePolicy.currentHostPlan(),
        select: Bool = true
    ) throws -> VMProfile {
        let id = makeID()
        var profile = VMProfile.defaultWindows11Arm(createdAt: now(), homeDirectory: homeDirectory)
        profile.id = id
        profile.name = try uniqueName(Self.validatedName(name))
        profile.cpuCount = resourcePlan.cpuCount
        profile.memoryMB = resourcePlan.memoryMB
        profile.diskGB = resourcePlan.diskGB
        try saveProfile(profile, id: id)
        try register(id, select: select)
        return profile
    }

    public func renameMachine(id: String, to name: String) throws {
        var profile = try machine(id: id).profile
        let validated = try Self.validatedName(name)
        guard validated != profile.name else {
            return
        }
        profile.name = try uniqueName(validated, excluding: id)
        try saveProfile(profile, id: id)
    }

    static func validatedName(_ name: String) throws -> String {
        let trimmed = String(
            name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VMLibraryError.invalidName
        }
        return String(trimmed.prefix(maximumNameLength))
    }

    /// "Windows 11 Arm", then "Windows 11 Arm 2", so two rows in the sidebar never look the same.
    func uniqueName(_ name: String, excluding excludedID: String? = nil) throws -> String {
        let taken = Set(machines().filter { $0.id != excludedID }.map { $0.profile.name.lowercased() })
        guard taken.contains(name.lowercased()) else {
            return name
        }
        var suffix = 2
        while taken.contains("\(name) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(name) \(suffix)"
    }

    // MARK: - Running and suspended guards

    /// A live QEMU process holding the disk, or a saved memory state, means the disk is not a
    /// consistent copy on its own; cloning, exporting, or deleting it then would lose data.
    func requireStopped(_ machine: VMLibraryMachine, allowSuspended: Bool = false) throws {
        if isDiskInUse(machine.profile.virtualDiskPath) {
            throw VMLibraryError.machineIsRunning(machine.profile.name)
        }
        if !allowSuspended, suspensionRecord(for: machine) != nil {
            throw VMLibraryError.machineIsSuspended(machine.profile.name)
        }
    }

    func suspensionRecordURL(for machine: VMLibraryMachine) -> URL {
        machine.diagnosticsDirectory
            .appendingPathComponent("QEMU Suspend", isDirectory: true)
            .appendingPathComponent("qemu-suspend-latest.json")
    }

    public func hasSuspendedSession(_ machine: VMLibraryMachine) -> Bool {
        suspensionRecord(for: machine) != nil
    }

    func suspensionRecord(for machine: VMLibraryMachine) -> VMSuspensionRecord? {
        guard let data = try? Data(contentsOf: suspensionRecordURL(for: machine)) else {
            return nil
        }
        return try? JSONDecoder.veilDiagnostics.decode(VMSuspensionRecord.self, from: data)
    }

    // MARK: - Clone

    /// An exact twin: the disk and UEFI variables are APFS clones (no extra space until either
    /// side writes), and the TPM state is copied, so BitLocker and Windows Hello keep working in
    /// the copy. Both machines then share one Windows identity; see docs/vm-library.md.
    @discardableResult
    public func cloneMachine(id: String, name: String? = nil, select: Bool = true) throws -> VMProfile {
        let source = try machine(id: id)
        try requireStopped(source)

        let newID = makeID()
        var profile = source.profile
        profile.id = newID
        profile.name = try uniqueName(Self.validatedName(name ?? "\(source.profile.name) Copy"))
        profile.createdAt = now()
        profile.guestAgentConnectedAt = nil
        profile.virtualDiskBookmarkData = nil

        let destination = defaultMachineDirectory(for: newID)
        if let diskPath = source.profile.virtualDiskPath, !diskPath.isEmpty {
            let sourceDisk = URL(fileURLWithPath: diskPath)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            do {
                let disk = destination.appendingPathComponent(sourceDisk.lastPathComponent)
                try Self.cloneFile(from: sourceDisk, to: disk)
                try Self.copyFirmwareState(from: sourceDisk.deletingLastPathComponent(), to: destination)
                profile.virtualDiskPath = disk.path
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        } else {
            profile.virtualDiskPath = nil
        }

        try saveProfile(profile, id: newID)
        try register(newID, select: select)
        return profile
    }

    static func copyFirmwareState(from sourceDirectory: URL, to destination: URL) throws {
        let vars = sourceDirectory.appendingPathComponent("uefi-vars.fd")
        if FileManager.default.fileExists(atPath: vars.path) {
            try cloneFile(from: vars, to: destination.appendingPathComponent("uefi-vars.fd"))
        }
        let tpm = sourceDirectory.appendingPathComponent("tpm", isDirectory: true)
        if FileManager.default.fileExists(atPath: tpm.path) {
            try FileManager.default.copyItem(at: tpm, to: destination.appendingPathComponent("tpm", isDirectory: true))
        }
    }

    /// `clonefile(2)` shares blocks on APFS; across volumes it falls back to a full copy.
    static func cloneFile(from source: URL, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VMLibraryError.bundleDestinationExists(destination.path)
        }
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                Darwin.clonefile(sourcePath!, destinationPath!, UInt32(CLONE_NOFOLLOW))
            }
        }
        if result == 0 {
            return
        }
        let code = errno
        guard code == ENOTSUP || code == EXDEV else {
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    // MARK: - Delete

    /// Moves the machine's own files to the Trash and forgets it. A disk the user picked from
    /// elsewhere (outside the machine's folder) and the shared folder are left alone.
    public func deleteMachine(
        id: String,
        discard: (URL) throws -> Void = LocalVMRuntimeService.moveToTrash
    ) throws {
        let target = try machine(id: id)
        try requireStopped(target, allowSuspended: true)

        var items: [URL] = []
        let ownedDirectory = defaultMachineDirectory(for: id)
        if target.isLegacyMachine {
            // The legacy folder may hold files the user put there; take only the machine's own.
            if let diskPath = target.profile.virtualDiskPath, !diskPath.isEmpty,
               URL(fileURLWithPath: diskPath).deletingLastPathComponent().standardizedFileURL == ownedDirectory.standardizedFileURL {
                items.append(URL(fileURLWithPath: diskPath))
            }
            items.append(ownedDirectory.appendingPathComponent("uefi-vars.fd"))
            items.append(ownedDirectory.appendingPathComponent("tpm", isDirectory: true))
            if let record = suspensionRecord(for: target) {
                items.append(URL(fileURLWithPath: record.stateFilePath))
            }
            items.append(suspensionRecordURL(for: target))
        } else {
            items.append(ownedDirectory)
            if let record = suspensionRecord(for: target) {
                items.append(URL(fileURLWithPath: record.stateFilePath))
            }
            items.append(machineStateDirectory(for: id))
        }
        items.append(target.profileURL)

        for url in items where FileManager.default.fileExists(atPath: url.path) {
            try discard(url)
        }

        var index = loadIndex()
        index.machineIDs.removeAll { $0 == id }
        if index.selectedMachineID == id {
            index.selectedMachineID = orderedMachineIDs(index: index).first
        }
        try saveIndex(index)
    }
}
