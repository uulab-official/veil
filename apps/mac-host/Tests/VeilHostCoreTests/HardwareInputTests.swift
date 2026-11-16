import Foundation
import Testing
@testable import VeilHostCore

struct HardwareInputTests {
    private let origin = (x: 400, y: 300)

    @Test func aClickMovesFirstThenPressesAndReleases() {
        var translator = HardwareInputTranslator()

        let down = translator.mouse(event: "leftDown", x: 20, y: 10, origin: origin)
        let up = translator.mouse(event: "leftUp", x: 20, y: 10, origin: origin)

        // QEMU applies buttons before position, so each change is preceded by the pointer arriving.
        #expect(down == [.pointer(x: 420, y: 310, buttons: 0), .pointer(x: 420, y: 310, buttons: 1)])
        #expect(up == [.pointer(x: 420, y: 310, buttons: 1), .pointer(x: 420, y: 310, buttons: 0)])
    }

    @Test func aDragKeepsItsButtonAndItsModifierUntilTheRelease() {
        var translator = HardwareInputTranslator()

        let down = translator.mouse(event: "leftDown", x: 0, y: 0, origin: origin, modifiers: ["ctrl"])
        let move = translator.mouse(event: "move", x: 50, y: 5, origin: origin)
        let up = translator.mouse(event: "leftUp", x: 50, y: 5, origin: origin)

        #expect(down.first == .key(keysym: 0xFFE3, isDown: true))
        #expect(move == [.pointer(x: 450, y: 305, buttons: 1)])
        #expect(up.last == .key(keysym: 0xFFE3, isDown: false))
    }

    @Test func theRightButtonIsItsOwnBit() {
        var translator = HardwareInputTranslator()

        let down = translator.mouse(event: "rightDown", x: 1, y: 1, origin: origin)

        #expect(down.last == .pointer(x: 401, y: 301, buttons: 4))
    }

