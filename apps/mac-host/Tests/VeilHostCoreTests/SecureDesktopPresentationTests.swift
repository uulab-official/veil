import Testing
@testable import VeilHostCore

struct SecureDesktopPresentationTests {
    private func action(
        isSecure: Bool = true,
        canShowDisplay: Bool = true,
        showsApps: Bool = true,
        isWindowShown: Bool = false,
        wasDismissed: Bool = false,
        appIsActive: Bool = true,
        attentionRequested: Bool = false
    ) -> SecureDesktopPresentation.Action {
        SecureDesktopPresentation.action(
            isSecure: isSecure,
            canShowDisplay: canShowDisplay,
            showsApps: showsApps,
            isWindowShown: isWindowShown,
            wasDismissed: wasDismissed,
            appIsActive: appIsActive,
            attentionRequested: attentionRequested
        )
    }

    @Test func showsThePromptWhileVeilIsInUse() {
        #expect(action() == .show)
        #expect(action(isWindowShown: true) == .none)
    }

    @Test func asksForAttentionOnceInsteadOfOpeningOverAnotherApp() {
        #expect(action(appIsActive: false) == .requestAttention)
        #expect(action(appIsActive: false, attentionRequested: true) == .none)
        // Coming back to Veil shows it.
        #expect(action(appIsActive: true, attentionRequested: true) == .show)
    }

    @Test func aPromptTheUserClosedStaysClosed() {
        #expect(action(wasDismissed: true) == .none)
    }

    @Test func closesWhenThePromptIsAnsweredOrCannotBeShown() {
        #expect(action(isSecure: false, isWindowShown: true) == .close)
        #expect(action(isSecure: false) == .none)
        #expect(action(canShowDisplay: false, isWindowShown: true) == .close)
        #expect(action(canShowDisplay: false) == .none)
        // The desktop view already shows the display.
        #expect(action(showsApps: false) == .none)
        #expect(action(showsApps: false, isWindowShown: true) == .close)
    }

    @Test func sizesTheWindowToTheDisplayShapeWithinTheScreen() {
        let wide = SecureDesktopPresentation.contentSize(
            display: GuestPixelRect(x: 0, y: 0, width: 3456, height: 2234),
            visibleWidth: 1728,
            visibleHeight: 1050
        )
        #expect(wide.height <= 1050 * 0.62 + 1)
        #expect(abs(wide.width / wide.height - 3456.0 / 2234.0) < 0.01)

        // No display size yet.
        let unknown = SecureDesktopPresentation.contentSize(
            display: GuestPixelRect(x: 0, y: 0, width: 0, height: 0),
            visibleWidth: 1440,
            visibleHeight: 900
        )
        #expect(unknown.width >= 640)
        #expect(abs(unknown.width / unknown.height - 1.6) < 0.01)
    }
}
