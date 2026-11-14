import Foundation
import Testing
@testable import VeilHostCore

@Suite("QEMU exiting at launch")
struct QEMUEarlyExitTests {
    @Test("A process that exits at once is reported, with the end of its output")
    func reportsAnImmediateExit() async throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("qemu-early-exit-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: logURL) }
        let handle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "echo 'starting'; echo \"qemu-system-aarch64: -drive id=system: Could not open 'disk.img': Permission denied\" >&2; exit 1"]
        process.standardOutput = handle
        process.standardError = handle
        try process.run()

        #expect(await QEMUVMRuntimeBooter.exitedAtLaunch(process, window: .seconds(5)))
        try handle.close()
        #expect(process.terminationStatus == 1)
        let detail = QEMUVMRuntimeBooter.launchFailureDetail(logURL: logURL)
        #expect(detail.hasSuffix("Could not open 'disk.img': Permission denied"))

        let error = VMRuntimeError.qemuExitedAtLaunch(status: 1, detail: detail)
        #expect(error.errorDescription?.contains("Permission denied") == true)
    }

    @Test("A process still running after the window is not reported")
    func keepsARunningProcess() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        // Far longer than any test run, so only the terminate below ends it: a loaded CI runner once took
        // seven seconds to get through this test, and a five-second sleep had exited by then.
        process.arguments = ["600"]
        try process.run()
        defer { process.terminate() }

        #expect(!(await QEMUVMRuntimeBooter.exitedAtLaunch(process, window: .milliseconds(200))))
    }

    @Test("A process a test runner never started is not watched")
    func ignoresAProcessThatNeverStarted() async {
        #expect(!(await QEMUVMRuntimeBooter.exitedAtLaunch(Process(), window: .milliseconds(200))))
    }

    @Test("Long output keeps its end")
    func trimsLongOutput() throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("qemu-long-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }
        try Data((String(repeating: "x", count: 2_000) + "\nlast line\n").utf8).write(to: logURL)
        let detail = QEMUVMRuntimeBooter.launchFailureDetail(logURL: logURL, maximumCharacters: 100)
        #expect(detail.count == 100)
        #expect(detail.hasSuffix("last line"))
        #expect(QEMUVMRuntimeBooter.launchFailureDetail(logURL: URL(fileURLWithPath: "/no/such/log")) == "")
    }
}
