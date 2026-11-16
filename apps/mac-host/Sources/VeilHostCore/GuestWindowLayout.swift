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
        /// For a window that is not fully visible: the parts of it the guest display does show, in display
        /// pixels. Absent for a fully visible window and from agents that do not report it.
        public var visibleRegion: [GuestPixelRect]?
        /// True when the window's program runs with more rights than the agent, as an installer does once
        /// its prompt is approved. Input the agent injects does not reach it. Absent otherwise.
        public var elevated: Bool?

        public init(
            windowId: String,
            ownerWindowId: String? = nil,
            frame: GuestPixelRect,
            zOrder: Int,
            isForeground: Bool,
            isShown: Bool,
            fullyVisible: Bool,
            visibleRegion: [GuestPixelRect]? = nil,
            elevated: Bool? = nil
        ) {
            self.windowId = windowId
            self.ownerWindowId = ownerWindowId
            self.frame = frame
            self.zOrder = zOrder
            self.isForeground = isForeground
            self.isShown = isShown
            self.fullyVisible = fullyVisible
            self.visibleRegion = visibleRegion
            self.elevated = elevated
        }
    }

    public var type: MessageType
    public var sequence: Int
    public var display: GuestPixelRect
    public var windows: [Window]
    /// True while a User Account Control prompt, the lock screen, or the Ctrl+Alt+Del screen has the guest
    /// display. Absent from agents that do not report it.
    public var secureDesktop: Bool?

    public init(sequence: Int, display: GuestPixelRect, windows: [Window], secureDesktop: Bool? = nil) {
        self.type = .windowLayout
        self.sequence = sequence
        self.display = display
        self.windows = windows
        self.secureDesktop = secureDesktop
    }

    /// Whether the guest display shows Windows' secure desktop instead of the windows listed here.
    public var showsSecureDesktop: Bool {
        secureDesktop == true
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
    /// Moves Veil asked for whose new frame the layout has not shown yet, and until when to wait for it.
    private var awaitedMoves: [String: Date] = [:]
    private let now: () -> Date

    /// How long a move Veil asked for may take to appear in the layout before cropping resumes anyway.
    public static let awaitedMoveSeconds: TimeInterval = 1

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
        // A window seen for the first time settles too: Windows fades and grows a window in as it opens,
        // and until that ends the framebuffer shows the desktop and the windows behind in its place.
        for window in event.windows where previousFrames[window.windowId].map({ $0 != window.frame }) ?? true {
            frameChangedAt[window.windowId] = changedAt
            // The move has reached the layout; the usual settle period covers the redraw from here.
            awaitedMoves[window.windowId] = nil
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

    /// Notes that Veil asked Windows to move a window, before the layout says it moved.
    ///
    /// When a caption drag on the Mac ends, Veil moves the guest window to where the Mac window was
    /// dropped. Windows can present the moved window before the agent's next layout scan reaches the host,
    /// and cropping the old frame from that newer picture showed the desktop the window had just left, once
    /// per drag. The window keeps its last cropped picture from the request until the layout shows the move
    /// and it settles, or `awaitedMoveSeconds` pass.
    public func expectMove(windowId: String, toX x: Int, toY y: Int) {
        if let frame = latest?.windows.first(where: { $0.windowId == windowId })?.frame,
           frame.x == x, frame.y == y {
            return
        }
        expectFrameChange(windowId: windowId)
    }

    /// The same for a resize Veil asked for: Windows redraws the window at its new size before the layout
    /// reports it, and the old frame of that picture shows what the window uncovered.
    public func expectFrameChange(windowId: String) {
        awaitedMoves[windowId] = now().addingTimeInterval(Self.awaitedMoveSeconds)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.awaitedMoveSeconds + 0.02))
            self?.observers.values.forEach { $0() }
        }
    }

    /// True while a window's frame changed less than `settleSeconds` ago, or a move Veil asked for has
    /// not reached the layout yet.
    public func isSettling(windowId: String) -> Bool {
        let current = now()
        if let until = awaitedMoves[windowId], current < until {
            return true
        }
        guard let changedAt = frameChangedAt[windowId] else {
            return false
        }
        return current.timeIntervalSince(changedAt) < Self.settleSeconds
    }

    public func reset() {
        latest = nil
        frameChangedAt = [:]
        awaitedMoves = [:]
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

    /// Whether other windows hide all of a window in Windows, as an agent that reports visible parts says.
    /// Its Mac window is then behind the same windows, so its captured frames may come slowly: printing a
    /// hidden window several times a second took guest CPU from the apps in front.
    public func isWhollyCovered(windowId: String) -> Bool {
        latest.map { Self.isWhollyCovered(windowId: windowId, layout: $0) } ?? false
    }

    public nonisolated static func isWhollyCovered(windowId: String, layout: WindowLayoutEvent) -> Bool {
        guard !layout.showsSecureDesktop,
              let window = layout.windows.first(where: { $0.windowId == windowId }),
              window.isShown,
              !window.fullyVisible,
              let region = window.visibleRegion else {
            return false
        }
        return region.isEmpty
    }

    /// Like `framebufferCrop`, and also for a window other windows partly cover: then the crop comes with
    /// the parts of it the framebuffer shows, and the rest keeps the captured frame.
    public func framebufferCropRegion(
        windowId: String,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> FramebufferCropRegion? {
        guard let latest, !isSettling(windowId: windowId) else {
            return nil
        }
        return Self.framebufferCropRegion(
            windowId: windowId,
            layout: latest,
            framebufferWidth: framebufferWidth,
            framebufferHeight: framebufferHeight
        )
    }

    public nonisolated static func framebufferCropRegion(
        windowId: String,
        layout: WindowLayoutEvent,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> FramebufferCropRegion? {
        if let crop = framebufferCrop(
            windowId: windowId,
            layout: layout,
            framebufferWidth: framebufferWidth,
            framebufferHeight: framebufferHeight
        ) {
            return FramebufferCropRegion(crop: crop, visible: nil)
        }

        guard !layout.showsSecureDesktop,
              layout.display.width == framebufferWidth,
              layout.display.height == framebufferHeight,
              let window = layout.windows.first(where: { $0.windowId == windowId }),
              window.isShown,
              !window.fullyVisible,
              window.frame.width > 0,
              window.frame.height > 0,
              let region = window.visibleRegion else {
            return nil
        }

        let crop = CGRect(
            x: window.frame.x - layout.display.x,
            y: window.frame.y - layout.display.y,
            width: window.frame.width,
            height: window.frame.height
        )
        // A window reaching past the display keeps its captured frames; it is moved back onto the display.
        guard CGRect(x: 0, y: 0, width: framebufferWidth, height: framebufferHeight).contains(crop) else {
            return nil
        }
        let whole = CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
        let visible = region.prefix(FramebufferCropRegion.maximumVisibleRects).compactMap { rect -> CGRect? in
            let local = CGRect(
                x: rect.x - window.frame.x,
                y: rect.y - window.frame.y,
                width: rect.width,
                height: rect.height
            ).intersection(whole)
            return local.isNull || local.isEmpty ? nil : local
        }
        return visible.isEmpty ? nil : FramebufferCropRegion(crop: crop, visible: visible)
    }

    public nonisolated static func framebufferCrop(
        windowId: String,
        layout: WindowLayoutEvent,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> CGRect? {
        // VNC carries the primary display only; a layout whose display is a different size describes a
        // display change the framebuffer has not caught up with.
        // During a prompt or on the lock screen the framebuffer holds that screen, not the window.
        guard !layout.showsSecureDesktop,
              layout.display.width == framebufferWidth,
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

/// Where a window's pixels are in the guest framebuffer, and how much of the window they cover.
public struct FramebufferCropRegion: Equatable, Sendable {
    /// More than the agent sends; a guest is not trusted to keep to its own limit.
    public static let maximumVisibleRects = 32

    /// The window's frame in framebuffer pixels.
    public var crop: CGRect
    /// The parts of the window the framebuffer shows, relative to the frame's top-left corner, when other
    /// windows cover the rest. Nil when the framebuffer shows all of it.
    public var visible: [CGRect]?

    public init(crop: CGRect, visible: [CGRect]?) {
        self.crop = crop
        self.visible = visible
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

/// Keeps a Windows window's 1-pixel DWM border out of its Mac window.
///
/// The layout frame is the DWM extended frame bounds, which include that border. Windows 11 draws it
/// translucent, so a crop of the frame showed a line of whatever was behind the window on the guest
/// display, usually the wallpaper. The exact pixels are taken from inside the border, and the ring they
/// leave is filled by the same inner region stretched to the full size beneath them, so the ring shows the
/// window's own edge colours.
public struct CoherenceBorderlessCrop: Equatable, Sendable {
    /// The framebuffer region drawn pixel for pixel.
    public var inner: CGRect
    /// Where `inner` sits in the Mac content view, in guest pixels from its top-left corner.
    public var innerOffset: CGPoint

    /// Guest pixels to drop on each side: one Mac point, which covers the border at every Windows scale.
    public static func borderPixels(pointsPerPixel: CGFloat) -> CGFloat {
        guard pointsPerPixel > 0 else { return 1 }
        return max(1, (1 / pointsPerPixel).rounded(.up))
    }

    /// Nil when the window is too small to lose its border, in which case the whole crop is drawn.
    public init?(crop: CGRect, borderPixels: CGFloat) {
        let inner = crop.insetBy(dx: borderPixels, dy: borderPixels)
        guard borderPixels > 0, inner.width >= 1, inner.height >= 1 else {
            return nil
        }
        self.inner = inner
        innerOffset = CGPoint(x: borderPixels, y: borderPixels)
    }
}
