import Foundation
import Testing
@testable import VeilHostShell

struct WindowsDownloadPolicyTests {
    @Test("license consent points to Microsoft's official terms over HTTPS")
    func licenseConsentUsesOfficialTerms() {
        #expect(WindowsLicenseConsentPolicy.termsURL.scheme == "https")
        #expect(WindowsLicenseConsentPolicy.termsURL.host == "www.microsoft.com")
        #expect(WindowsLicenseConsentPolicy.termsURL.path == "/useterms")
    }

    @Test("license consent describes unattended acceptance explicitly")
    func licenseConsentIsExplicit() {
        #expect(WindowsLicenseConsentPolicy.message.contains("unattended setup"))
        #expect(WindowsLicenseConsentPolicy.message.contains("records acceptance"))
        #expect(WindowsLicenseConsentPolicy.acceptButtonTitle.contains("I Agree"))
        #expect(WindowsLicenseConsentPolicy.reviewButtonTitle.contains("License Terms"))
    }

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
        #expect(script.contains("SHA-256"))
        #expect(script.contains("querySelectorAll('tr')"))
        #expect(script.contains("sha256"))
        #expect(script.contains("Korean"))
        #expect(!script.contains("software-download-connector"))
    }

    @Test("normalizes a Microsoft SHA-256 value")
    func normalizesSHA256() {
        let digest = "723fdcb737b39a5ec1f4b0eadacf288f1a2c4c4c8c845eb1f6a433cc264bd426"

        #expect(WindowsISOHashPolicy.normalizedSHA256("  \(digest)\n") == digest.uppercased())
    }

    @Test("rejects missing and malformed SHA-256 values", arguments: [nil, "1234", String(repeating: "Z", count: 64)])
    func rejectsInvalidSHA256(digest: String?) {
        #expect(WindowsISOHashPolicy.normalizedSHA256(digest) == nil)
    }

    @Test("detects an ISO hash mismatch")
    func detectsHashMismatch() {
        let expected = String(repeating: "A", count: 64)
        let actual = String(repeating: "B", count: 64)

        #expect(WindowsISOHashPolicy.failureReason(expected: expected, actual: actual)?.contains("damaged") == true)
    }

    @Test("streams SHA-256 calculation without loading the whole file")
    func calculatesSHA256() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-windows-hash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.iso")
        try Data("abc".utf8).write(to: file)

        let digest = try await WindowsISOIntegrityVerifier.sha256(for: file)

        #expect(digest == "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
    }

    @Test("rejects HTTP errors before creating a destination")
    func rejectsHTTPError() {
        let failure = WindowsDownloadResponsePolicy.failureReason(
            statusCode: 503,
            expectedContentLength: 7_000_000_000,
            availableCapacity: 20_000_000_000
        )

        #expect(failure?.contains("HTTP 503") == true)
    }

    @Test("rejects implausibly short download responses")
    func rejectsShortResponse() {
        let failure = WindowsDownloadResponsePolicy.failureReason(
            statusCode: 200,
            expectedContentLength: WindowsISOFileValidator.minimumPlausibleSize - 1,
            availableCapacity: 20_000_000_000
        )

        #expect(failure?.contains("incomplete") == true)
    }

    @Test("requires download size plus a storage reserve")
    func rejectsLowStorage() {
        let failure = WindowsDownloadResponsePolicy.failureReason(
            statusCode: 200,
            expectedContentLength: 7_000_000_000,
            availableCapacity: 8_999_999_999
        )

        #expect(failure?.contains("Not enough free storage") == true)
    }

    @Test("accepts a valid response when storage is sufficient")
    func acceptsValidResponse() {
        #expect(
            WindowsDownloadResponsePolicy.failureReason(
                statusCode: 200,
                expectedContentLength: 7_000_000_000,
                availableCapacity: 9_000_000_000
            ) == nil
        )
    }

    @Test("does not invent a storage failure when macOS omits capacity")
    func acceptsUnknownStorageCapacity() {
        #expect(
            WindowsDownloadResponsePolicy.failureReason(
                statusCode: 200,
                expectedContentLength: 7_000_000_000,
                availableCapacity: nil
            ) == nil
        )
    }
}
