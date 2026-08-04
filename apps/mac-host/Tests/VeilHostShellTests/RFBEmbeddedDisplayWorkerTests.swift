import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

@Suite("Embedded RFB display worker")
struct RFBEmbeddedDisplayWorkerTests {
    @Test("retries an initial connection refusal until the live display is ready")
    func retriesInitialConnectionRefusal() async {
        let attempts = LockedAttemptCounter()
        let frameReceived = AsyncSignal()
        let worker = RFBEmbeddedDisplayWorker(
            endpoint: RFBDisplayEndpoint(host: "127.0.0.1", port: 5_900),
            maximumConnectionAttempts: 2,
            connectionRetryDelay: 0,
            streamFactory: { _, _ in
                if attempts.incrementAndRead() == 1 {
                    throw RFBLoopbackSocketError.socketOperationFailed("connect: Connection refused")
                }
                return ScriptedRFBByteStream(inbound: Self.serverStreamData())
            }
        )

        worker.start(
            onFrame: { _ in frameReceived.signal() },
            onFailure: { _ in }
        )

        #expect(await frameReceived.wait(timeoutNanoseconds: 1_000_000_000))
        #expect(attempts.value == 2)
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
