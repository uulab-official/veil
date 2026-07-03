import Darwin
import Foundation

public enum RFBError: Error, LocalizedError, Equatable, Sendable {
    case messageTooShort(expected: Int, actual: Int)
    case unsupportedProtocol(String)
    case unsupportedSecurityType(UInt8)
    case authenticationFailed(UInt32)
    case unsupportedServerMessage(UInt8)
    case unsupportedEncoding(Int32)
    case invalidPixelFormatBitsPerPixel(UInt8)
    case sessionNotStarted
    case invalidRectangleBounds

    public var errorDescription: String? {
        switch self {
        case .messageTooShort(let expected, let actual):
            "RFB message is too short. Expected at least \(expected) bytes but received \(actual)."
        case .unsupportedProtocol(let version):
            "Unsupported RFB protocol version '\(version)'."
        case .unsupportedSecurityType(let type):
            "Unsupported RFB security type \(type)."
        case .authenticationFailed(let status):
            "RFB security handshake failed with status \(status)."
        case .unsupportedServerMessage(let type):
            "Unsupported RFB server message type \(type)."
        case .unsupportedEncoding(let encoding):
            "Unsupported RFB rectangle encoding \(encoding)."
        case .invalidPixelFormatBitsPerPixel(let bitsPerPixel):
            "Unsupported RFB pixel format depth \(bitsPerPixel)."
        case .sessionNotStarted:
            "RFB framebuffer updates cannot be read before the server init handshake completes."
        case .invalidRectangleBounds:
            "RFB framebuffer update contains a rectangle outside the display bounds."
        }
    }
}

public enum RFBLoopbackSocketError: Error, LocalizedError, Equatable, Sendable {
    case invalidEndpoint(String)
    case socketOperationFailed(String)
    case connectionClosed

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let endpoint):
            "Invalid RFB loopback endpoint '\(endpoint)'."
        case .socketOperationFailed(let operation):
            "RFB loopback socket operation failed: \(operation)."
        case .connectionClosed:
            "RFB loopback socket closed before the requested bytes were received."
        }
    }
}

public struct RFBPixelFormat: Codable, Equatable, Sendable {
    public var bitsPerPixel: UInt8
    public var depth: UInt8
    public var isBigEndian: Bool
    public var isTrueColor: Bool
    public var redMax: UInt16
    public var greenMax: UInt16
    public var blueMax: UInt16
    public var redShift: UInt8
    public var greenShift: UInt8
    public var blueShift: UInt8

    public init(
        bitsPerPixel: UInt8,
        depth: UInt8,
        isBigEndian: Bool,
        isTrueColor: Bool,
        redMax: UInt16,
        greenMax: UInt16,
        blueMax: UInt16,
        redShift: UInt8,
        greenShift: UInt8,
        blueShift: UInt8
    ) {
        self.bitsPerPixel = bitsPerPixel
        self.depth = depth
        self.isBigEndian = isBigEndian
        self.isTrueColor = isTrueColor
        self.redMax = redMax
        self.greenMax = greenMax
        self.blueMax = blueMax
        self.redShift = redShift
        self.greenShift = greenShift
        self.blueShift = blueShift
    }

    public var bytesPerPixel: Int? {
        guard bitsPerPixel % 8 == 0 else {
            return nil
        }

        return Int(bitsPerPixel / 8)
    }
}

public struct RFBServerInit: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var pixelFormat: RFBPixelFormat
    public var desktopName: String
}

public struct RFBRawRectangle: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var pixels: Data
}

public struct RFBFramebufferUpdate: Codable, Equatable, Sendable {
    public var rectangles: [RFBRawRectangle]
}

public struct RFBRenderedFrame: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgbaPixels: Data
    public var sequence: Int
}

public enum RFBClientMessageBuilder {
    public static func clientProtocolVersion() -> Data {
        Data("RFB 003.008\n".utf8)
    }

    public static func selectNoneSecurity() -> Data {
        Data([1])
    }

    public static func sharedClientInit() -> Data {
        Data([1])
    }

    public static func framebufferUpdateRequest(
        incremental: Bool,
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16
    ) -> Data {
        var data = Data([3, incremental ? 1 : 0])
        data.appendBigEndian(x)
        data.appendBigEndian(y)
        data.appendBigEndian(width)
        data.appendBigEndian(height)
        return data
    }
}

