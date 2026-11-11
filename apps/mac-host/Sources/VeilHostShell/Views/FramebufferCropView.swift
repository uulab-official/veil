import AppKit
import SwiftUI
import VeilHostCore

/// Shows a mirrored window by cropping the shared guest framebuffer, when `window.layout` says the guest
/// display shows all of it. Otherwise it is empty and the captured frame underneath shows through.
///
/// The view follows frames and layouts itself, outside SwiftUI: each framebuffer frame only swaps one
/// layer's contents, and the crop is a `contentsRect`, so the GPU does the cropping.
struct FramebufferCropView: NSViewRepresentable {
    var windowId: String
    /// Points per guest pixel; see `WindowFrameViewport.pointsPerPixel(forWindowsScale:)`.
    var pointsPerPixel: CGFloat
    var onAvailabilityChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> FramebufferCropHostView {
        FramebufferCropHostView(windowId: windowId)
    }

    func updateNSView(_ view: FramebufferCropHostView, context: Context) {
        view.windowId = windowId
        view.pointsPerPixel = pointsPerPixel
        view.onAvailabilityChange = onAvailabilityChange
        view.refresh()
    }

    static func dismantleNSView(_ view: FramebufferCropHostView, coordinator: ()) {
        view.detach()
    }
}

final class FramebufferCropHostView: NSView {
    var windowId: String
    var pointsPerPixel: CGFloat = 1
    var onAvailabilityChange: ((Bool) -> Void)?
    private let imageLayer = CALayer()
    /// The window's inner region stretched to the full size under `imageLayer`; only its outer ring shows,
    /// where the Windows border was dropped. See `CoherenceBorderlessCrop`.
    private let edgeLayer = CALayer()
    private var frameToken: UUID?
    private var layoutToken: UUID?
    private var latestFrame: CGImage?
    private(set) var isShowingCrop = false

    init(windowId: String) {
        self.windowId = windowId
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.anchorPoint = .zero
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        imageLayer.actions = [
            "contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()
        ]
        imageLayer.isHidden = true
        edgeLayer.anchorPoint = .zero
        edgeLayer.magnificationFilter = .linear
        edgeLayer.minificationFilter = .linear
        edgeLayer.actions = imageLayer.actions
        edgeLayer.isHidden = true
        layer?.addSublayer(edgeLayer)
        layer?.addSublayer(imageLayer)
        MainActor.assumeIsolated {
            frameToken = GuestFramebufferSource.shared.addSink { [weak self] image in
                self?.latestFrame = image
                self?.refresh()
            }
            layoutToken = GuestWindowLayoutStore.shared.observe { [weak self] in
                self?.refresh()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-left origin, matching Windows.
    override var isFlipped: Bool { true }

    /// Input belongs to the capture view above.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func detach() {
        if isShowingCrop {
            isShowingCrop = false
            onAvailabilityChange?(false)
        }
        MainActor.assumeIsolated {
            if let frameToken {
                GuestFramebufferSource.shared.removeSink(frameToken)
            }
            if let layoutToken {
                GuestWindowLayoutStore.shared.removeObserver(layoutToken)
            }
        }
        frameToken = nil
        layoutToken = nil
    }

    func refresh() {
        let crop = latestFrame.flatMap { frame in
            MainActor.assumeIsolated {
                GuestWindowLayoutStore.shared.framebufferCrop(
                    windowId: windowId,
                    framebufferWidth: frame.width,
                    framebufferHeight: frame.height
                )
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let crop, let latestFrame {
            let width = CGFloat(latestFrame.width)
            let height = CGFloat(latestFrame.height)
            func normalized(_ rect: CGRect) -> CGRect {
                CGRect(x: rect.minX / width, y: rect.minY / height, width: rect.width / width, height: rect.height / height)
            }
            let fullFrame = CGRect(x: 0, y: 0, width: crop.width * pointsPerPixel, height: crop.height * pointsPerPixel)
            imageLayer.contents = latestFrame
            if let borderless = CoherenceBorderlessCrop(
                crop: crop,
                borderPixels: CoherenceBorderlessCrop.borderPixels(pointsPerPixel: pointsPerPixel)
            ) {
                imageLayer.contentsRect = normalized(borderless.inner)
                imageLayer.frame = CGRect(
                    x: borderless.innerOffset.x * pointsPerPixel,
                    y: borderless.innerOffset.y * pointsPerPixel,
                    width: borderless.inner.width * pointsPerPixel,
                    height: borderless.inner.height * pointsPerPixel
                )
                edgeLayer.contents = latestFrame
                edgeLayer.contentsRect = normalized(borderless.inner)
                edgeLayer.frame = fullFrame
                edgeLayer.isHidden = false
            } else {
                imageLayer.contentsRect = normalized(crop)
                imageLayer.frame = fullFrame
                edgeLayer.isHidden = true
                edgeLayer.contents = nil
            }
            imageLayer.isHidden = false
        } else {
            imageLayer.isHidden = true
            imageLayer.contents = nil
            edgeLayer.isHidden = true
            edgeLayer.contents = nil
        }
        CATransaction.commit()

        let showing = crop != nil
        if showing != isShowingCrop {
            isShowingCrop = showing
            onAvailabilityChange?(showing)
        }
    }
}
