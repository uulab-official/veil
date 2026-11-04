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
    @State private var rfbDisplayModel = RFBEmbeddedDisplayModel()

    var body: some View {
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
        .onDisappear {
            resizeBus?.setPerformer(nil)
            rfbDisplayModel.setDisplayResizeFallback(nil)
            rfbDisplayModel.stop()
        }
    }

    private var renderedImage: NSImage? {
        rfbDisplayModel.image ?? image
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

        switch rfbDisplayModel.resizePresentation {
        case .available:
            return "Dynamic resolution available"
        case .scaled:
            return "Aspect-fit: guest resize unavailable"
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
    var pointerTapAction: (Double, Double) -> Void
    var keyAction: (String) -> Void

    func makeNSView(context: Context) -> ConsolePreviewInputCaptureNSView {
        let view = ConsolePreviewInputCaptureNSView()
        view.framebufferSize = framebufferSize
        view.pointerTapAction = pointerTapAction
        view.keyAction = keyAction
        return view
    }

    func updateNSView(_ nsView: ConsolePreviewInputCaptureNSView, context: Context) {
        nsView.framebufferSize = framebufferSize
        nsView.pointerTapAction = pointerTapAction
        nsView.keyAction = keyAction
    }
}

final class ConsolePreviewInputCaptureNSView: NSView {
    var framebufferSize: CGSize = .zero
    var pointerTapAction: ((Double, Double) -> Void)?
    var keyAction: ((String) -> Void)?
    private let keyboardMapper = QEMUConsoleKeyboardInputMapper()

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendPointerTap(event)
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
