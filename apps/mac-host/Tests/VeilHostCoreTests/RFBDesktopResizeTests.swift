import Foundation
import Testing

@testable import VeilHostCore

@Suite("RFB desktop resize policy")
struct RFBDesktopResizePolicyTests {
    @Test("converts points to pixels with backing scale and 8-pixel alignment")
    func convertsPointsToPixels() {
        let oneX = RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 1_280, height: 800),
            backingScaleFactor: 1
        )
        #expect(oneX == RFBDesktopResizeTarget(widthInPixels: 1_280, heightInPixels: 800))

        let twoX = RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 1_280, height: 800),
            backingScaleFactor: 2
        )
        #expect(twoX == RFBDesktopResizeTarget(widthInPixels: 2_560, heightInPixels: 1_600))

        let unaligned = RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 1_283.9, height: 805.9),
            backingScaleFactor: 1
        )
        #expect(unaligned == RFBDesktopResizeTarget(widthInPixels: 1_280, heightInPixels: 800))
    }

    @Test("clamps each axis to the supported pixel bounds")
    func clampsAxisBounds() {
        let tooSmall = RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 100, height: 50),
            backingScaleFactor: 1
        )
        #expect(tooSmall == RFBDesktopResizeTarget(
            widthInPixels: RFBDesktopSizePolicy.minimumAxisPixels,
            heightInPixels: RFBDesktopSizePolicy.minimumAxisPixels
        ))

        let tooLarge = RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 8_000, height: 6_000),
            backingScaleFactor: 2
        )
        #expect(tooLarge == RFBDesktopResizeTarget(widthInPixels: 2_880, heightInPixels: 2_880))
    }

    @Test("caps total area at 4K UHD while keeping the aspect ratio")
    func capsTotalArea() {
        let exactCap = RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 1_920, height: 1_080),
            backingScaleFactor: 2
        )
        #expect(exactCap == RFBDesktopResizeTarget(widthInPixels: 3_840, heightInPixels: 2_160))

        let overCap = RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 2_560, height: 1_440),
            backingScaleFactor: 2
        )
        let width = overCap?.widthInPixels ?? 0
        let height = overCap?.heightInPixels ?? 0
        #expect(width == 3_320)
        #expect(height == 2_488)
        #expect(width * height <= RFBDesktopSizePolicy.maximumAreaPixels)
        #expect(width * height > 0)
    }

    @Test("rejects invalid geometry input")
    func rejectsInvalidInput() {
        #expect(RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 0, height: 100),
            backingScaleFactor: 1
        ) == nil)
        #expect(RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 100, height: CGFloat.infinity),
            backingScaleFactor: 1
        ) == nil)
        #expect(RFBDesktopSizePolicy.target(
            contentSizeInPoints: CGSize(width: 100, height: 100),
            backingScaleFactor: 0
        ) == nil)
    }

    @Test("suppresses sub-threshold jitter on both axes")
    func suppressesSubThresholdChanges() {
        let first = RFBDesktopResizeTarget(widthInPixels: 1_280, heightInPixels: 800)
        let jittered = RFBDesktopResizeTarget(widthInPixels: 1_288, heightInPixels: 808)

        #expect(!RFBDesktopSizePolicy.isSignificantChange(from: first, to: jittered))
        #expect(RFBDesktopSizePolicy.isSignificantChange(
            from: first,
            to: RFBDesktopResizeTarget(widthInPixels: 1_296, heightInPixels: 800)
        ))
        #expect(RFBDesktopSizePolicy.isSignificantChange(from: nil, to: first))
    }
}

@Suite("RFB viewport mapper")
struct RFBViewportMapperTests {
    @Test("computes a letterboxed viewport for a 4:3 framebuffer in a 16:9 container")
    func letterboxesMismatchedAspect() {
        let viewport = RFBViewportMapper.viewport(
            framebufferWidth: 1_024,
            framebufferHeight: 768,
            containerWidth: 1_920,
            containerHeight: 1_080
        )

        #expect(viewport.width == 1_440)
        #expect(viewport.height == 1_080)
        #expect(viewport.minX == 240)
        #expect(viewport.minY == 0)
    }

