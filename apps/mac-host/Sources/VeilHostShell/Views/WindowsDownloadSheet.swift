import AppKit
import Combine
import CryptoKit
import SwiftUI
import WebKit

enum WindowsDownloadURLPolicy {
    static let landingPageURL = URL(
        string: "https://www.microsoft.com/en-us/software-download/windows11arm64"
    )!

    static func allowsNavigation(to url: URL) -> Bool {
        if url.scheme?.lowercased() == "about" {
            return true
        }

        return isOfficialMicrosoftHTTPSURL(url)
    }

    static func allowsISOResponse(url: URL?, suggestedFilename: String?) -> Bool {
        guard let url, isOfficialMicrosoftHTTPSURL(url) else {
            return false
        }

        return url.pathExtension.lowercased() == "iso"
            || suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension.lowercased() == "iso" } == true
    }

    static func isOfficialMicrosoftHTTPSURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "microsoft.com" || host.hasSuffix(".microsoft.com")
    }
}

enum WindowsLicenseConsentPolicy {
    static let termsURL = URL(string: "https://www.microsoft.com/useterms")!
    static let title = "Accept Microsoft License Terms?"
    static let message = "Veil's unattended setup hides the Windows Setup license page and records acceptance. Review Microsoft's terms before continuing. A valid Windows license and activation may be required."
    static let reviewButtonTitle = "Review License Terms"
    static let acceptButtonTitle = "I Agree and Install Windows"
}

enum WindowsDownloadDestination {
    static func downloadsDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directory = applicationSupport
            .appendingPathComponent("Veil", isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func availableISOURL(
        suggestedFilename: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let filename = sanitizedISOFilename(suggestedFilename)
        let firstCandidate = directory.appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: firstCandidate.path) else {
            return firstCandidate
        }

        let stem = firstCandidate.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent(
            "\(stem)-\(UUID().uuidString.lowercased()).iso",
            isDirectory: false
        )
    }

    static func sanitizedISOFilename(_ suggestedFilename: String) -> String {
        let lastComponent = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        let stem = URL(fileURLWithPath: lastComponent).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        let cleanedScalars = stem.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let cleaned = String(cleanedScalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_"))
        return "\(cleaned.isEmpty ? "Windows-11-Arm64" : cleaned).iso"
    }
}

enum WindowsISOFileValidator {
    static let minimumPlausibleSize: Int64 = 1_000_000_000

    static func failureReason(filename: String, fileSize: Int64) -> String? {
        guard URL(fileURLWithPath: filename).pathExtension.lowercased() == "iso" else {
            return "Microsoft did not return an ISO file. Reload the official download page and try again."
        }

        guard fileSize >= minimumPlausibleSize else {
            return "The Windows ISO download is incomplete. Veil removed the partial file; try the download again."
        }

        return nil
    }
}

enum WindowsDownloadResponsePolicy {
    static let minimumFallbackCapacity: Int64 = 10_000_000_000
    static let reservedCapacity: Int64 = 2_000_000_000

    static func failureReason(
        statusCode: Int?,
        expectedContentLength: Int64,
        availableCapacity: Int64?
    ) -> String? {
        if let statusCode, !(200...299).contains(statusCode) {
            return "Microsoft's Windows download returned HTTP \(statusCode). Reload the official page and try again."
        }

        if expectedContentLength > 0,
           expectedContentLength < WindowsISOFileValidator.minimumPlausibleSize {
            return "Microsoft returned an incomplete Windows ISO response. Reload the official page and try again."
        }

        guard let availableCapacity else {
            return nil
        }

        let requiredCapacity: Int64
        if expectedContentLength > 0 {
            let (capacity, overflow) = expectedContentLength.addingReportingOverflow(reservedCapacity)
            requiredCapacity = overflow ? Int64.max : capacity
        } else {
            requiredCapacity = minimumFallbackCapacity
        }

        guard availableCapacity >= requiredCapacity else {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "Not enough free storage for Windows. Veil needs \(formatter.string(fromByteCount: requiredCapacity)) but only \(formatter.string(fromByteCount: availableCapacity)) is available."
        }

        return nil
    }
}

enum WindowsISOHashPolicy {
    static func normalizedSHA256(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value
            .filter { !$0.isWhitespace }
            .uppercased()
        guard normalized.count == 64,
              normalized.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "0123456789ABCDEF").contains($0)
              }) else {
            return nil
        }
        return normalized
    }

    static func failureReason(expected: String?, actual: String) -> String? {
        guard let expected = normalizedSHA256(expected) else {
            return "Microsoft did not publish a valid SHA-256 for this ISO. Veil did not keep the unverified download."
        }

        guard normalizedSHA256(actual) == expected else {
            return "The Windows ISO failed Microsoft's SHA-256 integrity check. Veil removed the damaged download; try again."
        }

        return nil
    }
}

