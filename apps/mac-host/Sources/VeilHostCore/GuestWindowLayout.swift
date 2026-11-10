import CoreGraphics
import Foundation

/// A rectangle in guest display pixels, top-left origin.
public struct GuestPixelRect: Codable, Equatable, Sendable {
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

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// `window.layout`: where every tracked window sits on the guest display. See docs/protocol.md.
public struct WindowLayoutEvent: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public var windowId: String
        public var ownerWindowId: String?
        public var frame: GuestPixelRect
        public var zOrder: Int
        public var isForeground: Bool
        public var isShown: Bool
        public var fullyVisible: Bool

        public init(
            windowId: String,
            ownerWindowId: String? = nil,
            frame: GuestPixelRect,
            zOrder: Int,
            isForeground: Bool,
            isShown: Bool,
            fullyVisible: Bool
        ) {
            self.windowId = windowId
            self.ownerWindowId = ownerWindowId
            self.frame = frame
            self.zOrder = zOrder
            self.isForeground = isForeground
            self.isShown = isShown
            self.fullyVisible = fullyVisible
        }
    }

    public var type: MessageType
    public var sequence: Int
    public var display: GuestPixelRect
    public var windows: [Window]

    public init(sequence: Int, display: GuestPixelRect, windows: [Window]) {
        self.type = .windowLayout
        self.sequence = sequence
        self.display = display
        self.windows = windows
    }
}

/// The latest `window.layout`, and where each window's pixels sit in the guest framebuffer.
///
/// The host receives the whole guest display over its loopback VNC connection. A window the layout
/// marks `fullyVisible` can be shown by cropping that framebuffer instead of waiting for frames the
/// agent captures and encodes; see docs/superpowers/specs/2026-11-10-coherence-framebuffer-design.md.
@MainActor
public final class GuestWindowLayoutStore {
    public static let shared = GuestWindowLayoutStore()

    public private(set) var latest: WindowLayoutEvent?
    private var observers: [UUID: @MainActor () -> Void] = [:]

    public init() {}

    /// Applies a layout unless it is older than the one already applied.
    @discardableResult
    public func apply(_ event: WindowLayoutEvent) -> Bool {
        // Sequence 1 is a restarted agent, whose count started over.
        if let latest, event.sequence <= latest.sequence, event.sequence != 1 {
            return false
        }
        latest = event
        observers.values.forEach { $0() }
        return true
    }

    public func reset() {
        latest = nil
        observers.values.forEach { $0() }
    }

    public func observe(_ observer: @escaping @MainActor () -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    public func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    /// Where a window's pixels are in a framebuffer of the given size, or nil when the window must keep
    /// its captured frames: not fully visible, or a framebuffer that does not match the layout's display.
    public func framebufferCrop(windowId: String, framebufferWidth: Int, framebufferHeight: Int) -> CGRect? {
        guard let latest else {
            return nil
        }
        return Self.framebufferCrop(
            windowId: windowId,
            layout: latest,
            framebufferWidth: framebufferWidth,
            framebufferHeight: framebufferHeight
        )
    }

    public nonisolated static func framebufferCrop(
        windowId: String,
        layout: WindowLayoutEvent,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> CGRect? {
        // VNC carries the primary display only; a layout whose display is a different size describes a
        // display change the framebuffer has not caught up with.
        guard layout.display.width == framebufferWidth,
              layout.display.height == framebufferHeight,
              let window = layout.windows.first(where: { $0.windowId == windowId }),
              window.isShown,
              window.fullyVisible,
              window.frame.width > 0,
              window.frame.height > 0 else {
            return nil
        }

        let crop = CGRect(
            x: window.frame.x - layout.display.x,
            y: window.frame.y - layout.display.y,
            width: window.frame.width,
            height: window.frame.height
        )
        let bounds = CGRect(x: 0, y: 0, width: framebufferWidth, height: framebufferHeight)
        return bounds.contains(crop) ? crop : nil
    }
}

/// Whether a window that the layout does not mark fully visible is so because of where it sits on the
/// guest display, which resizing can fix, rather than because another app covers it.
public enum CoherenceDisplayFit {
    public static func needsFit(window: GuestPixelRect, display: GuestPixelRect) -> Bool {
        window.x < display.x
            || window.y < display.y
            || window.x + window.width > display.x + display.width
            || window.y + window.height > display.y + display.height - MirroredWindowDisplayFit.taskbarAllowance
    }
}
