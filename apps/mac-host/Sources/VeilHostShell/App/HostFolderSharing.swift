import AppKit
import Foundation
import VeilHostCore

/// A Mac folder the user chose, served over WebDAV and mapped in Windows as a drive
/// (docs/protocol.md § Mac Folder In Windows). Off until a folder is chosen: nothing on the Mac is visible to
/// Windows by default.
@MainActor
final class HostFolderSharing {
    static let shared = HostFolderSharing()
    static let folderDefaultsKey = "VeilHostFolderPath"
    static let driveLetter = "M"
    static let label = "Mac"

    private var server: HostFolderWebDAVServer?
    private var servedRoot: URL?
    private var port: UInt16 = 0
    private var token = ""
    /// The agent connection the folder was last mapped for; a new connection maps it again.
    private var mountedFor: String?
    private(set) var lastStatus: HostFolderStatus?

    var folder: URL? {
        guard let path = UserDefaults.standard.string(forKey: Self.folderDefaultsKey), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func setFolder(_ url: URL?) {
        UserDefaults.standard.set(url?.path, forKey: Self.folderDefaultsKey)
        mountedFor = nil
    }

    /// Cheap when nothing changed, so it runs on every agent poll.
    func sync(model: HostDashboardModel) async {
        guard let folder else {
            stopServing()
            return
        }
        guard model.hasLiveAgentConnection, model.health?.capabilities.hostFolder == true else {
            mountedFor = nil
            return
        }
        if servedRoot?.standardizedFileURL != folder.standardizedFileURL {
            stopServing()
            do {
                token = Self.makeToken()
                let server = HostFolderWebDAVServer(root: folder, token: token)
                port = try server.start()
                self.server = server
                servedRoot = folder
                mountedFor = nil
            } catch {
                VeilLog.window.notice("Host folder server did not start: \(String(describing: error), privacy: .public)")
                return
            }
        }
        let connection = "\(model.health?.agentVersion ?? "")#\(port)"
        guard mountedFor != connection else {
            return
        }
        let status = await model.mountHostFolder(port: Int(port), token: token, driveLetter: Self.driveLetter, label: Self.label)
        lastStatus = status
        if status?.isMounted == true {
            mountedFor = connection
        }
        VeilLog.window.notice("Host folder \(folder.path, privacy: .private) as \(Self.driveLetter, privacy: .public): mounted=\(status?.isMounted ?? false, privacy: .public) \(status?.message ?? "", privacy: .public)")
    }

    private func stopServing() {
        server?.stop()
        server = nil
        servedRoot = nil
        mountedFor = nil
    }

    /// 32 hex characters from the system RNG, within the protocol's token pattern.
    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Asks the user for a folder, from the menu.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Share with Windows")
        panel.message = String(localized: "Windows shows this folder as drive M:. Only this folder is shared.")
        if panel.runModal() == .OK, let url = panel.url {
            setFolder(url)
        }
    }
}
