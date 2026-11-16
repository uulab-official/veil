import Foundation

/// One event for the guest's virtual pointer or keyboard, in the terms of QEMU's display connection (RFB).
public enum HardwareInputEvent: Equatable, Sendable {
    /// The pointer at a place on the guest display, in pixels, with these buttons held.
    case pointer(x: Int, y: Int, buttons: UInt8)
    /// A key by X11 keysym, pressed or released.
    case key(keysym: UInt32, isDown: Bool)
}

/// Sends input to Windows as if from a mouse and keyboard attached to the virtual machine.
@MainActor
public protocol GuestHardwareInputSending: AnyObject {
    /// Whether events sent now would arrive.
    var isReady: Bool { get }
    func send(_ events: [HardwareInputEvent])
}

/// Turns the input of a mirrored window into hardware events, for a window the agent cannot reach.
///
/// The agent injects input as the user's own programs may. Windows drops that for a window whose program
/// runs with administrator rights, so an installer shown as a Mac window ignored every click and key.
/// Input through the virtual hardware is what a person at the machine would give, and Windows takes it for
/// any window. It is aimed with the same geometry the window is cropped by: the guest display stands for
/// the Mac screen, so a point in the window is its frame's corner plus the offset.
public struct HardwareInputTranslator: Sendable {
    public static let leftButton: UInt8 = 1
    public static let rightButton: UInt8 = 4
    public static let wheelUp: UInt8 = 8
    public static let wheelDown: UInt8 = 16
    public static let wheelLeft: UInt8 = 32
    public static let wheelRight: UInt8 = 64
    /// Wheel units to a notch, as Windows counts them.
    public static let wheelUnitsPerNotch = 120
    /// The most notches one event turns the wheel, so a burst of trackpad input cannot flood the guest.
    public static let maximumNotchesPerEvent = 8

    private var buttons: UInt8 = 0
    private var heldPointerModifiers: [UInt32] = []
    private var wheelRemainder = (x: 0, y: 0)

    public init() {}

    /// - Parameters:
    ///   - x, y: the point in the window, in guest pixels from the window frame's top-left corner.
    ///   - origin: that corner on the guest display.
    public mutating func mouse(
        event: String,
        x: Int,
        y: Int,
        origin: (x: Int, y: Int),
        modifiers: [String] = [],
        deltaX: Int? = nil,
        deltaY: Int? = nil
    ) -> [HardwareInputEvent] {
        let px = origin.x + x
        let py = origin.y + y
        switch event {
        case "move":
            return [.pointer(x: px, y: py, buttons: buttons)]
        case "leftDown", "rightDown":
            // The modifiers stay down until the button comes up: a drag with a key held is read when it ends.
            let keys = Self.modifierKeysyms(modifiers).filter { !heldPointerModifiers.contains($0) }
            heldPointerModifiers += keys
            // QEMU applies a pointer event's buttons before its position, so the pointer is moved first.
            let before = buttons
            buttons |= event == "leftDown" ? Self.leftButton : Self.rightButton
            return keys.map { .key(keysym: $0, isDown: true) }
                + [.pointer(x: px, y: py, buttons: before), .pointer(x: px, y: py, buttons: buttons)]
        case "leftUp", "rightUp":
            let before = buttons
            buttons &= ~(event == "leftUp" ? Self.leftButton : Self.rightButton)
            var events: [HardwareInputEvent] = [
                .pointer(x: px, y: py, buttons: before), .pointer(x: px, y: py, buttons: buttons)
            ]
            if buttons == 0 {
                events += heldPointerModifiers.reversed().map { .key(keysym: $0, isDown: false) }
                heldPointerModifiers = []
            }
            return events
        case "scroll":
            // An event with neither amount is one notch up, as the protocol says.
            let horizontal = deltaX ?? 0
            let vertical = deltaX == nil && deltaY == nil ? Self.wheelUnitsPerNotch : (deltaY ?? 0)
            wheelRemainder.x += horizontal
            wheelRemainder.y += vertical
            var notches: [UInt8] = []
            notches += takeNotches(&wheelRemainder.y, positive: Self.wheelUp, negative: Self.wheelDown)
            notches += takeNotches(&wheelRemainder.x, positive: Self.wheelRight, negative: Self.wheelLeft)
            guard !notches.isEmpty else {
                return []
            }
            let keys = Self.modifierKeysyms(modifiers).filter { !heldPointerModifiers.contains($0) }
            return keys.map { .key(keysym: $0, isDown: true) }
                + [.pointer(x: px, y: py, buttons: buttons)]
                + notches.flatMap { [.pointer(x: px, y: py, buttons: buttons | $0), .pointer(x: px, y: py, buttons: buttons)] }
                + keys.reversed().map { .key(keysym: $0, isDown: false) }
        default:
            return []
        }
    }

