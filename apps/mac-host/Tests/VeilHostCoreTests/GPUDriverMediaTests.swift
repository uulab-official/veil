import Foundation
import Testing
@testable import VeilHostCore

@Suite("GPU driver disc")
struct GPUDriverMediaTests {
    @Test("The disc carries the package under viogpu3d with the label the agent looks for")
    func buildsDisc() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("package")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("inf".utf8).write(to: package.appendingPathComponent("viogpu3d.inf"))
        let media = root.appendingPathComponent("shared/VeilGPUDriver.iso")

        var seen: [String] = []
        try GPUDriverMedia.build(packageDirectory: package, mediaURL: media) { tool, arguments in
            #expect(tool == "/usr/bin/hdiutil")
            seen = arguments
            let staging = URL(fileURLWithPath: arguments.last!)
            #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("viogpu3d/viogpu3d.inf").path))
            let output = arguments[arguments.firstIndex(of: "-o")! + 1]
            FileManager.default.createFile(atPath: output, contents: Data("iso".utf8))
            return 0
        }
        #expect(seen.contains("VEIL_GPU"))
        #expect(FileManager.default.fileExists(atPath: media.path))
    }

    @Test("A package without its INF is refused")
    func refusesEmptyPackage() {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: VMRuntimeError.self) {
            try GPUDriverMedia.build(packageDirectory: empty, mediaURL: empty.appendingPathComponent("x.iso")) { _, _ in 0 }
        }
    }

    @Test("Only a launch on the GPU runtime may receive the driver")
    func detectsGPULaunch() {
        func record(_ arguments: [String]) -> QEMULaunchRecord {
            QEMULaunchRecord(
                pid: 1,
                executablePath: "/q",
                arguments: arguments,
                processLogPath: "/tmp/l",
                monitorSocketPath: "/tmp/m",
                qmpSocketPath: "/tmp/q",
                startedAt: Date(timeIntervalSince1970: 0)
            )
        }
        #expect(QEMUGPURuntime.launchUsesGPURuntime(record(["-device", QEMUGPURuntime.displayDevice])))
        #expect(!QEMUGPURuntime.launchUsesGPURuntime(record(["-device", "virtio-gpu-pci"])))
    }

    @Test("Health carries the driver state, and the request names nothing to run")
    func protocolShapes() throws {
        let health = """
        {"type":"agent.health.response","requestId":"h","protocolVersion":1,"agentVersion":"0.1.0","os":"Windows",
         "session":{"interactive":true,"user":"u"},
         "capabilities":{"appList":true,"appLaunch":true,"windowTracking":true,"windowCapture":true,"input":true,"clipboardText":true,"packageIdentity":false,"gpuDriverInstall":true},
         "gpuDriver":{"installed":false,"installing":false,"lastInstall":{"outcome":"declined","finishedAt":"2026-11-15T09:00:00Z"}}}
        """
        let decoded = try JSONDecoder().decode(AgentHealthResponse.self, from: Data(health.utf8))
        #expect(decoded.capabilities.gpuDriverInstall == true)
        #expect(decoded.gpuDriver == GuestGPUDriverStatus(
            installed: false,
            installing: false,
            lastInstall: .init(outcome: "declined", finishedAt: "2026-11-15T09:00:00Z")
        ))

        let request = try JSONEncoder().encode(GPUDriverInstallRequest())
        let object = try JSONSerialization.jsonObject(with: request) as? [String: Any]
        #expect(object?["type"] as? String == "gpu.driver.install.request")
        #expect(Set(object?.keys.map { $0 } ?? []) == ["type", "requestId", "protocolVersion"])

        let response = """
        {"type":"gpu.driver.install.response","requestId":"r","protocolVersion":1,"install":{"isSupported":true,"outcome":"approval-requested","message":null}}
        """
        #expect(try JSONDecoder().decode(GPUDriverInstallResponse.self, from: Data(response.utf8)).install.outcome == "approval-requested")
    }
}
