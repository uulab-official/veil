import AppKit
import SwiftUI
import VeilHostCore

/// Shows a mirrored window by cropping the shared guest framebuffer, when `window.layout` says the guest
/// display shows it. A window other windows partly cover is cropped where it shows, and the captured frame
/// underneath fills the covered parts; that frame also shows through when nothing can be cropped.
///
/// Covered windows used to be shown from captured frames alone. With three overlapping windows the agent
/// then printed the two behind about seven times a second while nothing changed, each print making the app
/// draw itself again, in a guest that renders on the CPU.
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
    /// One layer per visible part of a window other windows partly cover, each cropping its own part of
    /// the framebuffer. Laid out like `imageLayer`, so they need no mask.
    private var pieceLayers: [CALayer] = []
    private let imageLayer = CALayer()
    /// The window's inner region stretched to the full size under `imageLayer`; only its outer ring shows,
    /// where the Windows border was dropped. See `CoherenceBorderlessCrop`.
    private let edgeLayer = CALayer()
    private var frameToken: UUID?
    private var layoutToken: UUID?
    private var latestFrame: CGImage?
    private(set) var isShowingCrop = false
    /// What was last reported through `onAvailabilityChange`: the window's captured frames may come slowly,
    /// because the framebuffer shows it or because other windows hide all of it.
    private var reportedSlowCapture = false

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
        isShowingCrop = false
        if reportedSlowCapture {
            reportedSlowCapture = false
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
        // While the window settles after a move or resize, keep the last cropped picture instead of switching
        // to the captured frame, which updates about once a second and made every move stutter. The last
        // picture is the window's own pixels; the new position's pixels may still be the desktop.
        if isShowingCrop, MainActor.assumeIsolated({ GuestWindowLayoutStore.shared.isSettling(windowId: windowId) }) {
            return
        }
        let region = latestFrame.flatMap { frame in
            MainActor.assumeIsolated {
                GuestWindowLayoutStore.shared.framebufferCropRegion(
                    windowId: windowId,
                    framebufferWidth: frame.width,
                    framebufferHeight: frame.height
                )
            }
        }
        let crop = region?.crop

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let crop, let latestFrame {
            let width = CGFloat(latestFrame.width)
            let height = CGFloat(latestFrame.height)
            func normalized(_ rect: CGRect) -> CGRect {
                CGRect(x: rect.minX / width, y: rect.minY / height, width: rect.width / width, height: rect.height / height)
            }
            let fullFrame = CGRect(x: 0, y: 0, width: crop.width * pointsPerPixel, height: crop.height * pointsPerPixel)
            let borderless = CoherenceBorderlessCrop(
                crop: crop,
                borderPixels: CoherenceBorderlessCrop.borderPixels(pointsPerPixel: pointsPerPixel)
            )
            if let visible = region?.visible {
                // Partly covered: only the parts the framebuffer shows, and none of the Windows border
                // around the window, which shows what is behind it. The captured frame fills the rest.
                let inner = borderless.map {
                    CGRect(x: $0.innerOffset.x, y: $0.innerOffset.y, width: $0.inner.width, height: $0.inner.height)
                } ?? CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
                let pieces = FramebufferCropPieces.pieces(visible: visible, within: inner)
                showPieces(pieces, crop: crop, frame: latestFrame, normalized: normalized)
                imageLayer.isHidden = true
                imageLayer.contents = nil
                edgeLayer.isHidden = true
                edgeLayer.contents = nil
            } else {
                showPieces([], crop: crop, frame: latestFrame, normalized: normalized)
                imageLayer.contents = latestFrame
                if let borderless {
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
            }
        } else {
            for piece in pieceLayers {
                piece.isHidden = true
                piece.contents = nil
            }
            imageLayer.isHidden = true
            imageLayer.contents = nil
            edgeLayer.isHidden = true
            edgeLayer.contents = nil
        }
        CATransaction.commit()

        let showing = crop != nil
        isShowingCrop = showing
        let slowCapture = showing
            || MainActor.assumeIsolated { GuestWindowLayoutStore.shared.isWhollyCovered(windowId: windowId) }
        if slowCapture != reportedSlowCapture {
            reportedSlowCapture = slowCapture
            onAvailabilityChange?(slowCapture)
        }
    }

    /// Lays out one layer per piece, reusing layers and hiding the ones left over.
    private func showPieces(
        _ pieces: [CGRect],
        crop: CGRect,
        frame: CGImage,
        normalized: (CGRect) -> CGRect
    ) {
        while pieceLayers.count < pieces.count {
            let piece = CALayer()
            piece.anchorPoint = .zero
            piece.magnificationFilter = .linear
            piece.minificationFilter = .linear
            piece.actions = imageLayer.actions
            layer?.addSublayer(piece)
            pieceLayers.append(piece)
        }
        for (index, piece) in pieceLayers.enumerated() {
            guard index < pieces.count else {
                piece.isHidden = true
                piece.contents = nil
                continue
            }
            let rect = pieces[index]
            piece.contents = frame
            piece.contentsRect = normalized(rect.offsetBy(dx: crop.minX, dy: crop.minY))
            piece.frame = CGRect(
                x: rect.minX * pointsPerPixel,
                y: rect.minY * pointsPerPixel,
                width: rect.width * pointsPerPixel,
                height: rect.height * pointsPerPixel
            )
            piece.isHidden = false
        }
    }

    /// Where each piece is laid out, in points, for tests.
    var pieceFrames: [CGRect] {
        pieceLayers.filter { !$0.isHidden }.map(\.frame)
    }

    var pieceContentsRects: [CGRect] {
        pieceLayers.filter { !$0.isHidden }.map(\.contentsRect)
    }
}

/// The parts of a partly covered window to crop from the framebuffer.
enum FramebufferCropPieces {
    /// The visible parts, in pixels from the window's top-left corner, kept inside `inner`: the window
    /// without its one-pixel Windows border.
    static func pieces(visible: [CGRect], within inner: CGRect) -> [CGRect] {
        visible.compactMap { rect in
            let piece = rect.intersection(inner)
            return piece.isNull || piece.isEmpty ? nil : piece
        }
    }
}