enum WindowsISOIntegrityVerifier {
    static func sha256(for url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var hasher = SHA256()
            while let data = try handle.read(upToCount: 4 * 1_024 * 1_024), !data.isEmpty {
                try Task.checkCancellation()
                hasher.update(data: data)
            }
            try Task.checkCancellation()

            return hasher.finalize()
                .map { String(format: "%02X", $0) }
                .joined()
        }.value
    }
}

enum WindowsDownloadLanguagePolicy {
    static func preferredMicrosoftLanguageNames(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [String] {
        let identifier = preferredLanguages.first ?? "en"
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let languageCode = normalized.split(separator: "-").first.map(String.init) ?? "en"

        let preferred: String
        switch languageCode {
        case "ar": preferred = "Arabic"
        case "bg": preferred = "Bulgarian"
        case "zh": preferred = normalized.contains("hant") || normalized.contains("tw") || normalized.contains("hk")
            ? "Chinese Traditional"
            : "Chinese Simplified"
        case "hr": preferred = "Croatian"
        case "cs": preferred = "Czech"
        case "da": preferred = "Danish"
        case "nl": preferred = "Dutch"
        case "et": preferred = "Estonian"
        case "fi": preferred = "Finnish"
        case "fr": preferred = normalized.contains("ca") ? "French Canadian" : "French"
        case "de": preferred = "German"
        case "el": preferred = "Greek"
        case "he": preferred = "Hebrew"
        case "hu": preferred = "Hungarian"
        case "it": preferred = "Italian"
        case "ja": preferred = "Japanese"
        case "ko": preferred = "Korean"
        case "lv": preferred = "Latvian"
        case "lt": preferred = "Lithuanian"
        case "nb", "nn", "no": preferred = "Norwegian"
        case "pl": preferred = "Polish"
        case "pt": preferred = normalized.contains("br") ? "Brazilian Portuguese" : "Portuguese"
        case "ro": preferred = "Romanian"
        case "ru": preferred = "Russian"
        case "sr": preferred = "Serbian Latin"
        case "sk": preferred = "Slovak"
        case "sl": preferred = "Slovenian"
        case "es": preferred = normalized.contains("mx") ? "Spanish (Mexico)" : "Spanish"
        case "sv": preferred = "Swedish"
        case "th": preferred = "Thai"
        case "tr": preferred = "Turkish"
        case "uk": preferred = "Ukrainian"
        case "en": preferred = normalized.contains("gb") || normalized.contains("au") || normalized.contains("nz")
            ? "English International"
            : "English"
        default: preferred = "English"
        }

        return preferred == "English" ? [preferred] : [preferred, "English"]
    }
}

enum WindowsDownloadPageAutomation {
    static func script(preferredLanguageNames: [String]) -> String {
        let encodedLanguages = (try? JSONEncoder().encode(preferredLanguageNames)) ?? Data("[\"English\"]".utf8)
        let languagesJSON = String(decoding: encodedLanguages, as: UTF8.self)

        return """
        (() => {
          const preferredLanguages = \(languagesJSON);
          const normalize = value => (value || '').replace(/\\s+/g, ' ').trim().toLowerCase();
          const visible = element => !!element && (element.offsetWidth > 0 || element.offsetHeight > 0 || element.getClientRects().length > 0);
          const response = (stage, detail = '', url = '', sha256 = '') => JSON.stringify({ stage, detail, url, sha256 });

          const isoLink = Array.from(document.querySelectorAll('a[href]')).find(anchor => {
            try {
              const url = new URL(anchor.href, document.baseURI);
              const officialHost = url.hostname === 'microsoft.com' || url.hostname.endsWith('.microsoft.com');
              return officialHost && /\\.iso(?:$|[?#])/i.test(url.href);
            } catch (_) {
              return false;
            }
          });
          if (isoLink) {
            const languageSelect = document.getElementById('product-languages');
            const selectedLanguage = languageSelect?.options[languageSelect.selectedIndex]?.textContent
              || preferredLanguages[0]
              || 'English';
            const expectedHashLabel = normalize(`${selectedLanguage} 64-bit`);
            const hashRow = Array.from(document.querySelectorAll('tr')).find(row => {
              const cells = Array.from(row.querySelectorAll('th, td'))
                .map(cell => (cell.textContent || '').replace(/\\s+/g, ' ').trim());
              return cells.length >= 2
                && normalize(cells[0]) === expectedHashLabel
                && /^[a-f0-9]{64}$/i.test(cells[1].replace(/\\s+/g, ''));
            });
            const publishedHash = hashRow
              ? Array.from(hashRow.querySelectorAll('th, td'))[1].textContent.replace(/\\s+/g, '').trim()
              : '';
            if (!publishedHash) {
              return response('waiting-hash', `Waiting for Microsoft's ${selectedLanguage} SHA-256`);
            }
            return response('download-ready', selectedLanguage.trim(), isoLink.href, publishedHash);
          }

          const visibleError = Array.from(document.querySelectorAll('.modal, [role="dialog"]'))
            .find(element => visible(element) && /encountered a problem|unable to complete/i.test(element.textContent || ''));
          if (visibleError) {
            return response('error', (visibleError.textContent || '').replace(/\\s+/g, ' ').trim());
          }

          const languageSelect = document.getElementById('product-languages');
          if (languageSelect && languageSelect.options.length > 1) {
            if (!languageSelect.dataset.veilSubmitted) {
              const options = Array.from(languageSelect.options).filter(option => option.value && option.value !== 'null');
              let selectedOption;
              for (const preferred of preferredLanguages) {
                selectedOption = options.find(option => normalize(option.textContent) === normalize(preferred));
                if (selectedOption) break;
              }
              selectedOption = selectedOption
                || options.find(option => normalize(option.textContent) === 'english')
                || options[0];
              if (!selectedOption) return response('waiting', 'Waiting for Microsoft language options');

              languageSelect.value = selectedOption.value;
              languageSelect.dispatchEvent(new Event('change', { bubbles: true }));
              languageSelect.dataset.veilSubmitted = 'true';
              document.getElementById('submit-sku')?.click();
              return response('language-submitted', (selectedOption.textContent || '').trim());
            }
            return response('waiting-download', languageSelect.options[languageSelect.selectedIndex]?.textContent || 'Windows language');
          }

          const editionSelect = document.getElementById('product-edition');
          if (editionSelect && editionSelect.options.length > 1) {
            if (!editionSelect.dataset.veilSubmitted) {
              const options = Array.from(editionSelect.options).filter(option => option.value && option.value !== 'null');
              const armOption = options.find(option => /arm64/i.test(option.textContent || '')) || options[0];
              if (!armOption) return response('waiting', 'Waiting for the latest Windows edition');

              editionSelect.value = armOption.value;
              editionSelect.dispatchEvent(new Event('change', { bubbles: true }));
              editionSelect.dataset.veilSubmitted = 'true';
              document.getElementById('submit-product-edition')?.click();
              return response('edition-submitted', (armOption.textContent || '').trim());
            }
            return response('waiting-language', 'Waiting for Microsoft language options');
          }

          return response('waiting', 'Waiting for Microsoft download controls');
        })();
        """
    }
}

private struct WindowsDownloadAutomationResponse: Decodable {
    var stage: String
    var detail: String
    var url: String
    var sha256: String
}

enum WindowsDownloadPhase: Equatable {
    case loadingPage
    case automating(step: String)
    case requestingDownload(language: String)
    case downloading(filename: String)
    case verifying(filename: String)
    case downloaded(URL)
    case failed(String)
}

@MainActor
final class WindowsDownloadController: NSObject, ObservableObject {
    @Published private(set) var phase: WindowsDownloadPhase = .loadingPage
    @Published private(set) var downloadProgress: Double?

