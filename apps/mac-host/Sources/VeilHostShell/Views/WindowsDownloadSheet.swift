import AppKit
import Combine
import CryptoKit
import SwiftUI
import VeilHostCore
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

/// Bytes received so far and a smoothed transfer rate, for the "3.4 GB of 5.6 GB · About 12
/// minutes left" line under the progress bar.
struct WindowsDownloadTransfer: Equatable {
    var receivedBytes: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double?

    /// Weight of the previous rate when a new sample arrives, so the estimate doesn't jump with
    /// every one-second sample.
    static let rateSmoothing = 0.75

    var sizeText: String {
        "\(Self.byteText(receivedBytes)) of \(Self.byteText(totalBytes))"
    }

    var rateText: String? {
        guard let bytesPerSecond, bytesPerSecond >= 1 else {
            return nil
        }
        return "\(Self.byteText(Int64(bytesPerSecond)))/s"
    }

    var remainingText: String? {
        guard let bytesPerSecond, bytesPerSecond >= 1, totalBytes > receivedBytes else {
            return nil
        }
        return Self.remainingText(seconds: Double(totalBytes - receivedBytes) / bytesPerSecond)
    }

    func advanced(toReceivedBytes received: Int64, totalBytes: Int64, over elapsed: TimeInterval) -> WindowsDownloadTransfer {
        guard elapsed > 0 else {
            return WindowsDownloadTransfer(receivedBytes: received, totalBytes: totalBytes, bytesPerSecond: bytesPerSecond)
        }

        let sampleRate = Double(max(received - receivedBytes, 0)) / elapsed
        let rate = bytesPerSecond.map { $0 * Self.rateSmoothing + sampleRate * (1 - Self.rateSmoothing) } ?? sampleRate
        return WindowsDownloadTransfer(receivedBytes: received, totalBytes: totalBytes, bytesPerSecond: rate)
    }

    static func remainingText(seconds: Double) -> String {
        if seconds < 60 {
            return "Less than a minute left"
        }
        if seconds < 3600 {
            let minutes = Int((seconds / 60).rounded(.up))
            return minutes == 1 ? "About 1 minute left" : "About \(minutes) minutes left"
        }

        let hours = Int(seconds / 3600)
        let minutes = Int((seconds - Double(hours) * 3600) / 60)
        return minutes == 0 ? "About \(hours) hr left" : "About \(hours) hr \(minutes) min left"
    }

    private static func byteText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// The three things that happen after one click, shown as a small tracker on the download page.
enum WindowsDownloadStage: Int, CaseIterable, Identifiable {
    case download
    case verify
    case prepare

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .download: "Download"
        case .verify: "Verify"
        case .prepare: "Prepare and start Setup"
        }
    }

    /// `nil` when the flow stopped on a failure, so the tracker doesn't claim progress.
    static func resolve(phase: WindowsDownloadPhase, isPreparingWindows: Bool) -> WindowsDownloadStage? {
        if isPreparingWindows {
            return .prepare
        }

        switch phase {
        case .loadingPage, .automating, .requestingDownload, .downloading:
            return .download
        case .verifying:
            return .verify
        case .downloaded:
            return .prepare
        case .failed:
            return nil
        }
    }
}

