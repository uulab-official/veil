import AppKit
import Testing
import VeilHostCore
@testable import VeilHostShell

@Suite("Shortcuts bridge")
@MainActor
struct VeilShortcutBridgeTests {
    private final class StubPerformer: VeilShortcutPerforming {
        var shortcutWindowsApps: [WindowsApp] = [
            WindowsApp(id: "winapp_word", name: "Word", exePath: #"C:\Word.exe"#, publisher: "Microsoft", iconId: "icon_word")
        ]
        var shortcutStopNeedsConfirmation = false
        func shortcutStartWindows() async throws -> LocalizedStringResource { "started" }
        func shortcutStopWindows() async throws -> LocalizedStringResource { "stopped" }
        func shortcutSuspendWindows() async throws -> LocalizedStringResource { "suspended" }
        func shortcutResumeWindows() async throws -> LocalizedStringResource { "resumed" }
        func shortcutOpenWindowsApp(id: String) async throws -> LocalizedStringResource { "opened" }
    }

    @Test("offers the inbox apps before the app has registered")
    func offersCatalogBeforeRegistration() async throws {
        let bridge = VeilShortcutBridge()

        #expect(bridge.windowsApps.map(\.id) == KnownWindowsAppCatalog.apps.map(\.id))
        await #expect(throws: VeilShortcutError.self) {
            _ = try await bridge.waitForPerformer(timeout: .milliseconds(50))
        }
    }

    @Test("hands requests to the registered app and lists its live apps")
    func usesRegisteredPerformer() async throws {
        let bridge = VeilShortcutBridge()
        bridge.performer = StubPerformer()

        let performer = try await bridge.waitForPerformer(timeout: .milliseconds(50))
        #expect(String(localized: try await performer.shortcutStartWindows()) == "started")
        #expect(bridge.windowsApps.map(\.name) == ["Word"])
    }

    @Test("every intent has an App Shortcut so Shortcuts and Spotlight list it")
    func everyIntentHasAShortcut() {
        #expect(VeilAppShortcuts.appShortcuts.count == 5)
    }
}

@Suite("Paste content selection")
@MainActor
struct HostPasteboardContentTests {
    private func pasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("veil-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private static let png = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII="
    )!

    @Test("a Finder copy pastes the files, not their names as text")
    func prefersFilesListedFirst() throws {
        let pasteboard = pasteboard()
        let url = URL(filePath: "/tmp/report.pdf")
        pasteboard.writeObjects([url as NSURL, "report.pdf" as NSString])

        #expect(HostPasteboardContent.read(from: pasteboard, includeFiles: true) == .files([url]))
    }

    @Test("with file paste off, a Finder copy falls back to its text")
    func fallsBackToTextWithoutFilePaste() {
        let pasteboard = pasteboard()
        pasteboard.writeObjects([URL(filePath: "/tmp/report.pdf") as NSURL])
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString("report.pdf", forType: .string)

        #expect(HostPasteboardContent.read(from: pasteboard, includeFiles: false) == .text("report.pdf"))
    }

    @Test("an image listed before text pastes as the image")
    func prefersImageListedFirst() {
        let pasteboard = pasteboard()
        pasteboard.declareTypes([.png, .string], owner: nil)
        pasteboard.setData(Self.png, forType: .png)
        pasteboard.setString("https://example.com/picture.png", forType: .string)

        #expect(HostPasteboardContent.read(from: pasteboard, includeFiles: true) == .image(png: Self.png))
    }

    @Test("a TIFF-only image is converted to PNG")
    func convertsTIFF() throws {
        let pasteboard = pasteboard()
        let tiff = try #require(NSBitmapImageRep(data: Self.png)?.tiffRepresentation)
        pasteboard.declareTypes([.tiff], owner: nil)
        pasteboard.setData(tiff, forType: .tiff)

        guard case .image(let png) = HostPasteboardContent.read(from: pasteboard, includeFiles: true) else {
            Issue.record("Expected a TIFF to become an image paste.")
            return
        }
        let payload = try ClipboardImagePayload(png: png)
        #expect(payload.width == 2 && payload.height == 2)
    }

    @Test("a guest image is written as PNG and TIFF for apps that read only one")
    func writesBothImageTypes() throws {
        let pasteboard = pasteboard()

        HostPasteboardContent.writeImage(try ClipboardImagePayload(png: Self.png), to: pasteboard)

        #expect(pasteboard.data(forType: .png) == Self.png)
        #expect(pasteboard.data(forType: .tiff) != nil)
    }
}