    private(set) lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }()

    private var activeDownload: WKDownload?
    private var destinationURL: URL?
    private var hasLoadedLandingPage = false
    private var hasRequestedDownload = false
    private var selectedLanguageName: String?
    private var expectedSHA256: String?
    private var automationTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var verificationTask: Task<Void, Never>?

    func loadLandingPage() {
        guard !hasLoadedLandingPage else {
            return
        }

        hasLoadedLandingPage = true
        hasRequestedDownload = false
        selectedLanguageName = nil
        expectedSHA256 = nil
        phase = .loadingPage
        webView.load(URLRequest(url: WindowsDownloadURLPolicy.landingPageURL))
    }

    func reloadLandingPage() {
        cancelDownload()
        destinationURL = nil
        hasRequestedDownload = false
        selectedLanguageName = nil
        expectedSHA256 = nil
        phase = .loadingPage
        webView.load(URLRequest(url: WindowsDownloadURLPolicy.landingPageURL))
    }

    func cancelDownload() {
        automationTask?.cancel()
        automationTask = nil
        progressTask?.cancel()
        progressTask = nil
        verificationTask?.cancel()
        verificationTask = nil
        downloadProgress = nil
        expectedSHA256 = nil
        let partialDestination = destinationURL
        destinationURL = nil

        guard let activeDownload else {
            removeFileIfPresent(at: partialDestination)
            return
        }

        self.activeDownload = nil
        // Unlink immediately so a dismissed sheet never leaves a multi-gigabyte
        // partial ISO behind. WebKit may still hold the file descriptor briefly;
        // the completion pass handles filesystems that delay the first removal.
        removeFileIfPresent(at: partialDestination)
        activeDownload.cancel { [self] _ in
            removeFileIfPresent(at: partialDestination)
        }
    }

