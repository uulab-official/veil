import AppKit
import Combine
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

enum WindowsDownloadPhase: Equatable {
    case loadingPage
    case choosingDownload
    case downloading(filename: String)
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
    private var progressTask: Task<Void, Never>?

    func loadLandingPage() {
        guard !hasLoadedLandingPage else {
            return
        }

        hasLoadedLandingPage = true
        phase = .loadingPage
        webView.load(URLRequest(url: WindowsDownloadURLPolicy.landingPageURL))
    }

    func reloadLandingPage() {
        cancelDownload()
        destinationURL = nil
        phase = .loadingPage
        webView.load(URLRequest(url: WindowsDownloadURLPolicy.landingPageURL))
    }

    func cancelDownload() {
        progressTask?.cancel()
        progressTask = nil
        downloadProgress = nil
        let partialDestination = destinationURL
        destinationURL = nil

        guard let activeDownload else {
            removeFileIfPresent(at: partialDestination)
            return
        }

        self.activeDownload = nil
        activeDownload.cancel { [self] _ in
            removeFileIfPresent(at: partialDestination)
        }
    }

    private func beginTracking(_ download: WKDownload) {
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
        progressTask?.cancel()
        progressTask = nil
        downloadProgress = nil
        activeDownload = nil
        if removePartialFile {
            removePartialDestination()
        }
        phase = .failed(message)
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
        case .loadingPage, .choosingDownload:
            phase = .choosingDownload
        case .downloading, .downloaded, .failed:
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
            downloadProgress = 1
            self.destinationURL = nil
            phase = .downloaded(destinationURL)
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

    let prepareDownloadedISO: (URL) async -> Bool
    let useExistingISO: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            MicrosoftWindowsDownloadWebView(controller: controller)
                .frame(minWidth: 920, minHeight: 600)

            Divider()
            footer
        }
        .frame(minWidth: 960, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
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
                    dismiss()
                } else {
                    preparationFailure = "The ISO was saved, but Veil could not finish VM preparation. Review Windows Settings and try again."
                }
            }
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

    private var footer: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.callout.weight(.semibold))
                Text(preparationFailure ?? statusDetail)
                    .font(.caption)
                    .foregroundStyle(preparationFailure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(2)
            }

            Spacer()

            if case .failed = controller.phase {
                Button("Reload Microsoft Page") {
                    preparationFailure = nil
                    controller.reloadLandingPage()
                }
            }

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
            case .choosingDownload:
                Image(systemName: "hand.point.up.left.fill")
                    .foregroundStyle(.tint)
            case .loadingPage, .downloading:
                EmptyView()
            }
        }
    }

    private var isBusy: Bool {
        switch controller.phase {
        case .loadingPage, .downloading:
            return true
        case .choosingDownload, .downloaded, .failed:
            return false
        }
    }

    private var statusTitle: String {
        if isPreparingWindows {
            return "Preparing Windows VM"
        }

        switch controller.phase {
        case .loadingPage:
            return "Opening Microsoft's download page"
        case .choosingDownload:
            return "Choose the edition and language"
        case .downloading(let filename):
            return "Downloading \(filename)"
        case .downloaded:
            return "Windows ISO downloaded"
        case .failed:
            return "Download needs attention"
        }
    }

    private var statusDetail: String {
        switch controller.phase {
        case .loadingPage:
            return "Veil only allows HTTPS navigation and ISO downloads from Microsoft-owned domains."
        case .choosingDownload:
            return "Microsoft requires these choices before issuing a temporary ISO link. Veil will handle saving and VM preparation after Download starts."
        case .downloading:
            if let progress = controller.downloadProgress {
                return "\(Int(progress * 100))% complete. The ISO is being saved locally in Veil's Application Support folder."
            }
            return "The ISO is being saved locally in Veil's Application Support folder. Keep this window open."
        case .downloaded:
            return "The ISO is complete. Veil is handing it to the local VM setup flow."
        case .failed(let message):
            return message
        }
    }
}
