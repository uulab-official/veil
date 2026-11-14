import Testing

@testable import VeilHostShell

@Suite("Mac integration settings")
struct MacIntegrationFeatureTests {
    @Test("lists what works once Windows is installed, with nothing marked as planned")
    func installedWindows() {
        let features = MacIntegrationFeature.features(windowsInstalled: true)

        #expect(features.map(\.id) == ["apps", "clipboard", "folders"])
        #expect(features.allSatisfy { $0.state == .ready })
        #expect(features.map(\.detail) == [
            "Each Windows app opens in its own Mac window.",
            "Copy on one side and paste on the other.",
            "Windows shows the Mac folder you share as a drive."
        ])
    }

    @Test("says the features wait for Windows before it is installed")
    func beforeInstallation() {
        let features = MacIntegrationFeature.features(windowsInstalled: false)

        #expect(features.count == 3)
        #expect(features.allSatisfy { $0.state == .blocked })
        #expect(features.allSatisfy { $0.detail == "Available after Windows is installed." })
    }
}
