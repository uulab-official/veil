import Foundation
import Testing
@testable import VeilHostCore

struct VeilApplicationSupportTests {
    @Test("test processes never resolve to the real Application Support folder")
    func testProcessIsIsolated() {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Veil", isDirectory: true)

        #expect(VeilApplicationSupport.isRunningUnderTests)
        #expect(VeilApplicationSupport.directory.standardizedFileURL != real.standardizedFileURL)
        #expect(!JSONVMProfileStore.defaultDirectory.path.hasPrefix(real.path))
        #expect(!JSONWindowRestoreIntentStore.defaultDirectory.path.hasPrefix(real.path))
        #expect(!JSONVMRuntimeBootReportStore.defaultDirectory.path.hasPrefix(real.path))
        #expect(!QEMUVMRuntimeBooter.defaultDiagnosticsDirectory().path.hasPrefix(real.path))
    }

    @Test("an explicit directory override wins over every default")
    func environmentOverrideWins() {
        let resolved = VeilApplicationSupport.resolve(
            environment: [VeilApplicationSupport.directoryEnvironmentKey: "/tmp/veil-override"],
            isTestProcess: true
        )
        #expect(resolved.path == "/tmp/veil-override")
    }

    @Test("a normal app process resolves to Application Support/Veil")
    func appProcessUsesApplicationSupport() {
        let resolved = VeilApplicationSupport.resolve(environment: [:], isTestProcess: false)
        #expect(resolved.lastPathComponent == "Veil")
        #expect(resolved.deletingLastPathComponent().lastPathComponent == "Application Support")
    }
}