public enum RFBFrameParser {
    public static func parseProtocolVersion(_ data: Data) throws -> String {
        try require(data, count: 12)
        let version = String(decoding: data.prefix(12), as: UTF8.self)
        guard version == "RFB 003.008\n" || version == "RFB 003.007\n" else {
            throw RFBError.unsupportedProtocol(version.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return version
    }

    public static func parseSecurityTypes(_ data: Data) throws -> [UInt8] {
        try require(data, count: 1)
        let count = Int(data[0])
        try require(data, count: 1 + count)
        let types = Array(data.dropFirst().prefix(count))
        guard types.contains(1) else {
            throw RFBError.unsupportedSecurityType(types.first ?? 0)
        }
        return types
    }

    public static func parseSecurityResult(_ data: Data) throws {
        var reader = RFBReader(data: data)
        let status = try reader.readUInt32()
        guard status == 0 else {
            throw RFBError.authenticationFailed(status)
        }
    }

    public static func parseServerInit(_ data: Data) throws -> RFBServerInit {
        var reader = RFBReader(data: data)
        let width = Int(try reader.readUInt16())
        let height = Int(try reader.readUInt16())
        let pixelFormat = try reader.readPixelFormat()
        let nameLength = Int(try reader.readUInt32())
        let desktopNameData = try reader.readData(count: nameLength)
        return RFBServerInit(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            desktopName: String(decoding: desktopNameData, as: UTF8.self)
        )
    }

    public static func parseFramebufferUpdate(
        _ data: Data,
        pixelFormat: RFBPixelFormat
    ) throws -> RFBFramebufferUpdate {
        guard let bytesPerPixel = pixelFormat.bytesPerPixel else {
            throw RFBError.invalidPixelFormatBitsPerPixel(pixelFormat.bitsPerPixel)
        }

        var reader = RFBReader(data: data)
        let messageType = try reader.readUInt8()
        guard messageType == 0 else {
            throw RFBError.unsupportedServerMessage(messageType)
        }
        _ = try reader.readUInt8()
        let rectangleCount = Int(try reader.readUInt16())
        var rectangles: [RFBRawRectangle] = []
        rectangles.reserveCapacity(rectangleCount)

        for _ in 0..<rectangleCount {
            let x = Int(try reader.readUInt16())
            let y = Int(try reader.readUInt16())
            let width = Int(try reader.readUInt16())
            let height = Int(try reader.readUInt16())
            let encoding = try reader.readInt32()
            guard encoding == 0 else {
                throw RFBError.unsupportedEncoding(encoding)
            }

            let pixelByteCount = width * height * bytesPerPixel
            let pixels = try reader.readData(count: pixelByteCount)
            rectangles.append(RFBRawRectangle(
                x: x,
                y: y,
                width: width,
                height: height,
                pixels: pixels
            ))
        }

        return RFBFramebufferUpdate(rectangles: rectangles)
    }

    private static func require(_ data: Data, count: Int) throws {
        guard data.count >= count else {
            throw RFBError.messageTooShort(expected: count, actual: data.count)
        }
    }
}

public protocol RFBByteStream: AnyObject {
    func readExactly(_ byteCount: Int) throws -> Data
    func write(_ data: Data) throws
    func close()
}

public final class RFBLoopbackSocket: RFBByteStream {
    private var fileDescriptor: Int32 = -1

    public init(host: String, port: Int, timeoutSeconds: Int = 3) throws {
        guard port > 0 && port <= 65_535 else {
            throw RFBLoopbackSocketError.invalidEndpoint("\(host):\(port)")
        }

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw RFBLoopbackSocketError.socketOperationFailed(Self.lastErrnoDescription("socket"))
        }
        fileDescriptor = descriptor

        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian

        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            close()
            throw RFBLoopbackSocketError.invalidEndpoint("\(host):\(port)")
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fileDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result == 0 else {
            let reason = Self.lastErrnoDescription("connect")
            close()
            throw RFBLoopbackSocketError.socketOperationFailed(reason)
        }
    }

    deinit {
        close()
    }

    public func readExactly(_ byteCount: Int) throws -> Data {
        guard byteCount >= 0 else {
            throw RFBError.messageTooShort(expected: 0, actual: byteCount)
        }

        var buffer = [UInt8](repeating: 0, count: byteCount)
        var bytesRead = 0

        while bytesRead < byteCount {
            let result = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fileDescriptor, rawBuffer.baseAddress!.advanced(by: bytesRead), byteCount - bytesRead)
            }

            if result == 0 {
                throw RFBLoopbackSocketError.connectionClosed
            }

            if result < 0 {
                throw RFBLoopbackSocketError.socketOperationFailed(Self.lastErrnoDescription("read"))
            }

            bytesRead += result
        }

