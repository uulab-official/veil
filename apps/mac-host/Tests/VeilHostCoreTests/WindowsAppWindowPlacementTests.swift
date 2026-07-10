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
