import AppKit
import Testing

@testable import VeilHostShell

@Suite("Windows app Dock icon")
@MainActor
struct WindowsAppDockIconTests {
    @Test("keeps Veil's icon when Windows sent no app icon")
    func keepsVeilIconWithoutAppIcon() {
        let identity = WindowsAppWindowIdentity(appId: "winapp_unknown", appName: "Unknown", iconData: nil)

        #expect(WindowsAppDockIcon.image(for: identity) == nil)
    }

    @Test("badges the Windows app icon with Veil at Dock resolution")
    func badgesAppIconWithVeil() throws {
        let appIcon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(appIcon.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let identity = WindowsAppWindowIdentity(appId: "winapp_dock_icon_test", appName: "Paint", iconData: png)

        let image = try #require(WindowsAppDockIcon.image(for: identity))

        #expect(image.size == WindowsAppDockIcon.canvasSize)
        #expect(image.accessibilityDescription == "Paint")
        #expect(WindowsAppDockIcon.image(for: identity) === image)
    }
}