    @Test("maps viewport corners onto guest corners")
    func mapsCorners() throws {
        let viewport = RFBViewportMapper.viewport(
            framebufferWidth: 1_920,
            framebufferHeight: 1_080,
            containerWidth: 1_920,
            containerHeight: 1_080
        )

        let topLeft = try #require(RFBViewportMapper.normalizedGuestPoint(
            pointInContainer: CGPoint(x: 0, y: 1_080),
            viewport: viewport
        ))
        #expect(topLeft.x == 0)
        #expect(topLeft.y == 1)

        let bottomRight = try #require(RFBViewportMapper.normalizedGuestPoint(
            pointInContainer: CGPoint(x: 1_920, y: 0),
            viewport: viewport
        ))
        #expect(bottomRight.x == 1)
        #expect(bottomRight.y == 0)
    }

    @Test("refuses points outside the viewport so letterbox clicks never reach the guest")
    func refusesOutsidePoints() {
        let viewport = RFBViewportMapper.viewport(
            framebufferWidth: 1_024,
            framebufferHeight: 768,
            containerWidth: 1_920,
            containerHeight: 1_080
        )

        #expect(RFBViewportMapper.normalizedGuestPoint(
            pointInContainer: CGPoint(x: 100, y: 540),
            viewport: viewport
        ) == nil)
        #expect(RFBViewportMapper.normalizedGuestPoint(
            pointInContainer: CGPoint(x: 1_880, y: 540),
            viewport: viewport
        ) == nil)
        #expect(RFBViewportMapper.normalizedGuestPoint(
            pointInContainer: CGPoint(x: 960, y: 540),
            viewport: viewport
        ) != nil)
    }

    @Test("degrades to an empty viewport for invalid sizes")
    func handlesInvalidSizes() {
        #expect(RFBViewportMapper.viewport(
            framebufferWidth: 0,
            framebufferHeight: 768,
            containerWidth: 1_920,
            containerHeight: 1_080
        ).isEmpty)
        #expect(RFBViewportMapper.normalizedGuestPoint(
            pointInContainer: CGPoint(x: 10, y: 10),
            viewport: .zero
        ) == nil)
    }
}

@Suite("RFB desktop resize state machine")
struct RFBDesktopResizeStateMachineTests {
    private static let target = RFBDesktopResizeTarget(widthInPixels: 1_600, heightInPixels: 900)

    @Test("a framebuffer update without ExtendedDesktopSize during probe marks the connection unsupported")
    func probeWithoutSupportMarksUnsupported() {
        var machine = RFBDesktopResizeStateMachine()
        machine.resetForReconnect()
        #expect(machine.presentation == .recovering)

        machine.handleFramebufferUpdateWithoutResizeResponse()
        #expect(machine.phase == .unsupported)
        #expect(machine.presentation == .scaled)

        let sent = machine.request(Self.target)
        #expect(sent == nil)
    }

    @Test("an ExtendedDesktopSize success response during probe applies the current size")
    func probeWithSupportAppliesSize() {
        var machine = RFBDesktopResizeStateMachine()
        machine.resetForReconnect()

        machine.handleDesktopSizeResponse(RFBDesktopSizeResponse(
            width: 1_280,
            height: 720,
            reasonCode: 1,
            resultCode: 0,
            screens: [RFBScreenLayoutEntry(id: 0, x: 0, y: 0, width: 1_280, height: 720, flags: 0)]
        ))

        #expect(machine.phase == .applied(RFBDesktopResizeTarget(widthInPixels: 1_280, heightInPixels: 720)))
        #expect(machine.presentation == .available)
    }

    @Test("a host request is sent once and responses mark it applied")
    func requestRoundTrip() {
        var machine = RFBDesktopResizeStateMachine()
        machine.resetForReconnect()
        machine.handleDesktopSizeResponse(Self.successResponse(1_280, 720))

        let sent = machine.request(Self.target)
        #expect(sent == Self.target)

        machine.markRequestSent(Self.target, now: 100)
        machine.handleDesktopSizeResponse(Self.successResponse(1_600, 900))
        #expect(machine.phase == .applied(Self.target))
    }

