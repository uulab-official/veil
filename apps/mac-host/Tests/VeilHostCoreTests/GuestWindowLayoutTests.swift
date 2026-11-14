import CoreGraphics
import Foundation
import Testing
@testable import VeilHostCore

@MainActor
struct GuestWindowLayoutTests {
    private func layout(sequence: Int = 1, fullyVisible: Bool = true, frame: GuestPixelRect = GuestPixelRect(x: 120, y: 80, width: 800, height: 600)) -> WindowLayoutEvent {
        WindowLayoutEvent(
            sequence: sequence,
            display: GuestPixelRect(x: 0, y: 0, width: 1920, height: 1080),
            windows: [
                .init(windowId: "hwnd:1", frame: frame, zOrder: 0, isForeground: true, isShown: true, fullyVisible: fullyVisible)
            ]
        )
    }

    @Test func decodesTheProtocolFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("harness/protocol-fixtures/window.layout.json")
        let event = try JSONDecoder.veilProtocol.decode(WindowLayoutEvent.self, from: Data(contentsOf: url))

        #expect(event.type == .windowLayout)
        #expect(event.sequence == 412)
        #expect(event.windows.map(\.windowId) == ["hwnd:000F0254", "hwnd:0003029A"])
        #expect(event.windows[1].fullyVisible == false)
    }

    @Test func cropsOnlyFullyVisibleWindowsFromAMatchingFramebuffer() {
        let visible = layout()
        #expect(GuestWindowLayoutStore.framebufferCrop(windowId: "hwnd:1", layout: visible, framebufferWidth: 1920, framebufferHeight: 1080)
            == CGRect(x: 120, y: 80, width: 800, height: 600))
        // A framebuffer that has not caught up with a display resize.
        #expect(GuestWindowLayoutStore.framebufferCrop(windowId: "hwnd:1", layout: visible, framebufferWidth: 1184, framebufferHeight: 848) == nil)
        #expect(GuestWindowLayoutStore.framebufferCrop(windowId: "hwnd:2", layout: visible, framebufferWidth: 1920, framebufferHeight: 1080) == nil)
        #expect(GuestWindowLayoutStore.framebufferCrop(windowId: "hwnd:1", layout: layout(fullyVisible: false), framebufferWidth: 1920, framebufferHeight: 1080) == nil)
    }

    @Test func nothingIsCroppedWhileTheSecureDesktopHasTheDisplay() throws {
        var secure = layout()
        secure.secureDesktop = true
        #expect(secure.showsSecureDesktop)
        #expect(GuestWindowLayoutStore.framebufferCrop(windowId: "hwnd:1", layout: secure, framebufferWidth: 1920, framebufferHeight: 1080) == nil)

        let json = Data(#"{"type":"window.layout","sequence":7,"display":{"x":0,"y":0,"width":1920,"height":1080},"secureDesktop":true,"windows":[]}"#.utf8)
        #expect(try JSONDecoder.veilProtocol.decode(WindowLayoutEvent.self, from: json).showsSecureDesktop)
        // An agent that does not report it.
        let older = Data(#"{"type":"window.layout","sequence":7,"display":{"x":0,"y":0,"width":1920,"height":1080},"windows":[]}"#.utf8)
        #expect(!(try JSONDecoder.veilProtocol.decode(WindowLayoutEvent.self, from: older).showsSecureDesktop))
    }

    @Test func aPartlyCoveredWindowIsCroppedWhereItShows() throws {
        // 800 by 600 at (120, 80), with its lower right quarter under another window.
        let covered = WindowLayoutEvent(
            sequence: 1,
            display: GuestPixelRect(x: 0, y: 0, width: 1920, height: 1080),
            windows: [
                .init(
                    windowId: "hwnd:1",
                    frame: GuestPixelRect(x: 120, y: 80, width: 800, height: 600),
                    zOrder: 1,
                    isForeground: false,
                    isShown: true,
                    fullyVisible: false,
                    visibleRegion: [
                        GuestPixelRect(x: 120, y: 80, width: 800, height: 300),
                        GuestPixelRect(x: 120, y: 380, width: 400, height: 300)
                    ]
                )
            ]
        )

        let region = try #require(GuestWindowLayoutStore.framebufferCropRegion(
            windowId: "hwnd:1", layout: covered, framebufferWidth: 1920, framebufferHeight: 1080))

        #expect(region.crop == CGRect(x: 120, y: 80, width: 800, height: 600))
        // Relative to the window's own corner.
        #expect(region.visible == [CGRect(x: 0, y: 0, width: 800, height: 300), CGRect(x: 0, y: 300, width: 400, height: 300)])
        // The whole-window crop still refuses it.
        #expect(GuestWindowLayoutStore.framebufferCrop(windowId: "hwnd:1", layout: covered, framebufferWidth: 1920, framebufferHeight: 1080) == nil)
    }

    @Test func aCoveredWindowWithNothingToShowKeepsItsCapturedFrames() {
        func layout(region: [GuestPixelRect]?, secure: Bool = false, x: Int = 120) -> WindowLayoutEvent {
            WindowLayoutEvent(
                sequence: 1,
                display: GuestPixelRect(x: 0, y: 0, width: 1920, height: 1080),
                windows: [
                    .init(
                        windowId: "hwnd:1",
                        frame: GuestPixelRect(x: x, y: 80, width: 800, height: 600),
                        zOrder: 1,
                        isForeground: false,
                        isShown: true,
                        fullyVisible: false,
                        visibleRegion: region
                    )
                ],
                secureDesktop: secure
            )
        }
        func region(_ layout: WindowLayoutEvent) -> FramebufferCropRegion? {
            GuestWindowLayoutStore.framebufferCropRegion(windowId: "hwnd:1", layout: layout, framebufferWidth: 1920, framebufferHeight: 1080)
        }
        let piece = [GuestPixelRect(x: 120, y: 80, width: 800, height: 300)]

        // Wholly covered, an agent that does not report the region, the secure desktop, off the display.
        #expect(region(layout(region: [])) == nil)
        #expect(region(layout(region: nil)) == nil)
        #expect(region(layout(region: piece, secure: true)) == nil)
        #expect(region(layout(region: piece, x: -40)) == nil)
        // A piece outside the window is dropped rather than drawn.
        #expect(region(layout(region: [GuestPixelRect(x: 1500, y: 900, width: 50, height: 50)])) == nil)
    }

    @Test func tellsAWindowHiddenBehindOthersFromOneThatShows() {
        func layout(fullyVisible: Bool, region: [GuestPixelRect]?) -> WindowLayoutEvent {
            WindowLayoutEvent(
                sequence: 1,
                display: GuestPixelRect(x: 0, y: 0, width: 1920, height: 1080),
                windows: [
                    .init(
                        windowId: "hwnd:1",
                        frame: GuestPixelRect(x: 120, y: 80, width: 800, height: 600),
                        zOrder: 1,
                        isForeground: false,
                        isShown: true,
                        fullyVisible: fullyVisible,
                        visibleRegion: region
                    )
                ]
            )
        }

        #expect(GuestWindowLayoutStore.isWhollyCovered(windowId: "hwnd:1", layout: layout(fullyVisible: false, region: [])))
        #expect(!GuestWindowLayoutStore.isWhollyCovered(
            windowId: "hwnd:1",
            layout: layout(fullyVisible: false, region: [GuestPixelRect(x: 120, y: 80, width: 10, height: 10)])
        ))
        #expect(!GuestWindowLayoutStore.isWhollyCovered(windowId: "hwnd:1", layout: layout(fullyVisible: true, region: nil)))
        // An agent that does not say: its windows keep their usual captures.
        #expect(!GuestWindowLayoutStore.isWhollyCovered(windowId: "hwnd:1", layout: layout(fullyVisible: false, region: nil)))
        #expect(!GuestWindowLayoutStore.isWhollyCovered(windowId: "hwnd:2", layout: layout(fullyVisible: false, region: [])))
    }

    @Test func aFullyVisibleWindowIsCroppedWhole() {
        let region = GuestWindowLayoutStore.framebufferCropRegion(
            windowId: "hwnd:1", layout: layout(), framebufferWidth: 1920, framebufferHeight: 1080)
        #expect(region == FramebufferCropRegion(crop: CGRect(x: 120, y: 80, width: 800, height: 600), visible: nil))
    }

    @Test func aWindowSeenForTheFirstTimeSettlesBeforeItIsCropped() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = GuestWindowLayoutStore(now: { clock })

        store.apply(layout(sequence: 1))
        // Windows is still fading the window in; the framebuffer shows the desktop there.
        #expect(store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) == nil)

        clock = clock.addingTimeInterval(GuestWindowLayoutStore.settleSeconds + 0.01)
        #expect(store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) != nil)
        // The same frame again starts no new wait.
        store.apply(layout(sequence: 2))
        #expect(store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) != nil)
    }

    @Test func ignoresOlderLayoutsButAcceptsARestartedAgent() {
        let store = GuestWindowLayoutStore()
        var notified = 0
        _ = store.observe { notified += 1 }

        #expect(store.apply(layout(sequence: 5)))
        #expect(!store.apply(layout(sequence: 4)))
        #expect(store.apply(layout(sequence: 1)))
        #expect(store.latest?.sequence == 1)
        #expect(notified == 2)
    }

    @Test func handlesLayoutEventsFromTheAgent() async throws {
        let model = HostDashboardModel(service: DemoHostDashboardService())
        let data = try JSONEncoder().encode(layout(sequence: 900))

        let result = try await model.receiveProtocolMessage(data)

        #expect(result == .handledWindowLayout(sequence: 900))
        #expect(GuestWindowLayoutStore.shared.latest?.sequence == 900)
        GuestWindowLayoutStore.shared.reset()
    }

    @Test func fitsWindowsPastTheDisplayEdgeOrUnderTheTaskbar() {
        let display = GuestPixelRect(x: 0, y: 0, width: 1184, height: 848)
        #expect(CoherenceDisplayFit.needsFit(window: GuestPixelRect(x: 0, y: 0, width: 1299, height: 600), display: display))
        #expect(CoherenceDisplayFit.needsFit(window: GuestPixelRect(x: 0, y: 300, width: 800, height: 540), display: display))
        #expect(!CoherenceDisplayFit.needsFit(window: GuestPixelRect(x: 40, y: 40, width: 800, height: 600), display: display))
    }

    @Test func encodesTheCropSetFixtureShape() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("harness/protocol-fixtures/window.crop.set.json")
        let fixture = try JSONDecoder.veilProtocol.decode(WindowCropSetRequest.self, from: Data(contentsOf: url))

        #expect(fixture == WindowCropSetRequest(requestId: "req_window_crop_1A2B3C4D", windowIds: ["hwnd:000F0254"], hidesDesktop: true))
    }

    @Test func aMovedOrResizedWindowSettlesBeforeCroppingResumes() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = GuestWindowLayoutStore(now: { clock })
        store.apply(layout(sequence: 1))
        // Past the wait a window gets when it is first seen.
        clock += GuestWindowLayoutStore.settleSeconds + 0.01
        #expect(store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) != nil)

        clock += 0.05
        store.apply(layout(sequence: 2, frame: GuestPixelRect(x: 120, y: 80, width: 900, height: 600)))
        #expect(store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) == nil)

        clock += 0.2
        store.apply(layout(sequence: 3, frame: GuestPixelRect(x: 120, y: 80, width: 900, height: 600)))
        #expect(store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) == nil)

        clock += 0.11
        #expect(store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080)
            == CGRect(x: 120, y: 80, width: 900, height: 600))
    }

    @Test func aMoveVeilAskedForHoldsTheLastPictureUntilTheLayoutShowsIt() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = GuestWindowLayoutStore(now: { clock })
        let crop = { store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) }
        store.apply(layout(sequence: 1))
        clock += GuestWindowLayoutStore.settleSeconds + 0.01
        #expect(crop() != nil)

        // The drop of a caption drag: Windows may present the moved window before the layout says so, and
        // the old frame of that picture is desktop.
        store.expectMove(windowId: "hwnd:1", toX: 400, toY: 300)
        #expect(crop() == nil)
        clock += 0.5
        #expect(crop() == nil)

        // The layout catches up; the usual settle period follows, then cropping resumes at the new frame.
        store.apply(layout(sequence: 2, frame: GuestPixelRect(x: 400, y: 300, width: 800, height: 600)))
        #expect(crop() == nil)
        clock += GuestWindowLayoutStore.settleSeconds + 0.01
        #expect(crop() == CGRect(x: 400, y: 300, width: 800, height: 600))
    }

    @Test func aMoveThatNeverArrivesStopsHoldingAfterAWhile() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = GuestWindowLayoutStore(now: { clock })
        let crop = { store.framebufferCrop(windowId: "hwnd:1", framebufferWidth: 1920, framebufferHeight: 1080) }
        store.apply(layout(sequence: 1))
        clock += GuestWindowLayoutStore.settleSeconds + 0.01

        // A move to where the window already is waits for nothing.
        store.expectMove(windowId: "hwnd:1", toX: 120, toY: 80)
        #expect(crop() != nil)

        store.expectMove(windowId: "hwnd:1", toX: 400, toY: 300)
        clock += GuestWindowLayoutStore.awaitedMoveSeconds + 0.01
        #expect(crop() != nil)
    }

    @Test func placesAMacWindowAtTheSameSpotOnAMatchingGuestDisplay() throws {
        // A 1512x982-point screen and a guest display of the same size.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let display = GuestPixelRect(x: 0, y: 0, width: 1512, height: 982)
        // Content 120 points from the left and 100 points below the top of the screen.
        let content = CGRect(x: 120, y: 982 - 100 - 600, width: 800, height: 600)

        let origin = try #require(CoherencePlacement.guestOrigin(contentFrame: content, screenFrame: screen, display: display))
        #expect(origin.x == 120 && origin.y == 100)

        // A second screen to the right maps its own top-left to the display's.
        let second = CGRect(x: 1512, y: 0, width: 1512, height: 982)
        let onSecond = try #require(CoherencePlacement.guestOrigin(
            contentFrame: content.offsetBy(dx: 1512, dy: 0), screenFrame: second, display: display))
        #expect(onSecond.x == 120 && onSecond.y == 100)

        #expect(CoherencePlacement.displayMatching(screenFrame: screen) == GuestDisplaySize(width: 1512, height: 982))
    }
}
