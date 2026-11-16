import CoreGraphics
import Foundation
import Testing
@testable import VeilHostCore

/// Opt-in: set `VEIL_SHM_SOCKET` to a running `veil-shm-display` socket. Skipped otherwise.
struct SharedFramebufferClientLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VEIL_SHM_SOCKET"] != nil))
    @MainActor
    func receivesFramesFromARunningQEMU() async throws {
        let socket = try #require(ProcessInfo.processInfo.environment["VEIL_SHM_SOCKET"])
        var frames: [CGImage] = []
        let client = SharedFramebufferClient(socketPath: socket) { frames.append($0) }
        client.start()
        try await Task.sleep(for: .seconds(8))
        client.stop()

        let first = try #require(frames.first)
        print("shared framebuffer frames: \(frames.count), size \(first.width)x\(first.height)")
        #expect(first.width > 0 && first.height > 0)
    }
}