        return Data(buffer)
    }

    public func write(_ data: Data) throws {
        var bytesWritten = 0

        try data.withUnsafeBytes { rawBuffer in
            while bytesWritten < data.count {
                let result = Darwin.write(
                    fileDescriptor,
                    rawBuffer.baseAddress!.advanced(by: bytesWritten),
                    data.count - bytesWritten
                )

                if result == 0 {
                    throw RFBLoopbackSocketError.connectionClosed
                }

                if result < 0 {
                    throw RFBLoopbackSocketError.socketOperationFailed(Self.lastErrnoDescription("write"))
                }

                bytesWritten += result
            }
        }
    }

    public func close() {
        guard fileDescriptor >= 0 else {
            return
        }

        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }

    private static func lastErrnoDescription(_ operation: String) -> String {
        "\(operation): \(String(cString: strerror(errno)))"
    }
}

public final class RFBFrameStreamClient {
    private let stream: RFBByteStream
    public private(set) var serverInit: RFBServerInit?

    public init(stream: RFBByteStream) {
        self.stream = stream
    }

    public func startSharedSession() throws -> RFBServerInit {
        _ = try RFBFrameParser.parseProtocolVersion(stream.readExactly(12))
        try stream.write(RFBClientMessageBuilder.clientProtocolVersion())

        let securityCountData = try stream.readExactly(1)
        let securityCount = Int(securityCountData[0])
        let securityTypesData = try stream.readExactly(securityCount)
        _ = try RFBFrameParser.parseSecurityTypes(securityCountData + securityTypesData)
        try stream.write(RFBClientMessageBuilder.selectNoneSecurity())

        try RFBFrameParser.parseSecurityResult(stream.readExactly(4))
        try stream.write(RFBClientMessageBuilder.sharedClientInit())

        let serverInitHeader = try stream.readExactly(24)
        let desktopNameLength = Int(serverInitHeader.readUInt32BigEndian(at: 20))
        let desktopNameData = try stream.readExactly(desktopNameLength)
        let serverInit = try RFBFrameParser.parseServerInit(serverInitHeader + desktopNameData)
        self.serverInit = serverInit
        return serverInit
    }

    public func requestFramebufferUpdate(incremental: Bool = true) throws {
        guard let serverInit else {
            throw RFBError.sessionNotStarted
        }

        try stream.write(RFBClientMessageBuilder.framebufferUpdateRequest(
            incremental: incremental,
            x: 0,
            y: 0,
            width: UInt16(serverInit.width),
            height: UInt16(serverInit.height)
        ))
    }

    public func readFramebufferUpdate() throws -> RFBFramebufferUpdate {
        guard let serverInit else {
            throw RFBError.sessionNotStarted
        }
        guard let bytesPerPixel = serverInit.pixelFormat.bytesPerPixel else {
            throw RFBError.invalidPixelFormatBitsPerPixel(serverInit.pixelFormat.bitsPerPixel)
        }

        let messageHeader = try stream.readExactly(4)
        let rectangleCount = Int(messageHeader.readUInt16BigEndian(at: 2))
        var update = messageHeader

        for _ in 0..<rectangleCount {
            let rectangleHeader = try stream.readExactly(12)
            update.append(rectangleHeader)

            let width = Int(rectangleHeader.readUInt16BigEndian(at: 4))
            let height = Int(rectangleHeader.readUInt16BigEndian(at: 6))
            let encoding = rectangleHeader.readInt32BigEndian(at: 8)

            guard encoding == 0 else {
                return try RFBFrameParser.parseFramebufferUpdate(update, pixelFormat: serverInit.pixelFormat)
            }

            let pixelByteCount = width * height * bytesPerPixel
            update.append(try stream.readExactly(pixelByteCount))
        }

        return try RFBFrameParser.parseFramebufferUpdate(update, pixelFormat: serverInit.pixelFormat)
    }
}

public final class RFBFramebufferRenderer {
    public let width: Int
    public let height: Int

    private let pixelFormat: RFBPixelFormat
    private var rgbaPixels: [UInt8]
    private var sequence = 0

    public init(serverInit: RFBServerInit) throws {
        guard serverInit.pixelFormat.bytesPerPixel != nil else {
            throw RFBError.invalidPixelFormatBitsPerPixel(serverInit.pixelFormat.bitsPerPixel)
        }

        self.width = serverInit.width
        self.height = serverInit.height
        self.pixelFormat = serverInit.pixelFormat
        self.rgbaPixels = [UInt8](repeating: 0, count: serverInit.width * serverInit.height * 4)
    }