    @Test func scrollingTurnsTheWheelANotchPer120UnitsAndKeepsTheRest() {
        var translator = HardwareInputTranslator()

        // Trackpad input arrives in small amounts.
        #expect(translator.mouse(event: "scroll", x: 5, y: 5, origin: origin, deltaY: 70).isEmpty)
        let notch = translator.mouse(event: "scroll", x: 5, y: 5, origin: origin, deltaY: 70)
        #expect(notch == [
            .pointer(x: 405, y: 305, buttons: 0),
            .pointer(x: 405, y: 305, buttons: 8),
            .pointer(x: 405, y: 305, buttons: 0)
        ])

        // The 20 units left over count against the next turn the other way: 20 - 240 is one notch down
        // and 100 more to go.
        let down = translator.mouse(event: "scroll", x: 5, y: 5, origin: origin, deltaY: -240)
        #expect(down.filter { $0 == .pointer(x: 405, y: 305, buttons: 16) }.count == 1)
        let rest = translator.mouse(event: "scroll", x: 5, y: 5, origin: origin, deltaY: -20)
        #expect(rest.filter { $0 == .pointer(x: 405, y: 305, buttons: 16) }.count == 1)

        // Neither amount: one notch up.
        var fresh = HardwareInputTranslator()
        let plain = fresh.mouse(event: "scroll", x: 5, y: 5, origin: origin)
        #expect(plain.contains(.pointer(x: 405, y: 305, buttons: 8)))
    }

    @Test func aPinchIsControlAroundTheWheel() {
        var translator = HardwareInputTranslator()

        let zoom = translator.mouse(event: "scroll", x: 5, y: 5, origin: origin, modifiers: ["ctrl"], deltaY: 120)

        #expect(zoom.first == .key(keysym: 0xFFE3, isDown: true))
        #expect(zoom.last == .key(keysym: 0xFFE3, isDown: false))
    }

    @Test func aBurstOfScrollingIsCapped() {
        var translator = HardwareInputTranslator()

        let burst = translator.mouse(event: "scroll", x: 5, y: 5, origin: origin, deltaY: 120 * 500)

        #expect(burst.filter { $0 == .pointer(x: 405, y: 305, buttons: 8) }.count == HardwareInputTranslator.maximumNotchesPerEvent)
    }

    @Test func keysGoByTheirPlaceOnAUSKeyboardWithModifiersAround() {
        let translator = HardwareInputTranslator()

        #expect(translator.key(event: "keyDown", windowsVirtualKey: 67, modifiers: ["ctrl"]) == [
            .key(keysym: 0xFFE3, isDown: true), .key(keysym: 0x63, isDown: true)
        ])
        #expect(translator.key(event: "keyUp", windowsVirtualKey: 67, modifiers: ["ctrl"]) == [
            .key(keysym: 0x63, isDown: false), .key(keysym: 0xFFE3, isDown: false)
        ])
        // Enter, an arrow, F5, the semicolon key.
        #expect(HardwareInputTranslator.keysym(forWindowsVirtualKey: 0x0D) == 0xFF0D)
        #expect(HardwareInputTranslator.keysym(forWindowsVirtualKey: 0x25) == 0xFF51)
        #expect(HardwareInputTranslator.keysym(forWindowsVirtualKey: 0x74) == 0xFFC2)
        #expect(HardwareInputTranslator.keysym(forWindowsVirtualKey: 0xBA) == 0x3B)
        // A key QEMU's keyboard has no place for sends nothing.
        #expect(translator.key(event: "keyDown", windowsVirtualKey: 166).isEmpty)
        // Shift by itself is not pressed twice.
        #expect(translator.key(event: "keyDown", windowsVirtualKey: 0x10, modifiers: ["shift"]) == [
            .key(keysym: 0xFFE1, isDown: true)
        ])
    }

    @Test func typesPlainTextAndRefusesWhatAUSKeyboardCannotType() throws {
        let translator = HardwareInputTranslator()

        let typed = try #require(translator.text("C:\\a!"))
        #expect(typed == [
            .key(keysym: 0xFFE1, isDown: true), .key(keysym: 0x63, isDown: true), .key(keysym: 0x63, isDown: false),
            .key(keysym: 0xFFE1, isDown: false),
            .key(keysym: 0xFFE1, isDown: true), .key(keysym: 0x3B, isDown: true), .key(keysym: 0x3B, isDown: false),
            .key(keysym: 0xFFE1, isDown: false),
            .key(keysym: 0x5C, isDown: true), .key(keysym: 0x5C, isDown: false),
            .key(keysym: 0x61, isDown: true), .key(keysym: 0x61, isDown: false),
            .key(keysym: 0xFFE1, isDown: true), .key(keysym: 0x31, isDown: true), .key(keysym: 0x31, isDown: false),
            .key(keysym: 0xFFE1, isDown: false)
        ])
        #expect(translator.text("안녕") == nil)
        #expect(translator.text("ok 안") == nil)
    }

    private func layout(elevated: Bool?, secure: Bool = false) -> WindowLayoutEvent {
        WindowLayoutEvent(
            sequence: 1,
            display: GuestPixelRect(x: 0, y: 0, width: 1920, height: 1080),
            windows: [
                .init(windowId: "hwnd:2", frame: GuestPixelRect(x: 500, y: 400, width: 300, height: 200), zOrder: 0, isForeground: true, isShown: true, fullyVisible: true),
                .init(windowId: "hwnd:1", frame: GuestPixelRect(x: 400, y: 300, width: 600, height: 400), zOrder: 1, isForeground: false, isShown: true, fullyVisible: false, elevated: elevated)
            ],
            secureDesktop: secure
        )
    }

    @Test func onlyAWindowAboveTheAgentTakesHardwareInput() throws {
        let origin = try #require(HardwareInputRouting.origin(windowId: "hwnd:1", layout: layout(elevated: true)))
        #expect(origin.x == 400)
        #expect(origin.y == 300)
        #expect(HardwareInputRouting.origin(windowId: "hwnd:1", layout: layout(elevated: nil)) == nil)
        #expect(HardwareInputRouting.origin(windowId: "hwnd:2", layout: layout(elevated: true)) == nil)
        #expect(HardwareInputRouting.origin(windowId: "hwnd:1", layout: layout(elevated: true, secure: true)) == nil)
        #expect(HardwareInputRouting.origin(windowId: "hwnd:1", layout: nil) == nil)
    }

    @Test func aPointUnderAnotherWindowIsCovered() {
        let layout = layout(elevated: true)

        // hwnd:2 lies over (500...800, 400...600), which is (100...400, 100...300) in hwnd:1.
        #expect(HardwareInputRouting.isCovered(windowId: "hwnd:1", x: 150, y: 150, layout: layout))
        #expect(!HardwareInputRouting.isCovered(windowId: "hwnd:1", x: 20, y: 20, layout: layout))
        // The window in front is covered by nothing.
        #expect(!HardwareInputRouting.isCovered(windowId: "hwnd:2", x: 10, y: 10, layout: layout))
    }
}
