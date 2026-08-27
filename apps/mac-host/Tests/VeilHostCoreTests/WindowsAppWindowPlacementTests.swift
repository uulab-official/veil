import Testing

@testable import VeilHostCore

@Suite("Windows app window placement")
struct WindowsAppWindowPlacementTests {
    @Test("keeps Calculator sized like a compact app window")
    func keepsCompactAppWindowSize() throws {
        let frame = WindowsAppWindowPlacement.initialFrame(
            for: WindowBounds(x: 0, y: 0, width: 520, height: 720),
            visibleFrame: HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.width == 520)
        #expect(frame.height == 720)
        #expect(frame.x == 460)
        #expect(frame.y == 90)
    }

    @Test("scales small HWND bounds without distorting aspect ratio")
    func scalesSmallWindowsByAspectRatio() throws {
        let frame = WindowsAppWindowPlacement.initialFrame(
            for: WindowBounds(x: 0, y: 0, width: 400, height: 300),
            visibleFrame: HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.width == 720)
        #expect(frame.height == 540)
    }

    @Test("keeps normal app windows close to their guest scale")
    func keepsNormalAppWindowsCloseToGuestScale() throws {
        let frame = WindowsAppWindowPlacement.initialFrame(
            for: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.width == 800)
        #expect(frame.height == 600)
        #expect(frame.x == 320)
        #expect(frame.y == 150)
    }

    @Test("clamps large app windows to the visible display")
    func clampsLargeWindowsToVisibleDisplay() throws {
        let frame = WindowsAppWindowPlacement.initialFrame(
            for: WindowBounds(x: 0, y: 0, width: 4000, height: 2400),
            visibleFrame: HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(frame.width <= 1440 * 0.92)
        #expect(frame.height <= 900 * 0.88)
    }

    @Test("cascades multiple app windows inside the visible display")
    func cascadesWindowsWithinVisibleDisplay() throws {
        let first = WindowsAppWindowPlacement.initialFrame(
            for: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900),
            existingWindowCount: 0
        )
        let second = WindowsAppWindowPlacement.initialFrame(
            for: WindowBounds(x: 0, y: 0, width: 800, height: 600),
            visibleFrame: HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900),
            existingWindowCount: 1
        )

        #expect(second.x == first.x + 28)
        #expect(second.y == first.y - 28)
        #expect(second.x + second.width <= 1440)
        #expect(second.y >= 0)
    }
}

/// Veil cannot resize the Windows window: there is no host-to-guest resize message in the protocol. Dragging
/// a mirrored window's corner therefore changes only how the guest's bitmap is presented, and the frame
/// surface renders with `scaledToFit` over black — so any shape other than the guest's produced black
/// letterbox bars. The window grew and the app did not.
///
/// Locking the ratio does not propagate the resize and does not pretend to. It makes the window behave
/// coherently: it still resizes, the image still scales, and it never letterboxes or distorts.
@Suite("Mirrored window resize constraints")
struct MirroredWindowResizeConstraintTests {
    @Test("locks a mirrored window to the guest window's shape")
    func locksToGuestShape() throws {
        let ratio = try #require(
            WindowsAppWindowPlacement.contentAspectRatio(for: WindowBounds(x: 0, y: 0, width: 1280, height: 800))
        )

        #expect(ratio.width == 1280)
        #expect(ratio.height == 800)
    }

    @Test("leaves a window freely resizable when the guest reported no size")
    func doesNotLockOnDegenerateBounds() {
        // A ratio derived from a zero dimension is a ratio derived from nothing. Freely resizable beats
        // locked to a guess.
        #expect(WindowsAppWindowPlacement.contentAspectRatio(for: WindowBounds(x: 0, y: 0, width: 0, height: 800)) == nil)
        #expect(WindowsAppWindowPlacement.contentAspectRatio(for: WindowBounds(x: 0, y: 0, width: 1280, height: 0)) == nil)
        #expect(WindowsAppWindowPlacement.contentAspectRatio(for: WindowBounds(x: 0, y: 0, width: 0, height: 0)) == nil)
    }

    @Test("derives the minimum size from the guest ratio instead of a fixed size")
    func minimumSizeFollowsGuestRatio() {
        // A fixed minimum fights an aspect-ratio lock: AppKit would have to violate one of them for a window
        // whose guest ratio does not match the minimum's.
        let minimum = WindowsAppWindowPlacement.minimumContentSize(
            for: WindowBounds(x: 0, y: 0, width: 1600, height: 800),
            shortestSide: 320
        )

        #expect(minimum.height == 320)
        #expect(minimum.width == 640)
    }

    @Test("gives a tall guest window a tall minimum")
    func minimumSizeForTallWindow() {
        // The floor applies to the *smaller* dimension, so a Calculator-shaped window does not get a minimum
        // as wide as a browser's.
        let minimum = WindowsAppWindowPlacement.minimumContentSize(
            for: WindowBounds(x: 0, y: 0, width: 520, height: 720),
            shortestSide: 320
        )

        #expect(minimum.width == 320)
        #expect(abs(minimum.height - 320 * (720.0 / 520.0)) < 0.001)
    }

    @Test("never demands a minimum larger than the guest window itself")
    func minimumNeverExceedsGuestWindow() {
        // A small utility window must not be handed a minimum it cannot satisfy.
        let minimum = WindowsAppWindowPlacement.minimumContentSize(
            for: WindowBounds(x: 0, y: 0, width: 200, height: 150),
            shortestSide: 320
        )

        #expect(minimum.width == 200)
        #expect(minimum.height == 150)
    }

    @Test("keeps the minimum on the guest ratio so the lock is satisfiable")
    func minimumMatchesLockedRatio() throws {
        let bounds = WindowBounds(x: 0, y: 0, width: 1280, height: 800)

        let ratio = try #require(WindowsAppWindowPlacement.contentAspectRatio(for: bounds))
        let minimum = WindowsAppWindowPlacement.minimumContentSize(for: bounds)

        // The whole point: a window can shrink to its minimum without breaking the aspect lock.
        #expect(abs(minimum.width / minimum.height - ratio.width / ratio.height) < 0.001)
    }

    @Test("survives a degenerate size without dividing by zero")
    func minimumSizeHandlesDegenerateBounds() {
        let minimum = WindowsAppWindowPlacement.minimumContentSize(for: WindowBounds(x: 0, y: 0, width: 0, height: 0))

        #expect(minimum.width > 0)
        #expect(minimum.height > 0)
    }

    @Test("newly placed windows already match the ratio they will be locked to")
    func initialFramePreservesGuestRatio() throws {
        // Otherwise the lock would snap a window the moment the user first touched its corner.
        let bounds = WindowBounds(x: 0, y: 0, width: 400, height: 300)
        let frame = WindowsAppWindowPlacement.initialFrame(
            for: bounds,
            visibleFrame: HostVisibleFrameGeometry(x: 0, y: 0, width: 1440, height: 900)
        )
        let ratio = try #require(WindowsAppWindowPlacement.contentAspectRatio(for: bounds))

        #expect(abs(frame.width / frame.height - ratio.width / ratio.height) < 0.001)
    }
}
