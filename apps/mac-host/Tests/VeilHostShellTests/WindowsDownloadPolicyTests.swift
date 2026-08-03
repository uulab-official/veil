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

    @Test("selects Korean automatically for a Korean Mac")
    func selectsKoreanLanguage() {
        #expect(
            WindowsDownloadLanguagePolicy.preferredMicrosoftLanguageNames(
                preferredLanguages: ["ko-KR"]
            ) == ["Korean", "English"]
        )
    }

    @Test("uses international English for a British English Mac")
    func selectsInternationalEnglish() {
        #expect(
            WindowsDownloadLanguagePolicy.preferredMicrosoftLanguageNames(
                preferredLanguages: ["en-GB"]
            ) == ["English International", "English"]
        )
    }

    @Test("distinguishes simplified and traditional Chinese")
    func selectsChineseScript() {
        #expect(
            WindowsDownloadLanguagePolicy.preferredMicrosoftLanguageNames(
                preferredLanguages: ["zh-Hans"]
            ).first == "Chinese Simplified"
        )
        #expect(
            WindowsDownloadLanguagePolicy.preferredMicrosoftLanguageNames(
                preferredLanguages: ["zh-Hant"]
            ).first == "Chinese Traditional"
        )
    }

    @Test("falls back to English for an unavailable Windows language")
    func fallsBackToEnglish() {
        #expect(
            WindowsDownloadLanguagePolicy.preferredMicrosoftLanguageNames(
                preferredLanguages: ["vi-VN"]
            ) == ["English"]
        )
    }

    @Test("automation uses Microsoft page controls without calling the private connector")
    func automationUsesPublicPageControls() {
        let script = WindowsDownloadPageAutomation.script(preferredLanguageNames: ["Korean", "English"])

        #expect(script.contains("product-edition"))
        #expect(script.contains("product-languages"))
        #expect(script.contains("submit-product-edition"))
        #expect(script.contains("submit-sku"))
        #expect(script.contains("Korean"))
        #expect(!script.contains("software-download-connector"))
    }
}
