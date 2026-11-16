import AppIntents
import VeilHostCore

/// What the running app does for a Shortcuts action. ``VeilHostShellApp`` conforms in
/// `VeilHostShellApp+ShortcutIntents.swift`; the intents only ever talk to this, so they never reach into
/// SwiftUI state directly.
@MainActor
protocol VeilShortcutPerforming {
    var shortcutWindowsApps: [WindowsApp] { get }
    var shortcutStopNeedsConfirmation: Bool { get }
    func shortcutStartWindows() async throws -> LocalizedStringResource
    func shortcutStopWindows() async throws -> LocalizedStringResource
    func shortcutSuspendWindows() async throws -> LocalizedStringResource
    func shortcutResumeWindows() async throws -> LocalizedStringResource
    func shortcutOpenWindowsApp(id: String) async throws -> LocalizedStringResource
}

struct VeilShortcutError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource

    static let notReady = VeilShortcutError(
        localizedStringResource: "Veil is still opening. Try the shortcut again in a moment."
    )
}

/// Hands Shortcuts requests to the app once its main window has configured itself.
///
/// Shortcuts can launch Veil to run an action, and the intent's `perform()` can then run before the
/// SwiftUI scene has built its models. Waiting a bounded time for registration turns that race into a short
/// delay instead of an error on every cold launch.
@MainActor
final class VeilShortcutBridge {
    static let shared = VeilShortcutBridge()

    var performer: (any VeilShortcutPerforming)?

    func waitForPerformer(timeout: Duration = .seconds(30)) async throws -> any VeilShortcutPerforming {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let performer {
                return performer
            }
            guard ContinuousClock.now < deadline else {
                throw VeilShortcutError.notReady
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    /// The live app list once the guest has reported it, otherwise the inbox apps every Windows has.
    var windowsApps: [WindowsApp] {
        performer?.shortcutWindowsApps ?? KnownWindowsAppCatalog.apps
    }
}

struct StartWindowsIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Windows"
    static let description = IntentDescription("Starts Windows in Veil, or resumes the suspended session.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let performer = try await VeilShortcutBridge.shared.waitForPerformer()
        return .result(dialog: IntentDialog(try await performer.shortcutStartWindows()))
    }
}

struct StopWindowsIntent: AppIntent {
    static let title: LocalizedStringResource = "Shut Down Windows"
    static let description = IntentDescription("Shuts down Windows in Veil.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let performer = try await VeilShortcutBridge.shared.waitForPerformer()
        // Same rule as the Shut Down menu item: open Windows app windows close with it, so ask first.
        if performer.shortcutStopNeedsConfirmation {
            try await requestConfirmation(
                actionName: .turnOff,
                dialog: "Shutting down Windows closes the Windows app windows that are open. Continue?"
            )
        }
        return .result(dialog: IntentDialog(try await performer.shortcutStopWindows()))
    }
}

struct SuspendWindowsIntent: AppIntent {
    static let title: LocalizedStringResource = "Suspend Windows"
    static let description = IntentDescription("Saves the running Windows session so it can resume where it left off.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let performer = try await VeilShortcutBridge.shared.waitForPerformer()
        return .result(dialog: IntentDialog(try await performer.shortcutSuspendWindows()))
    }
}

struct ResumeWindowsIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Windows"
    static let description = IntentDescription("Resumes a suspended Windows session.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let performer = try await VeilShortcutBridge.shared.waitForPerformer()
        return .result(dialog: IntentDialog(try await performer.shortcutResumeWindows()))
    }
}

struct WindowsAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Windows App"
    static let defaultQuery = WindowsAppEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ app: WindowsApp) {
        self.init(id: app.id, name: app.name)
    }
}

struct WindowsAppEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [WindowsAppEntity.ID]) async throws -> [WindowsAppEntity] {
        VeilShortcutBridge.shared.windowsApps
            .filter { identifiers.contains($0.id) }
            .map(WindowsAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [WindowsAppEntity] {
        VeilShortcutBridge.shared.windowsApps.map(WindowsAppEntity.init)
    }
}

struct OpenWindowsAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Windows App"
    static let description = IntentDescription("Opens a Windows app as a Mac window, starting Windows first if needed.")

    @Parameter(title: "App")
    var app: WindowsAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$app)")
    }

    init() {}

    init(app: WindowsAppEntity) {
        self.app = app
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let performer = try await VeilShortcutBridge.shared.waitForPerformer()
        return .result(dialog: IntentDialog(try await performer.shortcutOpenWindowsApp(id: app.id)))
    }
}

struct VeilAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWindowsIntent(),
            phrases: ["Start Windows in \(.applicationName)", "Start \(.applicationName)"],
            shortTitle: "Start Windows",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopWindowsIntent(),
            phrases: ["Shut down Windows in \(.applicationName)"],
            shortTitle: "Shut Down Windows",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: SuspendWindowsIntent(),
            phrases: ["Suspend Windows in \(.applicationName)"],
            shortTitle: "Suspend Windows",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeWindowsIntent(),
            phrases: ["Resume Windows in \(.applicationName)"],
            shortTitle: "Resume Windows",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: OpenWindowsAppIntent(),
            phrases: ["Open \(\.$app) in \(.applicationName)", "Open a Windows app in \(.applicationName)"],
            shortTitle: "Open Windows App",
            systemImageName: "macwindow"
        )
    }
}
