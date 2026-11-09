import AppKit
import SwiftUI

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

    func makeNSView(context: Context) -> FrameLayerHostView {
        FrameLayerHostView()
    }

    func updateNSView(_ view: FrameLayerHostView, context: Context) {
        view.show(image, pointsPerPixel: pointsPerPixel, backdrop: backdrop)
    }
}

final class FrameLayerHostView: NSView {
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.anchorPoint = .zero
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-left origin, matching Windows and the frame bitmap.
    override var isFlipped: Bool { true }

    /// Input belongs to the capture view above.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ image: CGImage?, pointsPerPixel: CGFloat, backdrop: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = backdrop
        imageLayer.contents = image
        if let image {
            imageLayer.frame = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(image.width) * pointsPerPixel,
                height: CGFloat(image.height) * pointsPerPixel
            )
        }
        CATransaction.commit()
    }

    var displayedImage: CGImage? {
        imageLayer.contents.map { $0 as! CGImage }
    }
}
