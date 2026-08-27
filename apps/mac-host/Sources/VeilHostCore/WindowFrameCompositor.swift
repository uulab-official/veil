import CoreGraphics
import Foundation
import ImageIO

/// Keeps one composited surface per mirrored window and applies incoming tiles to it.
///
/// This is what makes dirty-rect tiles possible: the guest sends only the region that changed, and the
/// authoritative full-window image lives here. It also removes the host's per-frame full-surface PNG
/// decode, because only the tile is decoded.
///
/// A tile that cannot be safely composited is rejected rather than approximated. Drawing a tile onto a
/// surface of the wrong size, or onto no surface at all, produces a plausible-looking but wrong window,
/// which is far harder to diagnose than a window that visibly waits for a key frame.
public final class WindowFrameCompositor: @unchecked Sendable {
    public enum ApplyResult: Equatable, Sendable {
        /// The surface now reflects this tile.
        case composited(generation: Int)
        /// The tile could not be applied and a key frame is required before this window can be shown.
        case needsKeyFrame(reason: RejectionReason)
    }

    public enum RejectionReason: String, Equatable, Sendable {
        /// A tile arrived before any key frame, so there is nothing to composite onto.
        case noSurface
        /// The declared surface size changed without a key frame to re-establish it.
        case surfaceSizeChanged
        /// The tile payload could not be decoded as an image.
        case undecodablePayload
        /// The decoded image dimensions disagree with the declared rectangle.
        case payloadRectMismatch
    }

    private struct Surface {
        var context: CGContext
        var width: Int
        var height: Int
        var generation: Int
    }

    /// How many window surfaces are kept at once.
    ///
    /// Each surface is a full-resolution bitmap, so the count is a memory bound, not a preference. Callers do
    /// not all provide one: the app path only composites tiles whose window id matches a tracked mirror
    /// session, but `veil-vmctl frame-pipeline-measure` composites straight off the guest channel with no such
    /// gate. A guest inventing a fresh window id per message would otherwise allocate a new surface for each.
    ///
    /// 16 is twice the per-app window bound, so it is above anything the app path can produce while still
    /// bounding the diagnostic path.
    public static let maximumSurfaceCount = 16

    private let lock = NSLock()
    private var surfacesByWindowId: [String: Surface] = [:]
    /// Least-recently-composited first. Kept alongside the dictionary so the bound can evict rather than
    /// refuse: a window whose surface was evicted asks for a key frame through the existing `.noSurface`
    /// path, which is already how a window that has never had a surface behaves.
    private var surfaceOrder: [String] = []
    private let decodeImage: @Sendable (Data) -> CGImage?

    public init(decodeImage: @escaping @Sendable (Data) -> CGImage? = WindowFrameCompositor.decodePNG) {
        self.decodeImage = decodeImage
    }

    /// Applies a tile, creating or replacing the surface when the tile is a key frame.
    @discardableResult
    public func apply(_ tile: WindowFrameTile) -> ApplyResult {
        guard let image = decodeImage(tile.payload) else {
            return .needsKeyFrame(reason: .undecodablePayload)
        }

        // The rectangle is what tells the compositor where to draw. If the payload's real size disagrees,
        // one of the two is wrong and scaling to fit would silently distort the window.
        guard image.width == tile.rect.width, image.height == tile.rect.height else {
            return .needsKeyFrame(reason: .payloadRectMismatch)
        }

        lock.lock()
        defer { lock.unlock() }

        var surface = surfacesByWindowId[tile.windowId]

        if tile.isKeyFrame {
            guard let context = Self.makeContext(width: tile.surfaceWidth, height: tile.surfaceHeight) else {
                return .needsKeyFrame(reason: .noSurface)
            }
            // Evicted before allocating, so the peak is the bound rather than the bound plus one.
            if surface == nil {
                evictOldestSurfacesIfNeeded(makingRoomFor: tile.windowId)
            }
            surface = Surface(
                context: context,
                width: tile.surfaceWidth,
                height: tile.surfaceHeight,
                generation: (surface?.generation ?? 0)
            )
        }

        guard var existing = surface else {
            return .needsKeyFrame(reason: .noSurface)
        }

        guard existing.width == tile.surfaceWidth, existing.height == tile.surfaceHeight else {
            // A resize invalidates every retained pixel. Dropping the surface forces the guest's next key
            // frame to re-establish it instead of compositing onto a mismatched buffer.
            surfacesByWindowId.removeValue(forKey: tile.windowId)
            surfaceOrder.removeAll { $0 == tile.windowId }
            return .needsKeyFrame(reason: .surfaceSizeChanged)
        }

        // CoreGraphics origin is bottom-left; guest rectangles are top-left. Flipping here keeps the tile
        // coordinate space identical to what Windows reported.
        let drawRect = CGRect(
            x: CGFloat(tile.rect.x),
            y: CGFloat(existing.height - tile.rect.y - tile.rect.height),
            width: CGFloat(tile.rect.width),
            height: CGFloat(tile.rect.height)
        )
        // Replace rather than blend: a tile is the new truth for its rectangle, and source-over would let
        // a partially transparent capture leave the previous content showing through.
        existing.context.setBlendMode(.copy)
        existing.context.draw(image, in: drawRect)
        existing.generation += 1
        surfacesByWindowId[tile.windowId] = existing
        touchSurfaceOrder(tile.windowId)
        return .composited(generation: existing.generation)
    }

    /// Marks a window as most recently composited. Called under `lock`.
    private func touchSurfaceOrder(_ windowId: String) {
        surfaceOrder.removeAll { $0 == windowId }
        surfaceOrder.append(windowId)
    }

    /// Drops least-recently-composited surfaces until there is room for one more. Called under `lock`.
    private func evictOldestSurfacesIfNeeded(makingRoomFor windowId: String) {
        while surfacesByWindowId.count >= Self.maximumSurfaceCount,
              let oldest = surfaceOrder.first(where: { $0 != windowId }) {
            surfacesByWindowId.removeValue(forKey: oldest)
            surfaceOrder.removeAll { $0 == oldest }
        }
    }

    /// Current composited image for a window, or `nil` when no key frame has established a surface.
    public func image(for windowId: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return surfacesByWindowId[windowId]?.context.makeImage()
    }

    public func generation(for windowId: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return surfacesByWindowId[windowId]?.generation ?? 0
    }

    public func hasSurface(for windowId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return surfacesByWindowId[windowId] != nil
    }

    /// Releases a window's surface.
    ///
    /// Each surface is a full-resolution bitmap, so a closed window that kept one would hold megabytes for
    /// the rest of the process's lifetime.
    public func forget(windowId: String) {
        lock.lock()
        defer { lock.unlock() }
        surfacesByWindowId.removeValue(forKey: windowId)
        surfaceOrder.removeAll { $0 == windowId }
    }

    public func forgetAll() {
        lock.lock()
        defer { lock.unlock() }
        surfacesByWindowId.removeAll()
        surfaceOrder.removeAll()
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0,
              height > 0,
              width <= VeilFrameChannelCodec.maximumSurfaceDimension,
              height <= VeilFrameChannelCodec.maximumSurfaceDimension,
              // Repeated here rather than trusted from the codec, because this is the call that actually
              // allocates and `frame-pipeline-measure` reaches it through its own compositor.
              width * height <= VeilFrameChannelCodec.maximumSurfacePixelCount else {
            return nil
        }

        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }

    public static func decodePNG(_ data: Data) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
