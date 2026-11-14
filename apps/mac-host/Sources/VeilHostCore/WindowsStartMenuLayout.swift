import Foundation

/// The Windows Start menu as Mac menus: apps at the top level, then one submenu per Start menu folder,
/// each sorted by name the way Finder sorts.
public struct WindowsStartMenuLayout: Equatable, Sendable {
    public struct Folder: Equatable, Sendable {
        public var name: String
        public var apps: [WindowsApp]
    }

    public var topLevel: [WindowsApp]
    public var folders: [Folder]

    public init(apps: [WindowsApp]) {
        func byName(_ lhs: WindowsApp, _ rhs: WindowsApp) -> Bool {
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        var grouped: [String: [WindowsApp]] = [:]
        var topLevel: [WindowsApp] = []
        // An app known only from an open window, such as a program started from its folder, is not in the
        // Windows Start menu either.
        for app in apps where app.isStartMenuEntry {
            // Only the first folder level becomes a submenu; deeper folders join their top folder.
            let folder = app.folder?
                .split(whereSeparator: { $0 == "\\" || $0 == "/" })
                .first
                .map(String.init)
            if let folder, !folder.isEmpty {
                grouped[folder, default: []].append(app)
            } else {
                topLevel.append(app)
            }
        }
        self.topLevel = topLevel.sorted(by: byName)
        folders = grouped
            .map { Folder(name: $0.key, apps: $0.value.sorted(by: byName)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