    private func beginTracking(_ download: WKDownload) {
        automationTask?.cancel()
        automationTask = nil
        activeDownload = download
        download.delegate = self
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self, weak download] in
            while !Task.isCancelled,
                  let self,
                  let download,
                  self.activeDownload === download {
                let progress = download.progress
                self.downloadProgress = progress.totalUnitCount > 0
                    ? min(max(progress.fractionCompleted, 0), 1)
                    : nil
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func fail(_ message: String, removePartialFile: Bool = true) {
        automationTask?.cancel()
        automationTask = nil
        progressTask?.cancel()
        progressTask = nil
        verificationTask?.cancel()
        verificationTask = nil
        downloadProgress = nil
        activeDownload = nil
        if removePartialFile {
            removePartialDestination()
        }
        phase = .failed(message)
    }

    private func startAutomationIfNeeded() {
        guard automationTask == nil,
              activeDownload == nil,
              !hasRequestedDownload else {
            return
        }

        phase = .automating(step: "Selecting the latest Windows 11 Arm64 release")
        let script = WindowsDownloadPageAutomation.script(
            preferredLanguageNames: WindowsDownloadLanguagePolicy.preferredMicrosoftLanguageNames()
        )
        automationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for _ in 0..<360 {
                guard !Task.isCancelled else {
                    return
                }

                do {
                    let rawResult = try await webView.evaluateJavaScript(script)
                    guard let resultString = rawResult as? String,
                          let resultData = resultString.data(using: .utf8),
                          let result = try? JSONDecoder().decode(
                            WindowsDownloadAutomationResponse.self,
                            from: resultData
                          ) else {
                        throw CocoaError(.coderReadCorrupt)
                    }

                    if handleAutomationResult(result) {
                        automationTask = nil
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    fail("Veil could not automate Microsoft's download page: \(error.localizedDescription). Show the Microsoft page to continue manually.", removePartialFile: false)
                    return
                }

                try? await Task.sleep(for: .milliseconds(500))
            }

            guard !Task.isCancelled else {
                return
            }
            fail("Microsoft did not issue a Windows ISO link within three minutes. Reload or show the Microsoft page to continue manually.", removePartialFile: false)
        }
    }

    private func handleAutomationResult(_ result: WindowsDownloadAutomationResponse) -> Bool {
        switch result.stage {
        case "edition-submitted":
            phase = .automating(step: "Requesting Microsoft's current Arm64 release")
        case "language-submitted":
            selectedLanguageName = result.detail
            phase = .automating(step: "Requesting the \(result.detail) ISO")
        case "waiting-language":
            phase = .automating(step: "Loading available Windows languages")
        case "waiting-download":
            selectedLanguageName = result.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .automating(step: "Waiting for Microsoft to issue the ISO link")
        case "waiting":
            phase = .automating(step: result.detail)
        case "waiting-hash":
            phase = .automating(step: result.detail)
        case "download-ready":
            guard let url = URL(string: result.url),
                  WindowsDownloadURLPolicy.allowsISOResponse(url: url, suggestedFilename: nil) else {
                fail("Microsoft returned a download link that did not pass Veil's official ISO policy.", removePartialFile: false)
                return true
            }

            guard let publishedSHA256 = WindowsISOHashPolicy.normalizedSHA256(result.sha256) else {
                fail("Microsoft did not expose a valid SHA-256 for this ISO. Show the Microsoft page or reload to try again.", removePartialFile: false)
                return true
            }

            hasRequestedDownload = true
            selectedLanguageName = result.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            expectedSHA256 = publishedSHA256
            phase = .requestingDownload(language: selectedLanguageName ?? "Windows 11 Arm64")
            webView.load(URLRequest(url: url))
            return true
        case "error":
            fail("Microsoft could not issue the Windows download: \(result.detail)", removePartialFile: false)
            return true
        default:
            phase = .automating(step: "Waiting for Microsoft's latest Windows download")
        }

        return false
    }

    private func removePartialDestination() {
        let destinationURL = destinationURL
        self.destinationURL = nil
        removeFileIfPresent(at: destinationURL)
    }

    private func removeFileIfPresent(at url: URL?) {
        guard let url else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }
}

extension WindowsDownloadController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if WindowsDownloadURLPolicy.allowsISOResponse(url: url, suggestedFilename: nil) {
            decisionHandler(.download)
            return
        }

