import Foundation
import Observation
import Sparkle

/// Updates of Veil itself, through Sparkle (https://sparkle-project.org).
///
/// Only a release build carries a feed and the public key its updates are signed with (`SUFeedURL`,
/// `SUPublicEDKey`; see `script/release_macos.sh` and `docs/release-updates.md`). A development build
/// carries neither, so it never offers to replace itself with a release. Sparkle checks once a day after
/// asking the user on the second launch whether it may; an update replaces Veil only after the user agrees,
/// and quitting for it goes through Veil's usual question about a running Windows.
@MainActor
@Observable
final class VeilUpdater {
    static let shared = VeilUpdater()

    /// Whether this build can update itself at all.
    let isConfigured: Bool
    /// False while a check is already showing, or when the build cannot update.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        isConfigured = UpdateFeedConfiguration(info: info) != nil
        guard isConfigured else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in
                self?.canCheckForUpdates = canCheck
            }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// What a bundle's Info.plist needs before Veil may update itself: an HTTPS feed and an EdDSA public key.
struct UpdateFeedConfiguration: Equatable {
    var feedURL: URL
    var publicKey: String

    init?(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed),
              url.scheme == "https",
              let key = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              // A 32-byte Ed25519 key is 44 characters of base64.
              key.count == 44,
              Data(base64Encoded: key)?.count == 32 else {
            return nil
        }
        feedURL = url
        publicKey = key
    }
}