    private func takeNotches(_ remainder: inout Int, positive: UInt8, negative: UInt8) -> [UInt8] {
        let count = remainder / Self.wheelUnitsPerNotch
        guard count != 0 else {
            return []
        }
        remainder -= count * Self.wheelUnitsPerNotch
        return Array(repeating: count > 0 ? positive : negative, count: min(abs(count), Self.maximumNotchesPerEvent))
    }

    /// The events for one `input.key`: modifiers go down before the key and come up after it. Empty for a
    /// key with no place on a keyboard QEMU knows.
    public func key(event: String, windowsVirtualKey: Int, modifiers: [String] = []) -> [HardwareInputEvent] {
        guard let keysym = Self.keysym(forWindowsVirtualKey: windowsVirtualKey) else {
            return []
        }
        let keys = Self.modifierKeysyms(modifiers).filter { $0 != keysym }
        switch event {
        case "keyDown":
            return keys.map { .key(keysym: $0, isDown: true) } + [.key(keysym: keysym, isDown: true)]
        case "keyUp":
            return [.key(keysym: keysym, isDown: false)] + keys.reversed().map { .key(keysym: $0, isDown: false) }
        default:
            return []
        }
    }

    /// Types text as key presses on a US keyboard, which is how QEMU reads keysyms. Nil when the text has a
    /// character that keyboard cannot type, such as Hangul: typing part of it would be worse than none.
    public func text(_ text: String) -> [HardwareInputEvent]? {
        var events: [HardwareInputEvent] = []
        for character in text {
            guard let stroke = Self.keystroke(for: character) else {
                return nil
            }
            if stroke.shift {
                events.append(.key(keysym: Self.shiftKeysym, isDown: true))
            }
            events.append(.key(keysym: stroke.keysym, isDown: true))
            events.append(.key(keysym: stroke.keysym, isDown: false))
            if stroke.shift {
                events.append(.key(keysym: Self.shiftKeysym, isDown: false))
            }
        }
        return events
    }

    // MARK: - Keys

    static let shiftKeysym: UInt32 = 0xFFE1
    static let controlKeysym: UInt32 = 0xFFE3
    static let altKeysym: UInt32 = 0xFFE9
    /// Super_L, the Windows logo key in QEMU's keymap.
    static let windowsKeysym: UInt32 = 0xFFEB

    static func modifierKeysyms(_ modifiers: [String]) -> [UInt32] {
        modifiers.compactMap { modifier in
            switch modifier {
            case "ctrl": controlKeysym
            case "shift": shiftKeysym
            case "alt": altKeysym
            case "win", "meta": windowsKeysym
            default: nil
            }
        }
    }

