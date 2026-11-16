import Testing

@testable import VeilHostShell

@Suite("Shell navigation view mode")
@MainActor
struct ShellNavigationViewModeTests {
    @Test("a desktop Veil chose is marked automatic so the first app frame can return to apps")
    func marksVeilChosenDesktopAutomatic() {
        let navigation = ShellNavigation()

        navigation.showDesktopAutomatically(true)

        #expect(navigation.viewMode == .desktop)
        #expect(navigation.isShowingDesktopAutomatically)
    }

    @Test("a desktop the user picked is never taken away by an arriving app frame")
    func userPickedDesktopIsNotAutomatic() {
        let navigation = ShellNavigation()
        navigation.showDesktopAutomatically(true)

        navigation.viewMode = .apps
        navigation.viewMode = .desktop

        #expect(navigation.viewMode == .desktop)
        #expect(!navigation.isShowingDesktopAutomatically)
    }
}