    public func apply(_ update: RFBFramebufferUpdate) throws -> RFBRenderedFrame {
        guard let bytesPerPixel = pixelFormat.bytesPerPixel else {
            throw RFBError.invalidPixelFormatBitsPerPixel(pixelFormat.bitsPerPixel)
        }

        for rectangle in update.rectangles {
            guard rectangle.x >= 0,
                  rectangle.y >= 0,
                  rectangle.width >= 0,
                  rectangle.height >= 0,
                  rectangle.x + rectangle.width <= width,
                  rectangle.y + rectangle.height <= height else {
                throw RFBError.invalidRectangleBounds
            }

            let expectedPixelByteCount = rectangle.width * rectangle.height * bytesPerPixel
            guard rectangle.pixels.count >= expectedPixelByteCount else {
                throw RFBError.messageTooShort(expected: expectedPixelByteCount, actual: rectangle.pixels.count)
            }

            for row in 0..<rectangle.height {
                for column in 0..<rectangle.width {
                    let sourceOffset = ((row * rectangle.width) + column) * bytesPerPixel
                    let destinationX = rectangle.x + column
                    let destinationY = rectangle.y + row
                    let destinationOffset = ((destinationY * width) + destinationX) * 4
                    let pixelValue = rectangle.pixels.rfbPixelValue(
                        at: sourceOffset,
                        bytesPerPixel: bytesPerPixel,
                        isBigEndian: pixelFormat.isBigEndian
                    )

                    rgbaPixels[destinationOffset] = Self.component(
                        from: pixelValue,
                        shift: pixelFormat.redShift,
                        max: pixelFormat.redMax
                    )
                    rgbaPixels[destinationOffset + 1] = Self.component(
                        from: pixelValue,
                        shift: pixelFormat.greenShift,
                        max: pixelFormat.greenMax
                    )
                    rgbaPixels[destinationOffset + 2] = Self.component(
                        from: pixelValue,
                        shift: pixelFormat.blueShift,
                        max: pixelFormat.blueMax
                    )
                    rgbaPixels[destinationOffset + 3] = 255
                }
            }
        }

        sequence += 1
        return RFBRenderedFrame(
            width: width,
            height: height,
            rgbaPixels: Data(rgbaPixels),
            sequence: sequence
        )
    }

    private static func component(from pixelValue: UInt32, shift: UInt8, max: UInt16) -> UInt8 {
        guard max > 0 else {
            return 0
        }

        let rawComponent = (pixelValue >> UInt32(shift)) & UInt32(max)
        return UInt8((rawComponent * 255) / UInt32(max))
    }
}

private struct RFBReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readUInt8() throws -> UInt8 {
        try require(count: 1)
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        try require(count: 2)
        defer { offset += 2 }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    mutating func readUInt32() throws -> UInt32 {
        try require(count: 4)
        defer { offset += 4 }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    mutating func readInt32() throws -> Int32 {
        Int32(bitPattern: try readUInt32())
    }

    mutating func readData(count: Int) throws -> Data {
        try require(count: count)
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readPixelFormat() throws -> RFBPixelFormat {
        let bitsPerPixel = try readUInt8()
        let depth = try readUInt8()
        let isBigEndian = try readUInt8() != 0
        let isTrueColor = try readUInt8() != 0
        let redMax = try readUInt16()
        let greenMax = try readUInt16()
        let blueMax = try readUInt16()
        let redShift = try readUInt8()
        let greenShift = try readUInt8()
        let blueShift = try readUInt8()
        _ = try readData(count: 3)
        return RFBPixelFormat(
            bitsPerPixel: bitsPerPixel,
            depth: depth,
            isBigEndian: isBigEndian,
            isTrueColor: isTrueColor,
            redMax: redMax,
            greenMax: greenMax,
            blueMax: blueMax,
            redShift: redShift,
            greenShift: greenShift,
            blueShift: blueShift
        )
    }

    private func require(count: Int) throws {
        guard data.count >= offset + count else {
            throw RFBError.messageTooShort(expected: offset + count, actual: data.count)
        }
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    func readUInt16BigEndian(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func readUInt32BigEndian(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func readInt32BigEndian(at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32BigEndian(at: offset))
    }

    func rfbPixelValue(at offset: Int, bytesPerPixel: Int, isBigEndian: Bool) -> UInt32 {
        var value: UInt32 = 0

        for byteIndex in 0..<bytesPerPixel {
            let sourceIndex = isBigEndian ? offset + byteIndex : offset + (bytesPerPixel - 1 - byteIndex)
            value = (value << 8) | UInt32(self[sourceIndex])
        }

        return value
    }
}