    @Test("a newer target replaces the queued one and is sent after the in-flight request succeeds")
    func queuedTargetIsSentAfterSuccess() {
        var machine = RFBDesktopResizeStateMachine()
        machine.resetForReconnect()
        machine.handleDesktopSizeResponse(Self.successResponse(1_280, 720))

        let inFlight = machine.request(Self.target)
        #expect(inFlight == Self.target)
        machine.markRequestSent(Self.target, now: 100)

        let newer = RFBDesktopResizeTarget(widthInPixels: 1_920, heightInPixels: 1_080)
        #expect(machine.request(newer) == nil)
        #expect(machine.queuedTarget == newer)

        machine.handleDesktopSizeResponse(Self.successResponse(1_600, 900))
        let queued = machine.takeQueuedTarget()
        #expect(queued == newer)
        #expect(machine.takeQueuedTarget() == nil)

        machine.markRequestSent(newer, now: 150)
        machine.handleDesktopSizeResponse(Self.successResponse(1_920, 1_080))
        #expect(machine.phase == .applied(newer))
    }

    @Test("a matching rejection disables automatic resize for the connection")
    func rejectionDisablesResize() {
        var machine = RFBDesktopResizeStateMachine()
        machine.resetForReconnect()
        machine.handleDesktopSizeResponse(Self.successResponse(1_280, 720))

        #expect(machine.request(Self.target) != nil)
        machine.markRequestSent(Self.target, now: 100)

        machine.handleDesktopSizeResponse(RFBDesktopSizeResponse(
            width: 1_600,
            height: 900,
            reasonCode: 0,
            resultCode: 2,
            screens: []
        ))

        #expect(machine.presentation == .rejected)
        #expect(machine.queuedTarget == nil)
        #expect(machine.request(Self.target) == nil)
    }

    @Test("a rejection that does not match the pending request is ignored")
    func unrelatedRejectionIsIgnored() {
        var machine = RFBDesktopResizeStateMachine()
        machine.resetForReconnect()
        machine.handleDesktopSizeResponse(Self.successResponse(1_280, 720))

        #expect(machine.request(Self.target) != nil)
        machine.markRequestSent(Self.target, now: 100)

        machine.handleDesktopSizeResponse(RFBDesktopSizeResponse(
            width: 999,
            height: 999,
            reasonCode: 0,
            resultCode: 2,
            screens: []
        ))

        #expect(machine.phase == .requestPending(Self.target))
    }

    @Test("a pending request times out deterministically on the injected clock")
    func timeoutUsesInjectedClock() {
        var machine = RFBDesktopResizeStateMachine(requestTimeoutSeconds: 3)
        machine.resetForReconnect()
        machine.handleDesktopSizeResponse(Self.successResponse(1_280, 720))

        #expect(machine.request(Self.target) != nil)
        machine.markRequestSent(Self.target, now: 100)

        #expect(machine.checkTimeout(now: 102.9) == nil)
        #expect(machine.phase == .requestPending(Self.target))

        let timedOut = machine.checkTimeout(now: 103)
        #expect(timedOut == Self.target)
        #expect(machine.phase == .timedOut(requested: Self.target))
        #expect(machine.presentation == .rejected)
        #expect(machine.request(Self.target) == nil)
    }

    @Test("an unsolicited success response records a guest-initiated resize")
    func externalResizeIsRecorded() {
        var machine = RFBDesktopResizeStateMachine()
        machine.resetForReconnect()
        machine.handleDesktopSizeResponse(Self.successResponse(1_280, 720))
        #expect(machine.request(Self.target) != nil)
        machine.markRequestSent(Self.target, now: 100)

        machine.handleDesktopSizeResponse(Self.successResponse(2_048, 1_152))
        #expect(machine.phase == .applied(RFBDesktopResizeTarget(widthInPixels: 2_048, heightInPixels: 1_152)))
    }

    private static func successResponse(_ width: Int, _ height: Int) -> RFBDesktopSizeResponse {
        RFBDesktopSizeResponse(
            width: width,
            height: height,
            reasonCode: 0,
            resultCode: 0,
            screens: [RFBScreenLayoutEntry(id: 0, x: 0, y: 0, width: width, height: height, flags: 0)]
        )
    }
}

