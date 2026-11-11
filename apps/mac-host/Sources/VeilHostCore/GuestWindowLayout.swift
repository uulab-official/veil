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
    /// When each window's frame last changed. The framebuffer lags a move or resize: until the app redraws
    /// and the guest presents, the area a window just took over still shows what was behind it, and
    /// cropping the new frame put the Windows desktop into the Mac window. See `settleSeconds`.
    private var frameChangedAt: [String: Date] = [:]
    private let now: () -> Date

    /// How long a moved or resized window keeps its captured frame before cropping resumes; a few guest
    /// frames at the 25-30 a second the software renderer presents.
    public static let settleSeconds: TimeInterval = 0.3

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Applies a layout unless it is older than the one already applied.
    @discardableResult
    public func apply(_ event: WindowLayoutEvent) -> Bool {
        // Sequence 1 is a restarted agent, whose count started over.
        if let latest, event.sequence <= latest.sequence, event.sequence != 1 {
            return false
        }
        let changedAt = now()
        let previousFrames = Dictionary(
            (latest?.windows ?? []).map { ($0.windowId, $0.frame) },
            uniquingKeysWith: { first, _ in first }
        )
        for window in event.windows where previousFrames[window.windowId].map({ $0 != window.frame }) ?? false {
            frameChangedAt[window.windowId] = changedAt
        }
        latest = event
        observers.values.forEach { $0() }
        if event.windows.contains(where: { isSettling(windowId: $0.windowId) }) {
            // Nothing else may arrive to end the settle period, so announce its end.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.settleSeconds + 0.02))
                self?.observers.values.forEach { $0() }
            }
        }
        return true
    }

    /// True while a window's frame changed less than `settleSeconds` ago.
    public func isSettling(windowId: String) -> Bool {
        guard let changedAt = frameChangedAt[windowId] else {
            return false
        }
        return now().timeIntervalSince(changedAt) < Self.settleSeconds
    }

    public func reset() {
        latest = nil
        frameChangedAt = [:]
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
        guard let latest, !isSettling(windowId: windowId) else {
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

/// Where a mirrored window belongs on the guest display, from where its Mac window's content is.
///
/// The guest display stands for the Mac screen the window is on: its top-left is the screen's top-left,
/// scaled by display pixels per screen point. When the two are the same size (`displayMatching`), the
/// guest layout is the Mac layout, so overlapping windows cover each other the same way in both.
public enum CoherencePlacement {
    /// The guest point for a window's visible frame. `contentFrame` and `screenFrame` are AppKit screen
    /// coordinates (bottom-left origin, points).
    public static func guestOrigin(contentFrame: CGRect, screenFrame: CGRect, display: GuestPixelRect) -> (x: Int, y: Int)? {
        guard screenFrame.width > 0, screenFrame.height > 0, display.width > 0, display.height > 0 else {
            return nil
        }
        let scaleX = Double(display.width) / screenFrame.width
        let scaleY = Double(display.height) / screenFrame.height
        let x = display.x + Int(((contentFrame.minX - screenFrame.minX) * scaleX).rounded())
        let y = display.y + Int(((screenFrame.maxY - contentFrame.maxY) * scaleY).rounded())
        return (x, y)
    }

    /// The guest display size that makes the guest layout the Mac layout: the screen in points times the
    /// guest pixels per point. Mirrored windows are their logical size in points, and Windows draws them
    /// at that many pixels per logical unit when its scale is `pixelsPerPoint` × 100%.
    public static func displayMatching(screenFrame: CGRect, pixelsPerPoint: Int = 1) -> GuestDisplaySize? {
        let width = Int((screenFrame.width * CGFloat(pixelsPerPoint)).rounded())
        let height = Int((screenFrame.height * CGFloat(pixelsPerPoint)).rounded())
        guard pixelsPerPoint >= 1, DisplayResizeRequest.isPlausible(width: width, height: height) else {
            return nil
        }
        return GuestDisplaySize(width: width, height: height)
    }
}

/// How many guest pixels per Mac point the apps view runs Windows at, and the Windows scale that goes with
/// it. Two on a Retina Mac, so text is drawn at the display's own pixels instead of being doubled by macOS.
/// See docs/checklists/2026-11-11-retina-guest-scale.md.
public struct CoherenceDisplayScale: Equatable, Sendable {
    public var pixelsPerPoint: Int
    public var display: GuestDisplaySize

    /// The Windows display scale to ask for, or nil for the scale the Windows user chose.
    public var scalePercent: Int? {
        pixelsPerPoint > 1 ? pixelsPerPoint * 100 : nil
    }

    public init(pixelsPerPoint: Int, display: GuestDisplaySize) {
        self.pixelsPerPoint = pixelsPerPoint
        self.display = display
    }

    /// The apps view's guest display for a Mac screen. Falls back to one pixel per point when Retina is off,
    /// the agent cannot set the scale, Windows refused it before, or the doubled screen is larger than a
    /// guest display may be (a 5K display at 2x).
    public static func target(
        screenFrame: CGRect,
        backingScale: Double?,
        retinaEnabled: Bool,
        agentCanScale: Bool,
        scaleRefused: Bool
    ) -> CoherenceDisplayScale? {
        let retinaPixels = retinaPixelsPerPoint(backingScale: backingScale)
        if retinaEnabled, agentCanScale, !scaleRefused, retinaPixels > 1,
           let display = CoherencePlacement.displayMatching(screenFrame: screenFrame, pixelsPerPoint: retinaPixels) {
            return CoherenceDisplayScale(pixelsPerPoint: retinaPixels, display: display)
        }
        return CoherencePlacement.displayMatching(screenFrame: screenFrame)
            .map { CoherenceDisplayScale(pixelsPerPoint: 1, display: $0) }
    }

    /// Whole pixels per point for a backing scale: 2 on every Retina Mac, 1 otherwise.
    public static func retinaPixelsPerPoint(backingScale: Double?) -> Int {
        guard let backingScale, backingScale.isFinite else {
            return 1
        }
        return min(max(Int(backingScale.rounded()), 1), 2)
    }

    /// Windows offers a scale step only while the display stays at least about 1024×768 logical pixels, so
    /// the display grows before the scale rises and the scale drops before the display shrinks.
    public static func resizesDisplayFirst(fromScalePercent current: Int?, toScalePercent target: Int?) -> Bool {
        (target ?? 100) >= (current ?? 100)
    }
}
