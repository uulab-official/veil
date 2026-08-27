import Foundation

/// Rectangle within a window surface, in guest pixels.
public struct WindowFrameTileRect: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    /// Whether this rectangle fits entirely inside a surface of the given size.
    ///
    /// Uses reported arithmetic so a crafted or corrupt header cannot trap on overflow: the maximum
    /// surface dimension is small enough that a legitimate rectangle can never overflow, so an overflow
    /// here is itself grounds for rejection.
    public func fits(surfaceWidth: Int, surfaceHeight: Int) -> Bool {
        guard !isEmpty, x >= 0, y >= 0 else {
            return false
        }

        let (right, rightOverflow) = x.addingReportingOverflow(width)
        let (bottom, bottomOverflow) = y.addingReportingOverflow(height)
        guard !rightOverflow, !bottomOverflow else {
            return false
        }

        return right <= surfaceWidth && bottom <= surfaceHeight
    }

    public func covers(surfaceWidth: Int, surfaceHeight: Int) -> Bool {
        x == 0 && y == 0 && width == surfaceWidth && height == surfaceHeight
    }
}

/// One frame update: either a key frame carrying the whole surface, or a tile carrying only the region
/// that changed.
///
/// Deliberately a distinct type from `WindowFrameEvent`. A tile is not a frame, and treating one as a
/// frame is exactly how a small update ends up stretched across an entire mirrored window. Callers must
/// go through `WindowFrameCompositor` to turn a sequence of these into something displayable.
public struct WindowFrameTile: Equatable, Sendable {
    public var windowId: String
    public var sequence: Int
    public var surfaceWidth: Int
    public var surfaceHeight: Int
    public var scale: Double
    public var isKeyFrame: Bool
    public var rect: WindowFrameTileRect
    /// PNG bytes covering exactly `rect`.
    public var payload: Data

    public init(
        windowId: String,
        sequence: Int,
        surfaceWidth: Int,
        surfaceHeight: Int,
        scale: Double,
        isKeyFrame: Bool,
        rect: WindowFrameTileRect,
        payload: Data
    ) {
        self.windowId = windowId
        self.sequence = sequence
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
        self.scale = scale
        self.isKeyFrame = isKeyFrame
        self.rect = rect
        self.payload = payload
    }

    /// Metadata-only frame event describing the composited surface after this tile is applied.
    ///
    /// `encodedData` is intentionally empty: the displayable pixels live in the compositor, and copying a
    /// full-surface PNG into every session update is the cost this slice exists to remove. Everything the
    /// status contract reads -- window id, sequence, surface size, scale -- is present.
    public func surfaceMetadataFrameEvent() -> WindowFrameEvent {
        WindowFrameEvent(
            type: .windowFrame,
            windowId: windowId,
            frameId: VeilFrameChannelCodec.frameId(for: sequence),
            sequence: sequence,
            format: WindowFrameEvent.compositedSurfaceFormat,
            width: surfaceWidth,
            height: surfaceHeight,
            scale: scale,
            encodedData: ""
        )
    }
}

public extension WindowFrameEvent {
    /// Marks a frame event whose pixels live in the host compositor rather than in `encodedData`.
    ///
    /// Renderers must check this before trying to decode `encodedData`, which is empty for these.
    static let compositedSurfaceFormat = "composited"

    var isCompositedSurface: Bool {
        format == Self.compositedSurfaceFormat
    }

    /// Treats a self-contained PNG frame as a key-frame tile, so JSON-delivered frames and
    /// binary-delivered key frames can share one compositing path.
    func asKeyFrameTile() -> WindowFrameTile? {
        guard format == "png",
              let payload = encodedPayloadData,
              !payload.isEmpty,
              width > 0,
              height > 0 else {
            return nil
        }

        return WindowFrameTile(
            windowId: windowId,
            sequence: sequence,
            surfaceWidth: width,
            surfaceHeight: height,
            scale: scale,
            isKeyFrame: true,
            rect: WindowFrameTileRect(x: 0, y: 0, width: width, height: height),
            payload: payload
        )
    }
}