@MainActor
final class WindowsDownloadController: NSObject, ObservableObject {
    @Published private(set) var phase: WindowsDownloadPhase = .loadingPage
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var transfer: WindowsDownloadTransfer?

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
        transfer = nil
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
        transfer = nil
        progressTask = Task { @MainActor [weak self, weak download] in
            let clock = ContinuousClock()
            var lastSample = clock.now
            while !Task.isCancelled,
                  let self,
                  let download,
                  self.activeDownload === download {
                let progress = download.progress
                self.downloadProgress = progress.totalUnitCount > 0
                    ? min(max(progress.fractionCompleted, 0), 1)
                    : nil

                // Bytes and rate move once a second; the bar itself keeps the 250 ms cadence.
                let now = clock.now
                if progress.totalUnitCount > 0 {
                    if let transfer = self.transfer {
                        let elapsed = now - lastSample
                        if elapsed >= .seconds(1) {
                            self.transfer = transfer.advanced(
                                toReceivedBytes: progress.completedUnitCount,
                                totalBytes: progress.totalUnitCount,
                                over: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                            )
                            lastSample = now
                        }
                    } else {
                        self.transfer = WindowsDownloadTransfer(
                            receivedBytes: progress.completedUnitCount,
                            totalBytes: progress.totalUnitCount
                        )
                        lastSample = now
                    }
                }
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
        transfer = nil
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
            transfer = nil
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

/// The automatic Microsoft download, presented either as a sheet or embedded in the
/// Installation Assistant. Both start downloading as soon as they appear and hand the verified ISO
/// to `prepareDownloadedISO`, which prepares the VM and starts Windows Setup.
struct WindowsDownloadSheet: View {
    enum Presentation {
        case sheet
        /// Lives inside the assistant: no dismiss, and `cancelAction` returns to the assistant page.
        case embedded(cancelAction: () -> Void)
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = WindowsDownloadController()
    @State private var isPreparingWindows = false
    @State private var preparationFailure: String?
    @State private var showsMicrosoftPage = false

    let prepareDownloadedISO: (URL) async -> Bool
    let useExistingISO: () -> Void
    var presentation: Presentation = .sheet
    /// Fetches Fedora's VirtIO driver ISO next to the Windows download, so it is usually verified
    /// by the time Setup starts. False when the profile already has driver media the user chose.
    var prefetchesDriverMedia = true

    var body: some View {
        VStack(spacing: 0) {
            if !isEmbedded {
                header
                Divider()
            }

            ZStack {
                MicrosoftWindowsDownloadWebView(controller: controller)
                    .opacity(showsMicrosoftPage ? 1 : 0)
                    .allowsHitTesting(showsMicrosoftPage)

                if !showsMicrosoftPage {
                    automaticDownloadStage
                }
            }
            .frame(minWidth: isEmbedded ? 0 : 760, minHeight: isEmbedded ? 0 : 420)

            Divider()
                .opacity(isEmbedded ? 0.5 : 1)
            footer
        }
        .frame(minWidth: isEmbedded ? 0 : 820, minHeight: isEmbedded ? 0 : 560)
        .background(isEmbedded ? AnyShapeStyle(.white.opacity(0.04)) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor)))
        .task {
            controller.loadLandingPage()
            if prefetchesDriverMedia {
                await VirtioWinDriverMediaProvider.shared.prefetch()
            }
        }
        .onChange(of: controller.phase) { _, phase in
            guard case .downloaded(let url) = phase else {
                return
            }

            Task {
                isPreparingWindows = true
                preparationFailure = nil
                let isReady = await prepareDownloadedISO(url)
                isPreparingWindows = false
                if isReady {
                    finish()
                } else {
                    preparationFailure = "The ISO was saved, but Veil could not finish VM preparation. Review Windows Settings and try again."
                }
            }
        }
        .onDisappear {
            controller.cancelDownload()
        }
    }

    /// Only the standalone sheet needs its own title; embedded, the assistant page names the step.
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var isEmbedded: Bool {
        if case .embedded = presentation {
            return true
        }
        return false
    }

    private func finish() {
        switch presentation {
        case .sheet:
            dismiss()
        case .embedded(let cancelAction):
            cancelAction()
        }
    }

    private var automaticDownloadStage: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.blue.gradient)
                    .frame(width: 84, height: 84)
                Image(systemName: stageSymbolName)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .shadow(color: .blue.opacity(0.28), radius: 24, y: 12)

            VStack(spacing: 6) {
                Text(statusTitle)
                    .font(.title2.weight(.semibold))
                Text(preparationFailure ?? statusDetail)
                    .font(.callout)
                    .foregroundStyle(preparationFailure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: 480)
            }

            progressBlock
                .frame(maxWidth: 440)

            if let stage = WindowsDownloadStage.resolve(phase: controller.phase, isPreparingWindows: isPreparingWindows),
               preparationFailure == nil {
                DownloadStageTracker(current: stage)
            }

            Spacer(minLength: 12)

            Label("Official Arm64 ISO from microsoft.com, checked against Microsoft's SHA-256", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .background(isEmbedded ? Color.clear : Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var progressBlock: some View {
        if case .downloading = controller.phase, let progress = controller.downloadProgress {
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                HStack {
                    Text(transferSummary)
                    Spacer(minLength: 12)
                    Text(controller.transfer?.remainingText ?? "Estimating time left…")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        } else if isPreparingWindows || isBusy {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var transferSummary: String {
        guard let transfer = controller.transfer else {
            return controller.downloadProgress.map { "\(Int($0 * 100))%" } ?? ""
        }
        return [transfer.sizeText, transfer.rateText].compactMap { $0 }.joined(separator: " · ")
    }

    private var stageSymbolName: String {
        if preparationFailure != nil {
            return "exclamationmark.triangle.fill"
        }

        switch WindowsDownloadStage.resolve(phase: controller.phase, isPreparingWindows: isPreparingWindows) {
        case .download: return "arrow.down"
        case .verify: return "checkmark.shield.fill"
        case .prepare: return "gearshape.2.fill"
        case nil: return "exclamationmark.triangle.fill"
        }
    }

    /// Actions live in one bar: the ISO fallback on the left, the Microsoft page tucked in a menu
    /// unless the automation failed, and Cancel on the right like a macOS assistant.
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
                Button("Use an ISO File I Already Have…") {
                    controller.cancelDownload()
                    finish()
                    useExistingISO()
                }
                .buttonStyle(.link)
                .disabled(isPreparingWindows)
            }

            Spacer()

            if isFailed {
                Button(showsMicrosoftPage ? "Hide Microsoft Page" : "Show Microsoft Page") {
                    showsMicrosoftPage.toggle()
                }

                Button("Try Again") {
                    preparationFailure = nil
                    controller.reloadLandingPage()
                }
            } else {
                Menu {
                    Button(showsMicrosoftPage ? "Hide Microsoft Page" : "Show Microsoft Page") {
                        showsMicrosoftPage.toggle()
                    }
                    if showsMicrosoftPage {
                        Button("Use an ISO File I Already Have…") {
                            controller.cancelDownload()
                            finish()
                            useExistingISO()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More download options")
            }

            Button(isEmbedded ? "Cancel" : "Close") {
                controller.cancelDownload()
                finish()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isPreparingWindows)
        }
        .controlSize(isEmbedded ? .regular : .large)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// Only a failed download offers a retry; a failed VM preparation keeps the verified ISO, so
    /// reloading Microsoft's page there would throw away a multi-gigabyte download.
    private var isFailed: Bool {
        if case .failed = controller.phase {
            return true
        }
        return false
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
        case .downloading:
            return "Downloading Windows 11"
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
        case .downloading(let filename):
            return filename
        case .verifying:
            return "Veil is comparing the completed file with Microsoft's published SHA-256."
        case .downloaded:
            return "The ISO is complete. Veil is handing it to the local VM setup flow."
        case .failed(let message):
            return message
        }
    }
}

/// Download → Verify → Prepare, with the finished stages checked off.
private struct DownloadStageTracker: View {
    var current: WindowsDownloadStage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WindowsDownloadStage.allCases) { stage in
                if stage != .download {
                    Capsule()
                        .fill(stage.rawValue <= current.rawValue ? Color.accentColor.opacity(0.7) : .white.opacity(0.14))
                        .frame(width: 28, height: 2)
                }

                HStack(spacing: 5) {
                    Image(systemName: symbolName(for: stage))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint(for: stage))
                    Text(stage.title)
                        .font(.caption.weight(stage == current ? .semibold : .regular))
                        .foregroundStyle(stage.rawValue > current.rawValue ? .secondary : .primary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(WindowsDownloadStage.allCases.count): \(current.title)")
    }

    private func symbolName(for stage: WindowsDownloadStage) -> String {
        if stage.rawValue < current.rawValue {
            return "checkmark.circle.fill"
        }
        return stage == current ? "circle.dotted.circle" : "circle"
    }

    private func tint(for stage: WindowsDownloadStage) -> Color {
        if stage.rawValue < current.rawValue {
            return .green
        }
        return stage == current ? .accentColor : .secondary
    }
}
