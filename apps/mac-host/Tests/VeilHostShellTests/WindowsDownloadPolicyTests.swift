import Foundation
import Testing
@testable import VeilHostShell

struct WindowsDownloadPolicyTests {
    @Test("allows the official Microsoft Windows Arm download page")
    func allowsOfficialLandingPage() {
        #expect(WindowsDownloadURLPolicy.allowsNavigation(to: WindowsDownloadURLPolicy.landingPageURL))
    }

    @Test("allows Microsoft ISO responses from official subdomains")
    func allowsOfficialMicrosoftISO() {
        let url = URL(string: "https://software.download.prss.microsoft.com/dbazure/Win11_Arm64.iso")!

        #expect(WindowsDownloadURLPolicy.allowsISOResponse(url: url, suggestedFilename: "Win11_Arm64.iso"))
    }

    @Test("rejects insecure, lookalike, and non-ISO downloads", arguments: [
        ("http://software.download.prss.microsoft.com/Win11.iso", "Win11.iso"),
        ("https://microsoft.com.example.invalid/Win11.iso", "Win11.iso"),
        ("https://downloads.example.invalid/Win11.iso", "Win11.iso"),
        ("https://www.microsoft.com/download/readme.html", "readme.html")
    ])
    func rejectsUntrustedDownloads(urlString: String, filename: String) {
        let url = URL(string: urlString)!

        #expect(!WindowsDownloadURLPolicy.allowsISOResponse(url: url, suggestedFilename: filename))
    }

    @Test("does not trust an ISO filename when the host is untrusted")
    func filenameCannotOverrideHostPolicy() {
        let url = URL(string: "https://example.invalid/download")!

        #expect(!WindowsDownloadURLPolicy.allowsISOResponse(url: url, suggestedFilename: "Windows.iso"))
    }

    @Test("sanitizes a server-provided filename and keeps the ISO extension")
    func sanitizesSuggestedFilename() {
        let filename = WindowsDownloadDestination.sanitizedISOFilename("../../Win11:Arm64.exe")

        #expect(filename == "Win11-Arm64.iso")
        #expect(!filename.contains("/"))
    }

    @Test("uses a safe fallback for an empty server-provided filename")
    func usesSafeFilenameFallback() {
        #expect(WindowsDownloadDestination.sanitizedISOFilename("...") == "Windows-11-Arm64.iso")
    }

    @Test("rejects partial ISO downloads before VM preparation")
    func rejectsPartialISO() {
        let failure = WindowsISOFileValidator.failureReason(
            filename: "Windows11.iso",
            fileSize: WindowsISOFileValidator.minimumPlausibleSize - 1
        )

        #expect(failure?.contains("incomplete") == true)
    }

    @Test("accepts a plausibly complete ISO download")
    func acceptsPlausibleISO() {
        let failure = WindowsISOFileValidator.failureReason(
            filename: "Windows11.iso",
            fileSize: WindowsISOFileValidator.minimumPlausibleSize
        )

        #expect(failure == nil)
    }
}
