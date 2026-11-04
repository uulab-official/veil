import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

struct WindowsAppWindowIdentityTests {
    @Test("resolves a mirrored window icon from the current app catalog")
    func resolvesIconDataFromAppCatalog() throws {
        let iconData = try #require(Data(base64Encoded: "aWNvbg=="))
        let app = WindowsApp(
            id: "winapp_notepad",
            name: "Notepad",
            exePath: "C:\\Windows\\System32\\notepad.exe",
            publisher: "Microsoft",
            iconId: "notepad",
            iconPngBase64: iconData.base64EncodedString()
        )

        let identity = WindowsAppWindowIdentity.resolve(
            appId: "winapp_notepad",
            apps: [app]
        )

        #expect(identity.appId == "winapp_notepad")
        #expect(identity.appName == "Notepad")
        #expect(identity.iconData == iconData)
    }

    @Test("keeps mirrored window identity safe when the icon is missing or malformed")
    func fallsBackWithoutIconData() {
        let app = WindowsApp(
            id: "winapp_calculator",
            name: "Calculator",
            exePath: "C:\\Windows\\System32\\calc.exe",
            publisher: "Microsoft",
            iconId: "calculator",
            iconPngBase64: "not-base64"
        )

        let identity = WindowsAppWindowIdentity.resolve(
            appId: "winapp_calculator",
            apps: [app]
        )

        #expect(identity.appName == "Calculator")
        #expect(identity.iconData == nil)
    }

    @Test("uses the app id as a stable fallback for an unknown window")
    func fallsBackToAppId() {
        let identity = WindowsAppWindowIdentity.resolve(
            appId: "winapp_unknown",
            apps: []
        )

        #expect(identity.appId == "winapp_unknown")
        #expect(identity.appName == "Windows App")
        #expect(identity.iconData == nil)
    }
}