    /// The X11 keysym of the key a Windows virtual key sits on, on a US keyboard:
    /// https://learn.microsoft.com/windows/win32/inputdev/virtual-key-codes
    public static func keysym(forWindowsVirtualKey key: Int) -> UInt32? {
        switch key {
        case 0x30...0x39: return UInt32(key)                 // 0-9
        case 0x41...0x5A: return UInt32(key) + 0x20          // A-Z, as the unshifted letter
        case 0x60...0x69: return 0xFFB0 + UInt32(key - 0x60) // numeric keypad 0-9
        case 0x70...0x7B: return 0xFFBE + UInt32(key - 0x70) // F1-F12
        default: return otherKeysyms[key]
        }
    }

    private static let otherKeysyms: [Int: UInt32] = [
        0x08: 0xFF08, 0x09: 0xFF09, 0x0D: 0xFF0D, 0x1B: 0xFF1B, 0x20: 0x20,
        0x21: 0xFF55, 0x22: 0xFF56, 0x23: 0xFF57, 0x24: 0xFF50,
        0x25: 0xFF51, 0x26: 0xFF52, 0x27: 0xFF53, 0x28: 0xFF54,
        0x2D: 0xFF63, 0x2E: 0xFFFF,
        0x10: shiftKeysym, 0xA0: shiftKeysym, 0xA1: 0xFFE2,
        0x11: controlKeysym, 0xA2: controlKeysym, 0xA3: 0xFFE4,
        0x12: altKeysym, 0xA4: altKeysym, 0xA5: 0xFFEA,
        0x5B: windowsKeysym, 0x5C: 0xFFEC, 0x5D: 0xFF67, 0x14: 0xFFE5,
        0x6A: 0xFFAA, 0x6B: 0xFFAB, 0x6D: 0xFFAD, 0x6E: 0xFFAE, 0x6F: 0xFFAF,
        0xBA: 0x3B, 0xBB: 0x3D, 0xBC: 0x2C, 0xBD: 0x2D, 0xBE: 0x2E, 0xBF: 0x2F, 0xC0: 0x60,
        0xDB: 0x5B, 0xDC: 0x5C, 0xDD: 0x5D, 0xDE: 0x27
    ]

    private static let shiftedSymbols: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
        "~": "`"
    ]

    static func keystroke(for character: Character) -> (keysym: UInt32, shift: Bool)? {
        if character == "\n" || character == "\r" {
            return (0xFF0D, false)
        }
        if character == "\t" {
            return (0xFF09, false)
        }
        if let base = shiftedSymbols[character], let value = base.asciiValue {
            return (UInt32(value), true)
        }
        guard let value = character.asciiValue, (0x20...0x7E).contains(value) else {
            return nil
        }
        if character.isUppercase {
            return (UInt32(value) + 0x20, true)
        }
        return (UInt32(value), false)
    }
}

/// Where a mirrored window's input goes.
public enum HardwareInputRouting {
    /// The window frame's corner on the guest display when the window takes input through the hardware:
    /// the layout marks it as running above the agent and shows it. Nil for any other window.
    public static func origin(windowId: String, layout: WindowLayoutEvent?) -> (x: Int, y: Int)? {
        guard let layout,
              !layout.showsSecureDesktop,
              let window = layout.windows.first(where: { $0.windowId == windowId }),
              window.elevated == true,
              window.isShown else {
            return nil
        }
        return (window.frame.x - layout.display.x, window.frame.y - layout.display.y)
    }

    /// Whether another tracked window lies over this point of the window in Windows. A click sent through
    /// the hardware lands on whatever is on top there, so one aimed at a covered point is not sent.
    public static func isCovered(windowId: String, x: Int, y: Int, layout: WindowLayoutEvent) -> Bool {
        guard let window = layout.windows.first(where: { $0.windowId == windowId }) else {
            return true
        }
        let px = window.frame.x + x
        let py = window.frame.y + y
        return layout.windows.contains { other in
            other.windowId != windowId
                && other.ownerWindowId != windowId
                && other.isShown
                && other.zOrder < window.zOrder
                && px >= other.frame.x && px < other.frame.x + other.frame.width
                && py >= other.frame.y && py < other.frame.y + other.frame.height
        }
    }
}
