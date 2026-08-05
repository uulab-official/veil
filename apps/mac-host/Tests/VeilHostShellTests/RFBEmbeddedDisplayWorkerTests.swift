import AppKit
import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

@Suite("Embedded RFB display worker")
struct RFBEmbeddedDisplayWorkerTests {
    @Test("publishes the latest framebuffer dimensions for display verification")
    @MainActor
    func publishesLatestFramebufferDimensions() {
        let model = RFBEmbeddedDisplayModel()

        #expect(model.frameSize == nil)

        model.receive(
            image: NSImage(size: NSSize(width: 1_920, height: 1_080)),
            sequence: 1
        )

        #expect(model.frameSize == CGSize(width: 1_920, height: 1_080))
    }

    @Test("keeps the last live frame quiet while the display reconnects")
    @MainActor
    func keepsLastLiveFrameDuringReconnect() {
        let model = RFBEmbeddedDisplayModel()
        let image = NSImage(size: NSSize(width: 1, height: 1))

        model.receive(image: image, sequence: 7)
        let initialIdentity = model.imageIdentity(
            endpoint: "127.0.0.1:5900",
            fallbackRevisionID: "snapshot-a"
        )
        model.receiveFailure("connect: Connection refused")

        #expect(model.status == .receiving)
        #expect(model.shouldShowStatusOverlay == false)
        #expect(
            model.imageIdentity(
                endpoint: "127.0.0.1:5900",
                fallbackRevisionID: "snapshot-b"
            ) == initialIdentity
        )
    }

    @Test("shows a terminal display error before any frame arrives")
    @MainActor
    func showsInitialTerminalFailure() {
        let model = RFBEmbeddedDisplayModel()

        model.receiveFailure("connect: Connection refused")

        #expect(model.status == .failed("connect: Connection refused"))
        #expect(model.shouldShowStatusOverlay)
    }

    @Test("maps pointer taps inside the fitted Windows frame instead of its letterbox")
    func mapsPointerTapInsideAspectFitFrame() throws {
        let point = try #require(AspectFitInputCoordinateMapper.normalizedPoint(
            point: CGPoint(x: 900, y: 337.5),
            bounds: CGRect(x: 0, y: 0, width: 1_200, height: 675),
            contentSize: CGSize(width: 1_024, height: 768)
        ))

        #expect(abs(point.x - (5.0 / 6.0)) < 0.000_1)
        #expect(abs(point.y - 0.5) < 0.000_1)
        #expect(AspectFitInputCoordinateMapper.normalizedPoint(
            point: CGPoint(x: 75, y: 337.5),
            bounds: CGRect(x: 0, y: 0, width: 1_200, height: 675),
            contentSize: CGSize(width: 1_024, height: 768)
        ) == nil)
    }

    @Test("retries initial refusal and resets the retry budget after a live frame")
    func retriesInitialConnectionRefusalAndLaterIdleTimeout() async {
        let attempts = LockedAttemptCounter()
        let frames = LockedAttemptCounter()
        let secondFrameReceived = AsyncSignal()
        let worker = RFBEmbeddedDisplayWorker(
            endpoint: RFBDisplayEndpoint(host: "127.0.0.1", port: 5_900),
            maximumConnectionAttempts: 2,
            connectionRetryDelay: 0.001,
            streamFactory: { _, _ in
                if attempts.incrementAndRead() == 1 {
                    throw RFBLoopbackSocketError.socketOperationFailed("connect: Connection refused")
                }
                return ScriptedRFBByteStream(inbound: Self.serverStreamData())
            }
        )

        worker.start(
            onFrame: { _ in
                if frames.incrementAndRead() == 2 {
                    secondFrameReceived.signal()
                }
            },
            onFailure: { _ in }
        )

        #expect(await secondFrameReceived.wait(timeoutNanoseconds: 1_000_000_000))
        #expect(attempts.value >= 3)
        worker.stop()
    }

    private static func serverStreamData() -> Data {
        var data = Data("RFB 003.008\n".utf8)
        data.append(contentsOf: [1, 1])
        data.append(contentsOf: [0, 0, 0, 0])
        data.appendBigEndian(UInt16(2))
        data.appendBigEndian(UInt16(1))
        data.append(contentsOf: [
            32, 24, 0, 1,
            0, 255, 0, 255, 0, 255,
            16, 8, 0,
            0, 0, 0
        ])
        data.appendBigEndian(UInt32(4))
        data.append(contentsOf: Data("QEMU".utf8))
        data.append(contentsOf: [
            0, 0, 0, 1,
            0, 0, 0, 0,
            0, 2, 0, 1,
            0, 0, 0, 0,
            0, 0, 255, 0,
            0, 255, 0, 0
        ])
        return data
    }
}

private final class LockedAttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func incrementAndRead() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}

private final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var signaled = false

    var isSignaled: Bool {
        lock.withLock { signaled }
    }

    func signal() {
        lock.withLock { signaled = true }
    }

    func wait(timeoutNanoseconds: UInt64) async -> Bool {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if isSignaled {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return isSignaled
    }
}

private final class ScriptedRFBByteStream: RFBByteStream, @unchecked Sendable {
    private let lock = NSLock()
    private var inbound: Data
    private var offset = 0

    init(inbound: Data) {
        self.inbound = inbound
    }

    func readExactly(_ byteCount: Int) throws -> Data {
        try lock.withLock {
            guard inbound.count >= offset + byteCount else {
                throw RFBLoopbackSocketError.connectionClosed
            }
            defer { offset += byteCount }
            return inbound.subdata(in: offset..<(offset + byteCount))
        }
    }

    func write(_ data: Data) throws {}
    func close() {}
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(contentsOf: [
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}
