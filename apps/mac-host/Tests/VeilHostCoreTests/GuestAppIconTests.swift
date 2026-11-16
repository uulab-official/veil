import Foundation
import Testing
@testable import VeilHostCore

struct GuestAppIconTests {
    /// The start of a PNG: signature, then an IHDR chunk declaring this size. Enough for the check, which
    /// reads the header and never decodes pixels.
    private func pngHeader(width: UInt32, height: UInt32, padding: Int = 0) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]
        bytes += Array("IHDR".utf8)
        for value in [width, height] {
            bytes += [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }
        bytes += [UInt8](repeating: 0, count: padding)
        return Data(bytes)
    }

    @Test func keepsASmallPNG() {
        let icon = pngHeader(width: 128, height: 128).base64EncodedString()
        #expect(GuestAppIcon.validatedPNGBase64(icon) == icon)
        let largest = pngHeader(width: 1_024, height: 1_024).base64EncodedString()
        #expect(GuestAppIcon.validatedPNGBase64(largest) == largest)
    }

    @Test func dropsAnIconThatWouldDecodeToGigabytes() {
        #expect(GuestAppIcon.validatedPNGBase64(pngHeader(width: 30_000, height: 30_000).base64EncodedString()) == nil)
        #expect(GuestAppIcon.validatedPNGBase64(pngHeader(width: 1_025, height: 16).base64EncodedString()) == nil)
        #expect(GuestAppIcon.validatedPNGBase64(pngHeader(width: 0, height: 16).base64EncodedString()) == nil)
    }

    @Test func dropsBytesThatAreNotAPNG() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0, count: 64)).base64EncodedString()
        #expect(GuestAppIcon.validatedPNGBase64(jpeg) == nil)
        #expect(GuestAppIcon.validatedPNGBase64("not-base64") == nil)
        #expect(GuestAppIcon.validatedPNGBase64("") == nil)
        #expect(GuestAppIcon.validatedPNGBase64(nil) == nil)
    }

    @Test func dropsAnIconOverTheSizeLimit() {
        let large = pngHeader(width: 64, height: 64, padding: GuestAppIcon.maximumByteCount).base64EncodedString()
        #expect(GuestAppIcon.validatedPNGBase64(large) == nil)
    }

    @Test func anAppFromTheGuestLosesOnlyItsBadIcon() throws {
        let bad = pngHeader(width: 30_000, height: 30_000).base64EncodedString()
        let json = Data("""
        {"id":"app_setup","name":"Setup","exePath":"C:\\\\setup.exe","publisher":"Contoso","iconId":"icon_setup",
         "iconPngBase64":"\(bad)","folder":"Tools","running":true}
        """.utf8)

        let app = try JSONDecoder().decode(WindowsApp.self, from: json)

        #expect(app.iconPngBase64 == nil)
        #expect(app.name == "Setup")
        #expect(app.folder == "Tools")
        #expect(app.running == true)
    }

    @Test func anAppWithoutOptionalFieldsStillDecodes() throws {
        let json = Data(#"{"id":"app_notepad","name":"Notepad","exePath":"notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}"#.utf8)

        let app = try JSONDecoder().decode(WindowsApp.self, from: json)

        #expect(app.iconPngBase64 == nil)
        #expect(app.folder == nil)
        #expect(app.isStartMenuEntry)
    }
}
