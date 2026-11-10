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

        #expect(fixture == WindowCropSetRequest(requestId: "req_window_crop_1A2B3C4D", windowIds: ["hwnd:000F0254"]))
    }

    @Test func aMovedOrResizedWindowSettlesBeforeCroppingResumes() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = GuestWindowLayoutStore(now: { clock })
        store.apply(layout(sequence: 1))
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
}
