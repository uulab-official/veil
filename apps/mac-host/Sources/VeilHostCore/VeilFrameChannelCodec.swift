import Foundation

/// Binary wire format for window frame updates.
///
/// Frames used to travel as base64 inside a JSON object on the shared control connection. That cost 33%
/// inflation before a byte left the guest, forced the host to parse a multi-hundred-kilobyte JSON
/// document per frame to reach the image, and put large frames in front of input messages on the same
/// TCP stream.
///
/// Version 2 adds a dirty rectangle and a key-frame flag, so a changed window sends only the region that
/// changed instead of re-encoding every pixel. Typing one character in a 1920x1080 window used to
/// re-encode 2 million pixels to deliver a caret and a glyph.
///
/// Layout, network byte order throughout:
///
/// ```text
/// offset  size  field                                    v1   v2
/// 0       4     magic ("VFR1" or "VFR2")                  y    y
/// 4       1     payload format (1 = png)                  y    y
/// 5       1     flags (bit 0 = key frame)                  -    y
/// -       2     window id byte count (uint16)              y    y
/// -       n     window id, UTF-8                          y    y
/// -       4     sequence (uint32)                          y    y
/// -       4     surface width in pixels (uint32)           y    y
/// -       4     surface height in pixels (uint32)          y    y
/// -       4     DPI scale in thousandths (uint32)          y    y
/// -       2     tile x (uint16)                            -    y
/// -       2     tile y (uint16)                            -    y
/// -       2     tile width (uint16)                        -    y
/// -       2     tile height (uint16)                       -    y
/// -       4     payload byte count (uint32)                y    y
/// -       m     payload                                    y    y
/// ```
///
/// The DPI scale is an integer thousandth rather than a float so the format carries no floating point
/// representation or endianness ambiguity. `frameId` is deliberately absent: it is `frame_%06d` derived
/// from `sequence`, so sending it would be redundant bytes on the hot path.
///
/// The decoder accepts both versions. A `VFR1` message decodes as a key frame covering the whole surface,
/// so an agent caught mid-upgrade degrades to full frames rather than failing outright.
public enum VeilFrameChannelCodec {
    public static let magicV1 = Data("VFR1".utf8)
    public static let magicV2 = Data("VFR2".utf8)
    public static let pngFormat: UInt8 = 1
    public static let keyFrameFlag: UInt8 = 0x01
    /// v1: magic(4) + format(1) + idLength(2) + sequence(4) + width(4) + height(4) + scale(4) + payloadLength(4)
    public static let headerByteCountWithoutWindowIdV1 = 27
    /// v2 adds a flags byte and four uint16 rectangle fields.
    public static let headerByteCountWithoutWindowIdV2 = 36
    /// Guards against a malformed header advertising an absurd allocation, and keeps every rectangle
    /// field expressible in the uint16 the format allots.
    public static let maximumSurfaceDimension = 32_768

    /// Total pixels allowed in one surface, because bounding each side separately does not bound the
    /// allocation.
    ///
    /// 32768 on each axis permits 32768x32768, which is a 4 GiB bitmap context — and a 1-bit PNG of those
    /// dimensions deflates to roughly 130 KB, so it fits in a single WebSocket message. A guest could
    /// therefore trigger a multi-gigabyte host allocation with a tiny, entirely well-formed message that
    /// passes every other check: the rect fits, the key frame covers the surface, and the payload's real
    /// dimensions match the rect.
    ///
    /// 8K is 7680x4320, about 33 million pixels. This allows half again as much, so no legitimate window on
    /// any display Apple ships comes close, while the worst case becomes a 200 MB surface rather than 4 GB.
    public static let maximumSurfacePixelCount = 50_000_000
    public static let maximumPayloadByteCount = 64 * 1_024 * 1_024
    public static let maximumWindowIdByteCount = 512

    public enum CodecError: Error, LocalizedError, Equatable, Sendable {
        case badMagic
        case unsupportedFormat(UInt8)
        case truncated(expectedAtLeast: Int, actual: Int)
        case windowIdTooLong(Int)
        case invalidWindowId
        case emptyPayload
        case payloadLengthMismatch(declared: Int, available: Int)
        case implausibleSurface(width: Int, height: Int)
        case payloadTooLarge(Int)
        case unsupportedFrameFormat(String)
        case tileOutsideSurface(rect: WindowFrameTileRect, surfaceWidth: Int, surfaceHeight: Int)
        case keyFrameMustCoverSurface(rect: WindowFrameTileRect, surfaceWidth: Int, surfaceHeight: Int)

