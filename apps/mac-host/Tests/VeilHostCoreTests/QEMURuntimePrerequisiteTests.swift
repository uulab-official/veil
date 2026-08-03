import Testing
@testable import VeilHostCore

struct QEMURuntimePrerequisiteTests {
    @Test("reports every missing QEMU runtime prerequisite")
    func missing() {
        let report = QEMURuntimePrerequisiteReport.probe(fileExists: { _ in false })
        #expect(!report.isReady)
        #expect(report.checks.count == 3)
        #expect(report.checks.allSatisfy { !$0.isReady })
    }

    @Test("becomes ready only when QEMU firmware and TPM are present")
    func ready() {
        let report = QEMURuntimePrerequisiteReport.probe { path in
            path == "/opt/homebrew/bin/qemu-system-aarch64"
                || path == "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
                || path == "/opt/homebrew/bin/swtpm"
        }
        #expect(report.isReady)
        #expect(report.checks.allSatisfy { $0.isReady })
        #expect(QEMURuntimePrerequisiteReport.installCommand == "brew install qemu swtpm")
    }
}