        decisionHandler(WindowsDownloadURLPolicy.allowsNavigation(to: url) ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response
        if WindowsDownloadURLPolicy.allowsISOResponse(
            url: response.url,
            suggestedFilename: response.suggestedFilename
        ) {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        switch phase {
        case .loadingPage, .automating:
            startAutomationIfNeeded()
        case .requestingDownload, .downloading, .verifying, .downloaded, .failed:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        fail("Microsoft's download page could not be opened. Check your connection and try again: \(error.localizedDescription)", removePartialFile: false)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        beginTracking(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        beginTracking(download)
    }
}

extension WindowsDownloadController: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard activeDownload === download else {
            return nil
        }

        guard WindowsDownloadURLPolicy.allowsISOResponse(
            url: response.url,
            suggestedFilename: suggestedFilename
        ) else {
            fail("Veil blocked a download that did not come from an official Microsoft HTTPS address.")
            return nil
        }

        do {
            let directory = try WindowsDownloadDestination.downloadsDirectory()
            let availableCapacity = try? directory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
            if let failure = WindowsDownloadResponsePolicy.failureReason(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                expectedContentLength: response.expectedContentLength,
                availableCapacity: availableCapacity
            ) {
                fail(failure)
                return nil
            }
            let destination = WindowsDownloadDestination.availableISOURL(
                suggestedFilename: suggestedFilename,
                in: directory
            )
            destinationURL = destination
            phase = .downloading(filename: destination.lastPathComponent)
            return destination
        } catch {
            fail("Veil could not create its Windows download folder: \(error.localizedDescription)")
            return nil
        }
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
    ) {
        guard activeDownload === download else {
            decisionHandler(.cancel)
            return
        }

        guard let url = request.url,
              WindowsDownloadURLPolicy.isOfficialMicrosoftHTTPSURL(url) else {
            fail("Veil blocked a Windows download redirect outside Microsoft's official HTTPS domains.")
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard activeDownload === download else {
            return
        }

        guard let destinationURL else {
            fail("The Windows download finished without a local destination.")
            return
        }

        do {
            let values = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(values.fileSize ?? 0)
            if let failure = WindowsISOFileValidator.failureReason(
                filename: destinationURL.lastPathComponent,
                fileSize: fileSize
            ) {
                fail(failure)
                return
            }

            activeDownload = nil
            progressTask?.cancel()
            progressTask = nil
            downloadProgress = nil
            beginIntegrityVerification(of: destinationURL)
        } catch {
            fail("Veil could not verify the downloaded Windows ISO: \(error.localizedDescription)")
        }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard activeDownload === download else {
            return
        }
        fail("The Windows ISO download failed: \(error.localizedDescription)")
    }

    private func beginIntegrityVerification(of url: URL) {
        let expectedSHA256 = expectedSHA256
        verificationTask?.cancel()
        phase = .verifying(filename: url.lastPathComponent)
        verificationTask = Task { @MainActor [weak self] in
            do {
                let actualSHA256 = try await WindowsISOIntegrityVerifier.sha256(for: url)
                try Task.checkCancellation()

                guard let self, self.destinationURL == url else {
                    return
                }
                if let failure = WindowsISOHashPolicy.failureReason(
                    expected: expectedSHA256,
                    actual: actualSHA256
                ) {
                    self.fail(failure)
                    return
                }

                self.verificationTask = nil
                self.expectedSHA256 = nil
                self.destinationURL = nil
                self.downloadProgress = 1
                self.phase = .downloaded(url)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.destinationURL == url else {
                    return
                }
                self.fail("Veil could not verify the downloaded Windows ISO: \(error.localizedDescription)")
            }
        }
    }
}

private struct MicrosoftWindowsDownloadWebView: NSViewRepresentable {
    @ObservedObject var controller: WindowsDownloadController

    func makeNSView(context: Context) -> WKWebView {
        controller.loadLandingPage()
        return controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct WindowsDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = WindowsDownloadController()
    @State private var isPreparingWindows = false
    @State private var preparationFailure: String?
    @State private var showsMicrosoftPage = false
    @State private var showsLicenseConfirmation = false

    let prepareDownloadedISO: (URL) async -> Bool
    let useExistingISO: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack {
                MicrosoftWindowsDownloadWebView(controller: controller)
                    .opacity(showsMicrosoftPage ? 1 : 0)
                    .allowsHitTesting(showsMicrosoftPage)

                if !showsMicrosoftPage {
                    automaticDownloadStage
                }
            }
            .frame(minWidth: 760, minHeight: 420)

            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            controller.loadLandingPage()
        }
        .alert(WindowsLicenseConsentPolicy.title, isPresented: $showsLicenseConfirmation) {
            Button("Not Now", role: .cancel) {}
            Button(WindowsLicenseConsentPolicy.reviewButtonTitle) {
                reviewLicenseTermsAndReopenConfirmation()
            }
            Button(WindowsLicenseConsentPolicy.acceptButtonTitle) {
                prepareDownloadedWindows()
            }
        } message: {
            Text(WindowsLicenseConsentPolicy.message)
        }
        .onDisappear {
            controller.cancelDownload()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Get Windows 11")
                    .font(.title2.weight(.semibold))
                Text("Download the latest Windows 11 Arm64 ISO directly from Microsoft")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(showsMicrosoftPage ? "Hide Microsoft Page" : "Show Microsoft Page") {
                showsMicrosoftPage.toggle()
            }

            Button("Use Existing ISO") {
                controller.cancelDownload()
                dismiss()
                useExistingISO()
            }

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var automaticDownloadStage: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.blue.gradient)
                    .frame(width: 92, height: 92)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 45, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .blue.opacity(0.28), radius: 24, y: 12)

            VStack(spacing: 7) {
                Text(statusTitle)
                    .font(.title2.weight(.semibold))
                Text(preparationFailure ?? statusDetail)
                    .font(.callout)
                    .foregroundStyle(preparationFailure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            if isPreparingWindows || isBusy {
                if let progress = controller.downloadProgress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 420)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }
            }

            if case .downloaded = controller.phase, !isPreparingWindows {
                VStack(spacing: 10) {
                    Link(destination: WindowsLicenseConsentPolicy.termsURL) {
                        Label(WindowsLicenseConsentPolicy.reviewButtonTitle, systemImage: "doc.text.magnifyingglass")
                    }

                    Button("Review and Prepare Windows") {
                        showsLicenseConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Label("Latest Arm64 ISO directly from microsoft.com", systemImage: "lock.shield.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if showsMicrosoftPage {
                statusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.callout.weight(.semibold))
                    Text(preparationFailure ?? statusDetail)
                        .font(.caption)
                        .foregroundStyle(preparationFailure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        .lineLimit(2)
                }
            } else {
                Label("Automatic download", systemImage: "sparkles")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .failed = controller.phase {
                Button("Reload Microsoft Page") {
                    preparationFailure = nil
                    controller.reloadLandingPage()
                }
            }

            Link("License Terms", destination: WindowsLicenseConsentPolicy.termsURL)

            Label("microsoft.com", systemImage: "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isPreparingWindows || isBusy {
            ProgressView()
                .controlSize(.small)
        } else if preparationFailure != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            switch controller.phase {
            case .downloaded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .automating, .requestingDownload:
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
            case .loadingPage, .downloading, .verifying:
                EmptyView()
            }
        }
    }

    private var isBusy: Bool {
        switch controller.phase {
        case .loadingPage, .automating, .requestingDownload, .downloading, .verifying:
            return true
        case .downloaded, .failed:
            return false
        }
    }

    private var statusTitle: String {
        if isPreparingWindows {
            return "Preparing Windows VM"
        }

        switch controller.phase {
        case .loadingPage:
            return "Finding the latest Windows 11"
        case .automating:
            return "Getting the latest Windows 11"
        case .requestingDownload:
            return "Starting the official ISO download"
        case .downloading(let filename):
            return "Downloading \(filename)"
        case .verifying:
            return "Verifying Windows ISO"
        case .downloaded:
            return "Windows ISO downloaded"
        case .failed:
            return "Download needs attention"
        }
    }

    private var statusDetail: String {
        switch controller.phase {
        case .loadingPage:
            return "Veil is opening Microsoft's official Arm64 download service."
        case .automating(let step):
            return step
        case .requestingDownload(let language):
            return "Microsoft issued the latest \(language) ISO link. Download is starting now."
        case .downloading:
            if let progress = controller.downloadProgress {
                return "\(Int(progress * 100))% complete. The ISO is being saved locally in Veil's Application Support folder."
            }
            return "The ISO is being saved locally in Veil's Application Support folder. Keep this window open."
        case .verifying:
            return "Veil is comparing the completed file with Microsoft's published SHA-256. Keep this window open."
        case .downloaded:
            return "The verified ISO is saved. Review Microsoft's license terms before starting unattended setup."
        case .failed(let message):
            return message
        }
    }

    private func prepareDownloadedWindows() {
        guard case .downloaded(let url) = controller.phase else {
            return
        }

        Task {
            isPreparingWindows = true
            preparationFailure = nil
            let isReady = await prepareDownloadedISO(url)
            isPreparingWindows = false
            if isReady {
                dismiss()
            } else {
                preparationFailure = "The ISO was saved, but Veil could not finish VM preparation. Review Windows Settings and try again."
            }
        }
    }

    private func reviewLicenseTermsAndReopenConfirmation() {
        NSWorkspace.shared.open(WindowsLicenseConsentPolicy.termsURL)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard case .downloaded = controller.phase else {
                return
            }
            showsLicenseConfirmation = true
        }
    }
}