        public var errorDescription: String? {
            switch self {
            case .badMagic:
                "Frame channel message does not start with a recognized Veil frame magic."
            case .unsupportedFormat(let format):
                "Frame channel payload format \(format) is not supported."
            case .truncated(let expectedAtLeast, let actual):
                "Frame channel message is truncated: expected at least \(expectedAtLeast) bytes, got \(actual)."
            case .windowIdTooLong(let byteCount):
                "Frame channel window id is \(byteCount) bytes, above the allowed maximum."
            case .invalidWindowId:
                "Frame channel window id is empty or not valid UTF-8."
            case .emptyPayload:
                "Frame channel message carries no image payload."
            case .payloadLengthMismatch(let declared, let available):
                "Frame channel declared a \(declared) byte payload but \(available) bytes are present."
            case .implausibleSurface(let width, let height):
                "Frame channel surface size \(width)x\(height) is out of range."
            case .payloadTooLarge(let byteCount):
                "Frame channel payload of \(byteCount) bytes is above the allowed maximum."
            case .unsupportedFrameFormat(let format):
                "Frame format '\(format)' cannot be sent on the binary frame channel."
            case .tileOutsideSurface(let rect, let surfaceWidth, let surfaceHeight):
                "Frame tile \(rect.width)x\(rect.height) at \(rect.x),\(rect.y) does not fit a \(surfaceWidth)x\(surfaceHeight) surface."
            case .keyFrameMustCoverSurface(let rect, let surfaceWidth, let surfaceHeight):
                "A key frame must cover the whole surface, but \(rect.width)x\(rect.height) at \(rect.x),\(rect.y) does not cover \(surfaceWidth)x\(surfaceHeight)."
            }
        }
    }

    public static func encode(_ tile: WindowFrameTile) throws -> Data {
        guard !tile.payload.isEmpty else {
            throw CodecError.emptyPayload
        }
        guard tile.payload.count <= maximumPayloadByteCount else {
            throw CodecError.payloadTooLarge(tile.payload.count)
        }
        guard tile.surfaceWidth > 0,
              tile.surfaceHeight > 0,
              tile.surfaceWidth <= maximumSurfaceDimension,
              tile.surfaceHeight <= maximumSurfaceDimension,
              // Checked after the per-axis bounds so the product cannot overflow: both sides are already
              // known to be at most 32768, so the largest possible product is 2^30.
              tile.surfaceWidth * tile.surfaceHeight <= maximumSurfacePixelCount else {
            throw CodecError.implausibleSurface(width: tile.surfaceWidth, height: tile.surfaceHeight)
        }
        guard tile.rect.fits(surfaceWidth: tile.surfaceWidth, surfaceHeight: tile.surfaceHeight) else {
            throw CodecError.tileOutsideSurface(
                rect: tile.rect,
                surfaceWidth: tile.surfaceWidth,
                surfaceHeight: tile.surfaceHeight
            )
        }
        if tile.isKeyFrame,
           !tile.rect.covers(surfaceWidth: tile.surfaceWidth, surfaceHeight: tile.surfaceHeight) {
            throw CodecError.keyFrameMustCoverSurface(
                rect: tile.rect,
                surfaceWidth: tile.surfaceWidth,
                surfaceHeight: tile.surfaceHeight
            )
        }

        let windowIdBytes = Data(tile.windowId.utf8)
        guard !windowIdBytes.isEmpty else {
            throw CodecError.invalidWindowId
        }
        guard windowIdBytes.count <= maximumWindowIdByteCount else {
            throw CodecError.windowIdTooLong(windowIdBytes.count)
        }

        var message = Data()
        message.reserveCapacity(headerByteCountWithoutWindowIdV2 + windowIdBytes.count + tile.payload.count)
        message.append(magicV2)
        message.append(pngFormat)
        message.append(tile.isKeyFrame ? keyFrameFlag : 0)
        message.append(bigEndianUInt16(UInt16(windowIdBytes.count)))
        message.append(windowIdBytes)
        message.append(bigEndianUInt32(UInt32(max(0, tile.sequence))))
        message.append(bigEndianUInt32(UInt32(tile.surfaceWidth)))
        message.append(bigEndianUInt32(UInt32(tile.surfaceHeight)))
        message.append(bigEndianUInt32(UInt32(max(0, Int((tile.scale * 1_000).rounded())))))
        message.append(bigEndianUInt16(UInt16(tile.rect.x)))
        message.append(bigEndianUInt16(UInt16(tile.rect.y)))
        message.append(bigEndianUInt16(UInt16(tile.rect.width)))
        message.append(bigEndianUInt16(UInt16(tile.rect.height)))
        message.append(bigEndianUInt32(UInt32(tile.payload.count)))
        message.append(tile.payload)
        return message
    }

