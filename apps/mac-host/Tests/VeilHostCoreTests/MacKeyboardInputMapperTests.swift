import Testing

@testable import VeilHostCore

@Suite("Mac keyboard input mapper")
struct MacKeyboardInputMapperTests {
    @Test("maps Command shortcuts to Windows control modifiers")
    func mapsCommandShortcutsToWindowsControlModifiers() {
        let mapper = MacKeyboardInputMapper()

        let input = mapper.input(
            charactersIgnoringModifiers: "c",
            keyCode: 8,
            modifiers: [.command]
        )

        #expect(input == MacKeyboardInput(key: "c", windowsVirtualKey: 67, modifiers: ["ctrl"]))
    }

    @Test("maps navigation keys to Windows virtual keys")
    func mapsNavigationKeysToWindowsVirtualKeys() {
        let mapper = MacKeyboardInputMapper()

        #expect(mapper.input(charactersIgnoringModifiers: nil, keyCode: 36)?.windowsVirtualKey == 13)
        #expect(mapper.input(charactersIgnoringModifiers: nil, keyCode: 123)?.key == "arrowLeft")
        #expect(mapper.input(charactersIgnoringModifiers: nil, keyCode: 126)?.windowsVirtualKey == 38)
    }

    @Test("maps option and shift modifiers to Windows alt and shift")
    func mapsOptionAndShiftModifiersToWindowsAltAndShift() {
        let mapper = MacKeyboardInputMapper()

        let input = mapper.input(
            charactersIgnoringModifiers: "s",
            keyCode: 1,
            modifiers: [.option, .shift]
        )

        #expect(input == MacKeyboardInput(key: "s", windowsVirtualKey: 83, modifiers: ["shift", "alt"]))
    }
}
