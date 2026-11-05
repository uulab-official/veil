import AppKit
import Foundation
import UniformTypeIdentifiers
import VeilHostCore

/// The sidebar's view of ``VMLibrary``: the machine list and the actions on it.
///
/// File work (clones, exports, disk conversion) runs off the main actor. Every action that changes
/// which machine is selected calls `machineDidChange` so the runtime model reloads the new
/// machine's snapshot; the runtime stores already follow the library selection.
@MainActor
@Observable
final class VMLibraryController {
    private(set) var machines: [VMLibraryMachine] = []
    private(set) var activeMachineID = VMLibrary.legacyMachineID
    private(set) var suspendedMachineIDs: Set<String> = []
    private(set) var isWorking = false
    var errorMessage: String?

    private let library: VMLibrary

    init(library: VMLibrary = VMLibrary()) {
        self.library = library
    }

    func reload() {
        machines = library.machines()
        activeMachineID = library.activeMachineID()
        suspendedMachineIDs = Set(machines.filter(library.hasSuspendedSession).map(\.id))
    }

    func select(_ id: String, then machineDidChange: @escaping (Bool) -> Void) {
        guard id != activeMachineID else {
            return
        }
        perform(machineDidChange: machineDidChange) { library in
            try library.select(id: id)
            return false
        }
    }

    func createMachine(named name: String, then machineDidChange: @escaping (Bool) -> Void) {
        perform(machineDidChange: machineDidChange) { library in
            try library.createMachine(name: name)
            return false
        }
    }

    func clone(_ id: String, then machineDidChange: @escaping (Bool) -> Void) {
        perform(machineDidChange: machineDidChange) { library in
            try library.cloneMachine(id: id)
            return false
        }
    }

    func rename(_ id: String, to name: String, then machineDidChange: @escaping (Bool) -> Void) {
        perform(machineDidChange: machineDidChange) { library in
            try library.renameMachine(id: id, to: name)
            return false
        }
    }

    func delete(_ id: String, then machineDidChange: @escaping (Bool) -> Void) {
        perform(machineDidChange: machineDidChange) { library in
            try library.deleteMachine(id: id)
            return false
        }
    }

    func export(_ machine: VMLibraryMachine) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(machine.profile.name).\(VMBundleManifest.bundleExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let destination = url.pathExtension == VMBundleManifest.bundleExtension
            ? url
            : url.appendingPathExtension(VMBundleManifest.bundleExtension)
        perform(machineDidChange: { _ in
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }) { library in
            try library.exportMachine(id: machine.id, to: destination)
            return false
        }
    }

    func importBundle(then machineDidChange: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = String(localized: "Choose a .veilvm machine bundle")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        perform(machineDidChange: machineDidChange) { library in
            try library.importBundle(from: url)
            return true
        }
    }

    func importDisk(then machineDidChange: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowedContentTypes = VMImportedDiskFormat.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = String(localized: "Choose a Windows 11 Arm disk (VHDX, VMDK, QCOW2, or raw)")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        perform(machineDidChange: machineDidChange) { library in
            try library.importDisk(from: url)
            return true
        }
    }

    /// Runs `work` off the main actor. It returns whether the selected machine needs its UEFI
    /// variables and TPM folder prepared (an imported disk arrives without them).
    private func perform(
        machineDidChange: ((Bool) -> Void)?,
        _ work: @escaping @Sendable (VMLibrary) throws -> Bool
    ) {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        let library = library
        Task {
            let result = await Task.detached { () -> Result<Bool, any Error> in
                Result { try work(library) }
            }.value
            isWorking = false
            reload()
            switch result {
            case .success(let needsPreparation):
                machineDidChange?(needsPreparation)
            case .failure(let error):
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// The library's errors in the user's language; Core keeps English for logs and the CLI.
    nonisolated static func message(for error: any Error) -> String {
        guard let error = error as? VMLibraryError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        switch error {
        case .machineNotFound:
            return String(localized: "This machine is no longer in the library.")
        case .machineIsRunning(let name):
            return String(localized: "\(name) is running. Shut it down first.")
        case .machineIsSuspended(let name):
            return String(localized: "\(name) is suspended. Resume and shut it down first, so its disk matches its saved state.")
        case .invalidName:
            return String(localized: "Enter a name for the machine.")
        case .bundleUnreadable, .bundleUnsupportedVersion:
            return String(localized: "This is not a Veil machine bundle this version can read.")
        case .bundleUnsafePath:
            return String(localized: "The bundle refers to a file outside itself, so it was not imported.")
        case .bundleDestinationExists(let path):
            return String(localized: "\(path) already exists.")
        case .unsupportedDiskFormat:
            return String(localized: "Veil cannot import this disk. Use VHDX, VHD, VMDK, QCOW2, or a raw image.")
        case .diskConverterMissing:
            return String(localized: "qemu-img was not found. Install QEMU with Homebrew (brew install qemu) to import this disk.")
        case .diskConversionFailed(let detail):
            return String(localized: "The disk could not be converted: \(detail)")
        }
    }
}
