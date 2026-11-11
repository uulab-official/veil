import Testing
@testable import VeilHostCore

struct MacPhysicalKeyMapTests {
    @Test("letters map by position, so a Korean input source still sends the key Windows composes from")
    func lettersByPosition() {
        // A (ㅁ), K (ㅏ), Q (ㅂ), R (ㄱ).
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 0) == 0x41)
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 40) == 0x4B)
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 12) == 0x51)
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 15) == 0x52)
    }

    @Test("punctuation, editing, and function keys that the character mapper dropped")
    func keysWithoutASCII() {
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 43) == 0xBC) // ,
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 117) == 0x2E) // forward delete
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 115) == 0x24) // home
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 122) == 0x70) // F1
        #expect(MacPhysicalKeyMap.keyName(forMacKeyCode: 51) == "backspace")
        #expect(MacPhysicalKeyMap.keyName(forMacKeyCode: 0) == "vk41")
    }

    @Test("Caps Lock and modifier keys are not sent: on a Mac they switch the input source")
    func modifiersStayOnTheMac() {
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 57) == nil) // Caps Lock
        #expect(MacPhysicalKeyMap.windowsVirtualKey(forMacKeyCode: 55) == nil) // Command
    }

    @Test("Windows composes whenever the Mac input source is Korean, in either view")
    func imeFollowsMac() {
        #expect(GuestImeMode.desired(macInputSourceLanguages: ["ko"], macInputSourceIsInputMode: true) == .native)
        #expect(GuestImeMode.desired(macInputSourceLanguages: ["en"], macInputSourceIsInputMode: false) == .alphanumeric)
    }
}