@Suite("RFB SetDesktopSize wire contract")
struct RFBDesktopResizeWireTests {
    @Test("encodes SetDesktopSize with one screen covering the framebuffer")
    func encodesSetDesktopSize() {
        let message = RFBClientMessageBuilder.setDesktopSize(width: 1_600, height: 900)

        #expect(message.count == 24)
        #expect(Array(message.prefix(8)) == [
            251, 0,
            0x06, 0x40,
            0x03, 0x84,
            1, 0
        ])
        #expect(message.subdata(in: 8..<24) == RFBClientMessageBuilder.screenLayoutEntry(
            id: 0,
            x: 0,
            y: 0,
            width: 1_600,
            height: 900,
            flags: 0
        ))
    }

    @Test("advertises raw pixels plus ExtendedDesktopSize")
    func advertisesExtendedDesktopSize() {
        let encodings = RFBClientMessageBuilder.setRawAndDesktopResizeEncodings()
        #expect(encodings == Data([
            2, 0,
            0, 2,
            0, 0, 0, 0,
            0xFF, 0xFF, 0xFF, 0x21
        ]))
    }

    @Test("parses an ExtendedDesktopSize rectangle with screens")
    func parsesDesktopSizeResponse() throws {
        var header = Data()
        header.appendBigEndian(UInt16(0))      // reason: client
        header.appendBigEndian(UInt16(0))      // result: success
        header.appendBigEndian(UInt16(1_600))
        header.appendBigEndian(UInt16(900))
        header.appendBigEndian(Int32(rfbExtendedDesktopSizeEncoding))

        var payload = Data([1, 0, 0, 0])
        payload.append(RFBClientMessageBuilder.screenLayoutEntry(
            id: 7,
            x: 0,
            y: 0,
            width: 1_600,
            height: 900,
            flags: 1
        ))

        let response = try RFBFrameParser.parseDesktopSizeResponse(
            rectangleHeader: header,
            payload: payload
        )

        #expect(response.width == 1_600)
        #expect(response.height == 900)
        #expect(response.isSuccess)
        #expect(response.screens.count == 1)
        #expect(response.screens.first?.id == 7)
        #expect(response.matches(RFBDesktopResizeTarget(widthInPixels: 1_600, heightInPixels: 900)))
    }

    @Test("rejects a payload whose length disagrees with the screen count")
    func rejectsMalformedPayload() throws {
        var header = Data()
        header.appendBigEndian(UInt16(0))
        header.appendBigEndian(UInt16(0))
        header.appendBigEndian(UInt16(640))
        header.appendBigEndian(UInt16(480))
        header.appendBigEndian(Int32(rfbExtendedDesktopSizeEncoding))

        let payload = Data([2, 0, 0, 0]) + Data(repeating: 0, count: 16)

        #expect(throws: RFBError.malformedDesktopSizeResponse) {
            _ = try RFBFrameParser.parseDesktopSizeResponse(rectangleHeader: header, payload: payload)
        }
    }

    @Test("stream client negotiates resize capability and reads a desktop size event")
    func streamClientReadsDesktopSizeEvent() throws {
        let stream = FakeRFBByteStream(inbound: Self.resizingServerStreamData())
        let client = RFBFrameStreamClient(stream: stream)

        let serverInit = try client.startSharedSession()
        #expect(serverInit.width == 640)
        #expect(serverInit.height == 480)

        #expect(stream.writes[3] == RFBClientMessageBuilder.setRawAndDesktopResizeEncodings())

        try client.requestFramebufferUpdate(incremental: false)

        let event = try client.readUpdateEvent()
        guard case .desktopSize(let response) = event else {
            Issue.record("Expected a desktop size event")
            return
        }

        #expect(response.width == 800)
        #expect(response.height == 600)
        #expect(response.isSuccess)

        try client.applyDesktopSize(width: 800, height: 600)
        #expect(client.serverInit?.width == 800)
        #expect(client.serverInit?.height == 600)

        try client.sendSetDesktopSize(width: 800, height: 600)
        #expect(stream.writes.last == RFBClientMessageBuilder.setDesktopSize(width: 800, height: 600))
    }

    @Test("stream client still reads plain framebuffer updates")
    func streamClientReadsFramebufferEvent() throws {
        let stream = FakeRFBByteStream(inbound: Self.serverStreamData())
        let client = RFBFrameStreamClient(stream: stream)

        _ = try client.startSharedSession()
        try client.requestFramebufferUpdate(incremental: false)
        let event = try client.readUpdateEvent()

        guard case .framebuffer(let update) = event else {
            Issue.record("Expected a framebuffer event")
            return
        }

        #expect(update.rectangles.count == 1)
        #expect(update.rectangles.first?.pixels == Data([
            0, 0, 255, 0,
            0, 255, 0, 0
        ]))
    }

    @Test("an unsupported encoding still fails loudly")
    func unsupportedEncodingThrows() throws {
        var data = Data("RFB 003.008\n".utf8)
        data.append(contentsOf: [1, 1])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(Self.serverInitData(width: 2, height: 1, desktopName: "QEMU"))
        data.append(contentsOf: [
            0, 0,
            0, 1,
            0, 0,
            0, 0,
            0, 2,
            0, 1,
            0, 0, 0, 5
        ])

        let stream = FakeRFBByteStream(inbound: data)
        let client = RFBFrameStreamClient(stream: stream)
        _ = try client.startSharedSession()
        try client.requestFramebufferUpdate(incremental: false)

        #expect(throws: RFBError.unsupportedEncoding(5)) {
            _ = try client.readUpdateEvent()
        }
    }

    private static func serverInitData(width: UInt16, height: UInt16, desktopName: String) -> Data {
        var data = Data()
        data.appendBigEndian(width)
        data.appendBigEndian(height)
        data.append(contentsOf: [
            32,
            24,
            0,
            1,
            0, 255,
            0, 255,
            0, 255,
            16,
            8,
            0,
            0, 0, 0
        ])
        let nameBytes = Array(desktopName.utf8)
        data.appendBigEndian(UInt32(nameBytes.count))
        data.append(contentsOf: nameBytes)
        return data
    }

    /// Handshake for a 2x1 framebuffer followed by one raw rectangle.
    private static func serverStreamData() -> Data {
        var data = Data("RFB 003.008\n".utf8)
        data.append(contentsOf: [1, 1])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(serverInitData(width: 2, height: 1, desktopName: "QEMU"))
        data.append(contentsOf: [
            0, 0,
            0, 1,
            0, 0,
            0, 0,
            0, 2,
            0, 1,
            0, 0, 0, 0,
            0, 0, 255, 0,
            0, 255, 0, 0
        ])
        return data
    }

    /// Handshake followed by an ExtendedDesktopSize response advertising 800x600.
    private static func resizingServerStreamData() -> Data {
        var data = Data("RFB 003.008\n".utf8)
        data.append(contentsOf: [1, 1])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(serverInitData(width: 640, height: 480, desktopName: "QEMU"))
        data.append(contentsOf: [
            0, 0,
            0, 1,
            0, 0,
            0, 0,
            3, 32,
            2, 88,
            0xFF, 0xFF, 0xFF, 0x21
        ])
        data.append(contentsOf: [1, 0, 0, 0])
        data.append(RFBClientMessageBuilder.screenLayoutEntry(
            id: 0,
            x: 0,
            y: 0,
            width: 800,
            height: 600,
            flags: 0
        ))
        return data
    }
}

private final class FakeRFBByteStream: RFBByteStream {
    private var inbound: Data
    private var offset = 0
    private(set) var writes: [Data] = []

    init(inbound: Data) {
        self.inbound = inbound
    }

    func readExactly(_ byteCount: Int) throws -> Data {
        guard inbound.count >= offset + byteCount else {
            throw RFBLoopbackSocketError.connectionClosed
        }

        defer { offset += byteCount }
        return inbound.subdata(in: offset..<(offset + byteCount))
    }

    func write(_ data: Data) throws {
        writes.append(data)
    }

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

    mutating func appendBigEndian(_ value: Int32) {
        appendBigEndian(UInt32(bitPattern: value))
    }
}
