import Foundation
import Testing
@testable import VeilHostCore

@Suite("GPU acceleration backup")
struct VMGraphicsBackupTests {
    @Test("A backup holds the disk, UEFI variables and TPM state, and restoring it puts them back")
    func backupAndRestore() throws {
        let machine = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: machine) }
        let tpm = machine.appendingPathComponent("tpm")
        try FileManager.default.createDirectory(at: tpm, withIntermediateDirectories: true)
        let disk = machine.appendingPathComponent("Windows 11 Arm.img")
        try Data("before".utf8).write(to: disk)
        try Data("vars-before".utf8).write(to: machine.appendingPathComponent("uefi-vars.fd"))
        try Data("tpm-before".utf8).write(to: tpm.appendingPathComponent("tpm2-00.permall"))
        try Data("pid".utf8).write(to: tpm.appendingPathComponent("swtpm.pid"))

        let backup = try VMGraphicsBackup.create(diskPath: disk.path, now: Date(timeIntervalSince1970: 0))
        #expect(backup.path.hasSuffix("Backups/before-gpu-19700101-000000"))
        #expect(!FileManager.default.fileExists(atPath: backup.appendingPathComponent("tpm/swtpm.pid").path))

        // Windows changes after GPU acceleration is on.
        try Data("after".utf8).write(to: disk)
        try Data("vars-after".utf8).write(to: machine.appendingPathComponent("uefi-vars.fd"))
        try Data("tpm-after".utf8).write(to: tpm.appendingPathComponent("tpm2-00.permall"))

        try VMGraphicsBackup.restore(from: backup, diskPath: disk.path)
        #expect(try String(contentsOf: disk, encoding: .utf8) == "before")
        #expect(try String(contentsOf: machine.appendingPathComponent("uefi-vars.fd"), encoding: .utf8) == "vars-before")
        #expect(try String(contentsOf: tpm.appendingPathComponent("tpm2-00.permall"), encoding: .utf8) == "tpm-before")
        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(!FileManager.default.fileExists(atPath: disk.path + ".before-restore"))
    }

    @Test("A missing disk or backup is refused")
    func refusesMissingFiles() {
        #expect(throws: VMGraphicsBackup.BackupError.noDisk) {
            try VMGraphicsBackup.create(diskPath: "/no/such/\(UUID().uuidString)/disk.img")
        }
        let missing = URL(fileURLWithPath: "/no/such/\(UUID().uuidString)")
        #expect(throws: VMGraphicsBackup.BackupError.missingBackup(missing.path)) {
            try VMGraphicsBackup.restore(from: missing, diskPath: "/tmp/disk.img")
        }
    }
}
