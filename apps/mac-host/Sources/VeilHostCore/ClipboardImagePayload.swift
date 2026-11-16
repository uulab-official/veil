import CryptoKit
import Foundation

public enum ClipboardImagePayloadError: Error, Equatable, LocalizedError, Sendable {
    case notPNG
    case tooLarge(byteCount: Int)
    case dimensionsOutOfBounds(width: Int, height: Int)
    case unsupportedFormat(String)
    case invalidBase64
    case byteLengthMismatch(declared: Int, actual: Int)
    case hashMismatch
    case dimensionsMismatch

    public var errorDescription: String? {
        switch self {
        case .notPNG:
            "The clipboard image is not a PNG."
        case .tooLarge(let byteCount):
            "The clipboard image is \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)), above the \(ByteCountFormatter.string(fromByteCount: Int64(ClipboardImagePayload.maximumByteCount), countStyle: .file)) Veil sends to Windows."
        case .dimensionsOutOfBounds(let width, let height):
            "The clipboard image is \(width)×\(height) pixels, larger than Veil sends to Windows."
        case .unsupportedFormat(let format):
            "The clipboard image format '\(format)' is not supported."
        case .invalidBase64:
            "The clipboard image data is not valid base64."
        case .byteLengthMismatch:
            "The clipboard image size does not match its declared length."
        case .hashMismatch:
            "The clipboard image does not match its declared hash."
        case .dimensionsMismatch:
            "The clipboard image dimensions do not match its PNG header."
        }
    }
}

/// A PNG clipboard image checked against the bounds in `docs/protocol.md` "Clipboard Image".
///
/// Both directions go through here: the host builds one from the Mac pasteboard before sending, and
/// verifies one from the guest before it reaches `NSPasteboard`. The guest chooses the bytes, so nothing
/// about them is trusted until the signature, the declared length, the hash, and the IHDR dimensions agree.
public struct ClipboardImagePayload: Equatable, Sendable {
    /// 8 MiB of PNG. Base64 makes the frame about 11.2 MB, which the transport's receive limit covers.
    public static let maximumByteCount = 8 * 1_024 * 1_024
    public static let maximumDimension = 16_384
    /// A small PNG can decode to an enormous bitmap; this caps the decoded size at 128 MB of RGBA.
    public static let maximumPixelCount = 33_554_432

    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    public let png: Data
    public let width: Int
    public let height: Int
    public let sha256: String

    public init(png: Data) throws(ClipboardImagePayloadError) {
        guard png.count <= Self.maximumByteCount else {
            throw .tooLarge(byteCount: png.count)
        }
        let (width, height) = try Self.headerDimensions(of: png)
        guard Self.dimensionsAreAllowed(width: width, height: height) else {
            throw .dimensionsOutOfBounds(width: width, height: height)
        }

        self.png = png
        self.width = width
        self.height = height
        self.sha256 = Self.hexDigest(of: png)
    }

    /// Verifies a received message. Every declared field has to agree with the bytes themselves.
    public init(message: ClipboardImageSet) throws(ClipboardImagePayloadError) {
        guard message.format == "png" else {
            throw .unsupportedFormat(message.format)
        }
        // Checked before decoding so an oversized declaration never allocates its claimed size.
        guard message.byteLength >= 1, message.byteLength <= Self.maximumByteCount,
              message.pngBase64.utf8.count <= (Self.maximumByteCount + 2) / 3 * 4 else {
            throw .tooLarge(byteCount: message.byteLength)
        }
        guard Self.dimensionsAreAllowed(width: message.width, height: message.height) else {
            throw .dimensionsOutOfBounds(width: message.width, height: message.height)
        }
        guard let png = Data(base64Encoded: message.pngBase64) else {
            throw .invalidBase64
        }
        guard png.count == message.byteLength else {
            throw .byteLengthMismatch(declared: message.byteLength, actual: png.count)
        }

        try self.init(png: png)
        guard sha256 == message.sha256 else {
            throw .hashMismatch
        }
        guard width == message.width, height == message.height else {
            throw .dimensionsMismatch
        }
    }

    public func message(requestId: String, origin: String, sequence: Int) -> ClipboardImageSet {
        ClipboardImageSet(
            requestId: requestId,
            origin: origin,
            sequence: sequence,
            width: width,
            height: height,
            byteLength: png.count,
            sha256: sha256,
            pngBase64: png.base64EncodedString()
        )
    }

    static func dimensionsAreAllowed(width: Int, height: Int) -> Bool {
        (1...maximumDimension).contains(width)
            && (1...maximumDimension).contains(height)
            && width * height <= maximumPixelCount
    }

    /// Reads width and height from the IHDR chunk, which the PNG specification requires to come first.
    static func headerDimensions(of png: Data) throws(ClipboardImagePayloadError) -> (Int, Int) {
        let bytes = [UInt8](png.prefix(24))
        guard bytes.count == 24,
              Array(bytes[0..<8]) == signature,
              Array(bytes[12..<16]) == Array("IHDR".utf8) else {
            throw .notPNG
        }

        func bigEndian(_ offset: Int) -> Int {
            bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        return (bigEndian(16), bigEndian(20))
    }

    static func hexDigest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
