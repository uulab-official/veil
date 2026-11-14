import AppKit
import SwiftUI
import VeilHostCore

/// Shows a mirrored window's surface the way macOS apps show video and remote screens: the image goes straight
/// into a layer's contents, swapped without implicit animation, pinned unscaled to the top-left.
///
/// Building an `NSImage` and laying out a SwiftUI `Image` for every frame put view diffing and image bookkeeping
/// on the main thread at frame rate. Setting layer contents is the cheapest update AppKit has; the compositor
/// does the rest.
struct FrameLayerView: NSViewRepresentable {
    var image: CGImage?
    /// Points per source pixel; see `WindowFrameViewport.pointsPerPixel(forWindowsScale:)`.
    var pointsPerPixel: CGFloat
    /// Fills area the guest has not drawn yet. Clear for popups.
    var backdrop: CGColor
    /// Whether the frame is a whole app window, whose outer ring is the Windows border. A frame the agent
    /// copied from the screen has whatever was behind the window in that translucent border, so the ring is
    /// replaced the way a framebuffer crop's is; see `CoherenceBorderlessCrop`. Off for popups, which are
    /// drawn over their owner as they are.
    var dropsWindowBorder = false

    func makeNSView(context: Context) -> FrameLayerHostView {
        FrameLayerHostView()
    }

    func updateNSView(_ view: FrameLayerHostView, context: Context) {
        view.show(image, pointsPerPixel: pointsPerPixel, backdrop: backdrop, dropsWindowBorder: dropsWindowBorder)
    }
}

final class FrameLayerHostView: NSView {
    private let imageLayer = CALayer()
    /// The frame's inner region stretched over the whole frame beneath `imageLayer`; only its outer ring
    /// shows, where the Windows border was dropped.
    private let edgeLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.anchorPoint = .zero
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        imageLayer.actions = [
            "contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()
        ]
        edgeLayer.anchorPoint = .zero
        edgeLayer.magnificationFilter = .linear
        edgeLayer.minificationFilter = .linear
        edgeLayer.actions = imageLayer.actions
        edgeLayer.isHidden = true
        layer?.addSublayer(edgeLayer)
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-left origin, matching Windows and the frame bitmap.
    override var isFlipped: Bool { true }

    /// Input belongs to the capture view above.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ image: CGImage?, pointsPerPixel: CGFloat, backdrop: CGColor, dropsWindowBorder: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = backdrop
        imageLayer.contents = image
        let whole = image.map { CGRect(x: 0, y: 0, width: $0.width, height: $0.height) }
        let borderless = whole.flatMap { whole in
            dropsWindowBorder
                ? CoherenceBorderlessCrop(
                    crop: whole,
                    borderPixels: CoherenceBorderlessCrop.borderPixels(pointsPerPixel: pointsPerPixel)
                )
                : nil
        }
        if let whole {
            let fullFrame = CGRect(x: 0, y: 0, width: whole.width * pointsPerPixel, height: whole.height * pointsPerPixel)
            if let borderless {
                let unit = CGRect(
                    x: borderless.inner.minX / whole.width,
                    y: borderless.inner.minY / whole.height,
                    width: borderless.inner.width / whole.width,
                    height: borderless.inner.height / whole.height
                )
                imageLayer.contentsRect = unit
                imageLayer.frame = CGRect(
                    x: borderless.innerOffset.x * pointsPerPixel,
                    y: borderless.innerOffset.y * pointsPerPixel,
                    width: borderless.inner.width * pointsPerPixel,
                    height: borderless.inner.height * pointsPerPixel
                )
                edgeLayer.contents = image
                edgeLayer.contentsRect = unit
                edgeLayer.frame = fullFrame
            } else {
                imageLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                imageLayer.frame = fullFrame
            }
        }
        edgeLayer.isHidden = borderless == nil
        if borderless == nil {
            edgeLayer.contents = nil
        }
        CATransaction.commit()
    }

    var displayedImage: CGImage? {
        imageLayer.contents.map { $0 as! CGImage }
    }

    /// Where the frame's pixels are drawn one for one, for tests.
    var imageFrame: CGRect { imageLayer.frame }

    /// The part of the frame drawn there, in unit coordinates.
    var imageContentsRect: CGRect { imageLayer.contentsRect }

    /// The layer filling the dropped border, or nil while the whole frame is drawn.
    var borderFill: CALayer? { edgeLayer.isHidden ? nil : edgeLayer }
}
