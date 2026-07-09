import AppKit
import Foundation

enum AppIconSource: String, Codable, Equatable {
    case bundled
    case fallback
}

struct MainWindowFrameReport: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: NSRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }
}

struct MainWindowLaunchReport: Encodable, Equatable {
    static let expectedBundleIdentifier = "org.uulab.veil.host-shell"

    var bundleIdentifier: String
    var activationPolicy: String
    var mainWindowCount: Int
    var visibleMainWindowCount: Int
    var duplicateMainWindowCount: Int
    var isAppActive: Bool
    var isMainWindowKey: Bool
    var frame: MainWindowFrameReport
    var minWidth: Double
    var minHeight: Double
    var titlebarAppearsTransparent: Bool
    var hasFullSizeContentView: Bool
    var appIconSource: AppIconSource

    var meetsLauncherContract: Bool {
        bundleIdentifier == Self.expectedBundleIdentifier
            && activationPolicy == "regular"
            && mainWindowCount == 1
            && visibleMainWindowCount == 1
            && duplicateMainWindowCount == 0
            && frame.width >= 1180
            && frame.height >= 760
            && minWidth >= 1180
            && minHeight >= 760
            && titlebarAppearsTransparent
            && hasFullSizeContentView
            && appIconSource == .bundled
    }

    enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case activationPolicy
        case mainWindowCount
        case visibleMainWindowCount
        case duplicateMainWindowCount
        case isAppActive
        case isMainWindowKey
        case frame
        case minWidth
        case minHeight
        case titlebarAppearsTransparent
        case hasFullSizeContentView
        case appIconSource
        case meetsLauncherContract
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(activationPolicy, forKey: .activationPolicy)
        try container.encode(mainWindowCount, forKey: .mainWindowCount)
        try container.encode(visibleMainWindowCount, forKey: .visibleMainWindowCount)
        try container.encode(duplicateMainWindowCount, forKey: .duplicateMainWindowCount)
        try container.encode(isAppActive, forKey: .isAppActive)
        try container.encode(isMainWindowKey, forKey: .isMainWindowKey)
        try container.encode(frame, forKey: .frame)
        try container.encode(minWidth, forKey: .minWidth)
        try container.encode(minHeight, forKey: .minHeight)
        try container.encode(titlebarAppearsTransparent, forKey: .titlebarAppearsTransparent)
        try container.encode(hasFullSizeContentView, forKey: .hasFullSizeContentView)
        try container.encode(appIconSource, forKey: .appIconSource)
        try container.encode(meetsLauncherContract, forKey: .meetsLauncherContract)
    }
}

enum LaunchVerificationArguments {
    static func reportURL(from arguments: [String]) -> URL? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--launch-verification-report" {
                guard arguments.indices.contains(index + 1) else {
                    return nil
                }
                return URL(fileURLWithPath: arguments[index + 1])
            }

            let prefix = "--launch-verification-report="
            if argument.hasPrefix(prefix) {
                let path = String(argument.dropFirst(prefix.count))
                return path.isEmpty ? nil : URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}
