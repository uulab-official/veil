import Foundation

public enum RFBError: Error, LocalizedError, Equatable, Sendable {
    case messageTooShort(expected: Int, actual: Int)
    case unsupportedProtocol(String)
    case unsupportedSecurityType(UInt8)
    case authenticationFailed(UInt32)
    case unsupportedServerMessage(UInt8)
    case unsupportedEncoding(Int32)
    case invalidPixelFormatBitsPerPixel(UInt8)

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
        guard version == "RFB 003.008\n" || version == "RFB 003.007\n" || version == "RFB 003.003\n" else {
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
}