    public static func decode(_ message: Data) throws -> WindowFrameTile {
        // Indexing is done through a zero-based copy: a `Data` slice taken from a larger receive buffer
        // keeps non-zero start indices, and assuming zero here would read the wrong bytes.
        let bytes = [UInt8](message)

        guard bytes.count >= 4 else {
            throw CodecError.truncated(expectedAtLeast: headerByteCountWithoutWindowIdV1, actual: bytes.count)
        }

        let magic = Array(bytes[0..<4])
        let isVersion2: Bool
        if magic == [UInt8](magicV2) {
            isVersion2 = true
        } else if magic == [UInt8](magicV1) {
            isVersion2 = false
        } else {
            throw CodecError.badMagic
        }

        let fixedHeaderByteCount = isVersion2 ? headerByteCountWithoutWindowIdV2 : headerByteCountWithoutWindowIdV1
        guard bytes.count >= fixedHeaderByteCount else {
            throw CodecError.truncated(expectedAtLeast: fixedHeaderByteCount, actual: bytes.count)
        }
        guard bytes[4] == pngFormat else {
            throw CodecError.unsupportedFormat(bytes[4])
        }

        // v1 has no flags byte, so every v1 message is a full-surface key frame.
        let isKeyFrame = isVersion2 ? (bytes[5] & keyFrameFlag) != 0 : true
        var cursor = isVersion2 ? 6 : 5

        let windowIdByteCount = Int(readUInt16(bytes, at: cursor))
        cursor += 2
        guard windowIdByteCount > 0 else {
            throw CodecError.invalidWindowId
        }
        guard windowIdByteCount <= maximumWindowIdByteCount else {
            throw CodecError.windowIdTooLong(windowIdByteCount)
        }

        let headerByteCount = fixedHeaderByteCount + windowIdByteCount
        guard bytes.count >= headerByteCount else {
            throw CodecError.truncated(expectedAtLeast: headerByteCount, actual: bytes.count)
        }

        guard let windowId = String(bytes: bytes[cursor..<(cursor + windowIdByteCount)], encoding: .utf8),
              !windowId.isEmpty else {
            throw CodecError.invalidWindowId
        }
        cursor += windowIdByteCount

        let sequence = Int(readUInt32(bytes, at: cursor))
        cursor += 4
        let surfaceWidth = Int(readUInt32(bytes, at: cursor))
        cursor += 4
        let surfaceHeight = Int(readUInt32(bytes, at: cursor))
        cursor += 4
        let scaleThousandths = Int(readUInt32(bytes, at: cursor))
        cursor += 4

        guard surfaceWidth > 0,
              surfaceHeight > 0,
              surfaceWidth <= maximumSurfaceDimension,
              surfaceHeight <= maximumSurfaceDimension,
              // Checked after the per-axis bounds so the product cannot overflow: both sides are already
              // known to be at most 32768, so the largest possible product is 2^30.
              surfaceWidth * surfaceHeight <= maximumSurfacePixelCount else {
            throw CodecError.implausibleSurface(width: surfaceWidth, height: surfaceHeight)
        }

        let rect: WindowFrameTileRect
        if isVersion2 {
            let x = Int(readUInt16(bytes, at: cursor))
            let y = Int(readUInt16(bytes, at: cursor + 2))
            let width = Int(readUInt16(bytes, at: cursor + 4))
            let height = Int(readUInt16(bytes, at: cursor + 6))
            cursor += 8
            rect = WindowFrameTileRect(x: x, y: y, width: width, height: height)
        } else {
            rect = WindowFrameTileRect(x: 0, y: 0, width: surfaceWidth, height: surfaceHeight)
        }

        guard rect.fits(surfaceWidth: surfaceWidth, surfaceHeight: surfaceHeight) else {
            throw CodecError.tileOutsideSurface(
                rect: rect,
                surfaceWidth: surfaceWidth,
                surfaceHeight: surfaceHeight
            )
        }
        // A key frame that does not cover the surface would leave the compositor with undefined pixels
        // outside the rectangle and no way to know it.
        if isKeyFrame, !rect.covers(surfaceWidth: surfaceWidth, surfaceHeight: surfaceHeight) {
            throw CodecError.keyFrameMustCoverSurface(
                rect: rect,
                surfaceWidth: surfaceWidth,
                surfaceHeight: surfaceHeight
            )
        }

        let payloadByteCount = Int(readUInt32(bytes, at: cursor))
        cursor += 4

        guard payloadByteCount > 0 else {
            throw CodecError.emptyPayload
        }
        guard payloadByteCount <= maximumPayloadByteCount else {
            throw CodecError.payloadTooLarge(payloadByteCount)
        }

        let available = bytes.count - cursor
        // Strict equality, not `>=`: a declared length shorter than the buffer means the sender and
        // receiver disagree about framing, and silently ignoring the tail would hide that.
        guard available == payloadByteCount else {
            throw CodecError.payloadLengthMismatch(declared: payloadByteCount, available: available)
        }

        return WindowFrameTile(
            windowId: windowId,
            sequence: sequence,
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight,
            // A scale of zero would mean the sender omitted it; 1.0 is the honest default and matches what
            // a DPI-unaware guest reports.
            scale: scaleThousandths == 0 ? 1 : Double(scaleThousandths) / 1_000,
            isKeyFrame: isKeyFrame,
            rect: rect,
            payload: Data(bytes[cursor..<(cursor + payloadByteCount)])
        )
    }

    /// Matches the guest's `frame_{sequence:000000}` format, so a frame that arrives over the binary
    /// channel is indistinguishable downstream from one that arrived as JSON.
    public static func frameId(for sequence: Int) -> String {
        String(format: "frame_%06d", sequence)
    }

    private static func bigEndianUInt16(_ value: UInt16) -> Data {
        Data([UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }

    private static func bigEndianUInt32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value)
        ])
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}
