import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VeilHostCore
import Virtualization

struct WindowsEmbeddedDisplayPreview: View {
    var image: NSImage?
    var surface: VMConsoleDisplaySurface
    var path: String
    var revisionID: String
    var resizeBus: DesktopResizeCommandBus?
    var displayResizeAction: ((Int, Int) -> Void)?
    var pointerTapAction: (Double, Double) -> Void
    var keyAction: (String) -> Void
    var commandKeyMapping: VMCommandKeyMapping = .default
    @State private var rfbDisplayModel = RFBEmbeddedDisplayModel()
    @State private var lastThumbnailAt = Date.distantPast
    @State private var followResizeTask: Task<Void, Never>?
    @State private var lastFollowTarget: RFBDesktopResizeTarget?
    @State private var containerSize: CGSize = .zero
    @Environment(\.liveDisplayThumbnailSink) private var liveDisplayThumbnailSink

    var body: some View {
        displayContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { followContainerSize(proxy.size) }
                        .onChange(of: proxy.size) { _, size in followContainerSize(size) }
                }
            }
            // Something else can change the guest resolution under an unchanged window: mirrored app
            // windows grow it to the Mac screen. Re-checking whenever the framebuffer size changes keeps
            // the desktop filling this window instead of sitting in it with bars.
            .onChange(of: framebufferPixelSize) { _, _ in
                followContainerSize(containerSize)
            }
    }

    /// The separate desktop window has a presenter that measures it; the main window has none, so
    /// without this Windows kept its resolution however the user sized Veil. A settled container size
    /// becomes the guest's desktop size, the way a Parallels VM window resizes Windows with it.
    private func followContainerSize(_ size: CGSize) {
        containerSize = size
        guard resizeBus == nil, surface.kind == .vncLoopback else {
            return
        }
        followResizeTask?.cancel()
        followResizeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled,
                  let target = RFBDesktopSizePolicy.target(
                      contentSizeInPoints: size,
                      backingScaleFactor: DisplayResolutionPreference.guestPixelsPerPoint(
                          screenScale: NSScreen.main?.backingScaleFactor
                      )
                  ),
                  RFBDesktopSizePolicy.isSignificantChange(from: lastFollowTarget, to: target)
                    || RFBDesktopSizePolicy.isSignificantChange(from: framebufferPixelSize, to: target) else {
                return
            }
            lastFollowTarget = target
            rfbDisplayModel.requestDesktopResize(width: target.widthInPixels, height: target.heightInPixels)
        }
    }

    private var displayContent: some View {
        ZStack {
            Color.black

            if let renderedImage {
                Image(nsImage: renderedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(displayRevisionID)
            } else {
                WindowsDisplayGrid()
                    .opacity(0.10)
                Image(systemName: surface.kind == .vncLoopback ? "display.and.arrow.down" : "display")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }

            if surface.kind == .vncLoopback {
                VStack {
                    // A display that is receiving frames is just Windows, like a Parallels VM window;
                    // the badge only explains a display that is still connecting or has failed.
                    if !rfbDisplayModel.isReceiving {
                        HStack {
                            Label(rfbDisplayModel.statusTitle(for: surface), systemImage: rfbDisplayModel.statusSymbolName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Spacer()
                        }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        if let resizeStatusText {
                            Text(resizeStatusText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(14)
                .allowsHitTesting(false)
            }

            ConsolePreviewInputCaptureView(
                framebufferSize: renderedFramebufferSize,
                commandKeyMapping: commandKeyMapping,
                rfbDisplayModel: surface.kind == .vncLoopback ? rfbDisplayModel : nil,
                pointerTapAction: { normalizedX, normalizedY in
                    if surface.kind == .vncLoopback {
                        rfbDisplayModel.sendPointerTap(
                            normalizedX: normalizedX,
                            normalizedY: normalizedY
                        )
                    } else {
                        pointerTapAction(normalizedX, normalizedY)
                    }
                },
                keyAction: { key in
                    if surface.kind == .vncLoopback {
                        rfbDisplayModel.sendKey(key)
                    } else {
                        keyAction(key)
                    }
                }
            )
        }
        .aspectRatio(displayAspectRatio, contentMode: .fit)
        .help("Latest Windows display")
        .accessibilityLabel(surface.kind == .vncLoopback ? "Embedded Windows display endpoint" : "Latest Windows display screenshot")
        .accessibilityValue(surface.endpoint ?? path)
        .onAppear {
            // Install the fallback before opening the socket. A local QEMU endpoint can answer the
            // first SetDesktopSize request immediately; registering after connect would lose the
            // one-shot agent fallback and leave the first enlargement in aspect-fit mode.
            rfbDisplayModel.setDisplayResizeFallback(displayResizeAction)
            if let resizeBus {
                let model = rfbDisplayModel
                resizeBus.setPerformer { [weak model] width, height in
                    model?.requestDesktopResize(width: width, height: height)
                }
            }
            rfbDisplayModel.connectIfNeeded(to: surface)
        }
        .onChange(of: surface.endpoint) { _, _ in
            rfbDisplayModel.connectIfNeeded(to: surface)
        }
        .onChange(of: rfbDisplayModel.frameSequence) { _, _ in
            // The sidebar shows what Windows is doing now, not the first boot frame; a frame every
            // couple of seconds is plenty for a 64-point thumbnail.
            let now = Date()
            guard let liveDisplayThumbnailSink,
                  let frame = rfbDisplayModel.image,
                  now.timeIntervalSince(lastThumbnailAt) >= 2 else {
                return
            }
            lastThumbnailAt = now
            liveDisplayThumbnailSink(frame)
        }
        .onDisappear {
            resizeBus?.setPerformer(nil)
            rfbDisplayModel.setDisplayResizeFallback(nil)
            rfbDisplayModel.stop()
        }
    }

    /// The guest framebuffer as last received, which is what the desktop actually shows.
    private var framebufferPixelSize: RFBDesktopResizeTarget? {
        guard let representation = rfbDisplayModel.image?.representations.first,
              representation.pixelsWide > 0,
              representation.pixelsHigh > 0 else {
            return nil
        }
        return RFBDesktopResizeTarget(
            widthInPixels: representation.pixelsWide,
            heightInPixels: representation.pixelsHigh
        )
    }

    private var renderedImage: NSImage? {
        rfbDisplayModel.image ?? fallbackScreenshot
    }

    /// The saved console screenshot stands in only while it is recent. For a live display it was
    /// taken when QEMU started, so hours later it showed a firmware boot screen over a Windows that
    /// was sitting at its desktop.
    static let liveFallbackScreenshotMaximumAge: TimeInterval = 120

    private var fallbackScreenshot: NSImage? {
        guard surface.isLiveCapable else {
            return image
        }
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) <= Self.liveFallbackScreenshotMaximumAge else {
            return nil
        }
        return image
    }

    private var renderedFramebufferSize: CGSize {
        guard let renderedImage else {
            return .zero
        }

        return CGSize(width: renderedImage.size.width, height: renderedImage.size.height)
    }

    private var displayAspectRatio: CGFloat {
        CGFloat(
            WindowsDisplayAspectRatioPolicy.resolve(
                pixelWidth: Double(renderedImage?.size.width ?? 0),
                pixelHeight: Double(renderedImage?.size.height ?? 0)
            )
        )
    }

    private var displayRevisionID: String {
        if let sequence = rfbDisplayModel.frameSequence {
            return "\(surface.endpoint ?? "rfb")#\(sequence)"
        }

        return revisionID
    }

    private var resizeStatusText: String? {
        guard rfbDisplayModel.status == .receiving else {
            return nil
        }

        // Resizing that works, or plain aspect-fit, is the normal case and needs no badge on top of
        // Windows; only a refused or in-progress resize is worth a word.
        switch rfbDisplayModel.resizePresentation {
        case .available, .scaled, .forwardedToGuest:
            return nil
        case .rejected:
            return "Guest refused resize: aspect-fit"
        case .recovering:
            return "Probing guest resize support…"
        case .unavailable:
            return nil
        }
    }
}

enum WindowsDisplayAspectRatioPolicy {
    static func resolve(pixelWidth: Double, pixelHeight: Double) -> Double {
        guard pixelWidth > 0, pixelHeight > 0 else {
            return 16.0 / 9.0
        }

        return pixelWidth / pixelHeight
    }
}

struct ConsolePreviewInputCaptureView: NSViewRepresentable {
    var framebufferSize: CGSize
    var commandKeyMapping: VMCommandKeyMapping
    /// When set, the view sends every pointer change over RFB (moves, drags, both buttons, scrolling)
    /// instead of reducing a press to a tap.
    var rfbDisplayModel: RFBEmbeddedDisplayModel? = nil
    var pointerTapAction: (Double, Double) -> Void
    var keyAction: (String) -> Void

    func makeNSView(context: Context) -> ConsolePreviewInputCaptureNSView {
        let view = ConsolePreviewInputCaptureNSView()
        view.framebufferSize = framebufferSize
        view.keyboardMapper.commandKeyMapping = commandKeyMapping
        view.rfbDisplayModel = rfbDisplayModel
        view.pointerTapAction = pointerTapAction
        view.keyAction = keyAction
        return view
    }

    func updateNSView(_ nsView: ConsolePreviewInputCaptureNSView, context: Context) {
        nsView.framebufferSize = framebufferSize
        nsView.keyboardMapper.commandKeyMapping = commandKeyMapping
        nsView.rfbDisplayModel = rfbDisplayModel
        nsView.pointerTapAction = pointerTapAction
        nsView.keyAction = keyAction
    }
}

final class ConsolePreviewInputCaptureNSView: NSView {
    var framebufferSize: CGSize = .zero
    var pointerTapAction: ((Double, Double) -> Void)?
    var keyAction: ((String) -> Void)?
    var keyboardMapper = QEMUConsoleKeyboardInputMapper()
    weak var rfbDisplayModel: RFBEmbeddedDisplayModel?
    /// RFB buttons currently held, sent with every move so a drag keeps its button down.
    private var heldButtons: UInt8 = 0
    private var scrollRemainder = (x: 0.0, y: 0.0)
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if !sendPointerButton(event, isDown: true) {
            sendPointerTap(event)
        }
    }

    override func mouseUp(with event: NSEvent) { sendPointerButton(event, isDown: false) }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendPointerButton(event, isDown: true)
    }
    override func rightMouseUp(with event: NSEvent) { sendPointerButton(event, isDown: false) }
    override func otherMouseDown(with event: NSEvent) { sendPointerButton(event, isDown: true) }
    override func otherMouseUp(with event: NSEvent) { sendPointerButton(event, isDown: false) }
    override func mouseMoved(with event: NSEvent) { sendPointerMove(event) }
    override func mouseDragged(with event: NSEvent) { sendPointerMove(event) }
    override func rightMouseDragged(with event: NSEvent) { sendPointerMove(event) }
    override func otherMouseDragged(with event: NSEvent) { sendPointerMove(event) }

    override func scrollWheel(with event: NSEvent) {
        guard let rfbDisplayModel, let pixel = framebufferPixel(event) else {
            super.scrollWheel(with: event)
            return
        }

        // Same feel as mirrored app windows: about 60 points of trackpad travel per wheel notch, and one
        // notch per line of a stepped mouse wheel.
        let notchesPerDelta = event.hasPreciseScrollingDeltas ? 1.0 / 60.0 : 1.0
        let amount = WindowsScrollAmount.accumulate(
            remainder: scrollRemainder,
            scrollingDeltaX: Double(event.scrollingDeltaX),
            scrollingDeltaY: Double(event.scrollingDeltaY),
            unitsPerDelta: notchesPerDelta
        )
        scrollRemainder = amount.remainder
        let notches = RFBPointerButtons.wheelNotches(deltaX: amount.deltaX, deltaY: amount.deltaY)
        rfbDisplayModel.sendWheel(x: pixel.x, y: pixel.y, buttonMask: heldButtons, notches: notches)
    }

    /// Returns false when this view has no RFB session, so the caller falls back to a tap.
    @discardableResult
    private func sendPointerButton(_ event: NSEvent, isDown: Bool) -> Bool {
        guard let rfbDisplayModel, let pixel = framebufferPixel(event) else {
            return false
        }
        guard let bit = RFBPointerButtons.bit(forButtonNumber: event.buttonNumber) else {
            return true
        }

        heldButtons = isDown ? heldButtons | bit : heldButtons & ~bit
        rfbDisplayModel.sendPointer(x: pixel.x, y: pixel.y, buttonMask: heldButtons)
        return true
    }

    private func sendPointerMove(_ event: NSEvent) {
        guard let rfbDisplayModel, let pixel = framebufferPixel(event) else {
            return
        }
        rfbDisplayModel.sendPointer(x: pixel.x, y: pixel.y, buttonMask: heldButtons)
    }

    private func framebufferPixel(_ event: NSEvent) -> (x: Int, y: Int)? {
        guard let size = rfbDisplayModel?.framebufferPixelSize else {
            return nil
        }
        let viewport = RFBViewportMapper.viewport(
            framebufferWidth: Double(size.width),
            framebufferHeight: Double(size.height),
            containerWidth: bounds.width,
            containerHeight: bounds.height
        )
        return RFBPointerButtons.framebufferPixel(
            pointInContainer: convert(event.locationInWindow, from: nil),
            viewport: viewport,
            framebufferWidth: size.width,
            framebufferHeight: size.height
        )
    }

    override func keyDown(with event: NSEvent) {
        if !sendKey(event) {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              sendKey(event) else {
            return super.performKeyEquivalent(with: event)
        }

        return true
    }

    /// Maps clicks through the aspect-fit viewport so letterbox bars and window
    /// chrome never inject coordinates into the guest. While a resize request is in
    /// flight the framebuffer size stays at the last applied geometry.
    private func sendPointerTap(_ event: NSEvent) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let viewport = RFBViewportMapper.viewport(
            framebufferWidth: framebufferSize.width,
            framebufferHeight: framebufferSize.height,
            containerWidth: bounds.width,
            containerHeight: bounds.height
        )

        guard let normalized = RFBViewportMapper.normalizedGuestPoint(
            pointInContainer: point,
            viewport: viewport
        ) else {
            return
        }

        pointerTapAction?(Double(normalized.x), Double(1 - normalized.y))
    }

    private func sendKey(_ event: NSEvent) -> Bool {
        guard let key = keyboardMapper.key(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: qemuKeyboardModifiers(from: event)
        ) else {
            return false
        }

        keyAction?(key)
        return true
    }

    private func qemuKeyboardModifiers(from event: NSEvent) -> QEMUConsoleKeyboardModifier {
        let flags = event.modifierFlags
        var modifiers: QEMUConsoleKeyboardModifier = []

        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }

        return modifiers
    }
}

extension EnvironmentValues {
    /// Receives occasional live frames for the Control Center thumbnail. Unset in windows that have
    /// no sidebar, such as the separate desktop window.
    @Entry var liveDisplayThumbnailSink: ((NSImage) -> Void)?
}
