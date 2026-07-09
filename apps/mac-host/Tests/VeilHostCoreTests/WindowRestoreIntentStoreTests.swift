import Foundation
import Testing

@testable import VeilHostCore

@Suite("Window restore intent store")
struct WindowRestoreIntentStoreTests {
    @Test("saves and loads mapped app ids as JSON")
    func savesAndLoadsMappedAppIds() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONWindowRestoreIntentStore(directory: directory)
        let intent = WindowRestoreIntent(
            appIds: ["winapp_notepad"],
            appWindowCounts: ["winapp_notepad": 2]
        )

        try await store.save(intent)
        let loaded = try await store.load()

        #expect(loaded == intent)
        #expect(loaded?.appIds == ["winapp_notepad"])
        #expect(loaded?.appWindowCounts == ["winapp_notepad": 2])
        #expect(loaded?.appIdsForRestoreLaunches == ["winapp_notepad", "winapp_notepad"])
        #expect(loaded?.normalizedAppWindowCounts == ["winapp_notepad": 2])
    }

    @Test("loads legacy mapped app ids as one window per app")
    func loadsLegacyMappedAppIdsAsOneWindowPerApp() async throws {
        let data = Data(#"{"appIds":["winapp_notepad","winapp_calculator"]}"#.utf8)
        let intent = try JSONDecoder().decode(WindowRestoreIntent.self, from: data)

        #expect(intent.appIds == ["winapp_notepad", "winapp_calculator"])
        #expect(intent.appWindowCounts == nil)
        #expect(intent.appIdsForRestoreLaunches == ["winapp_notepad", "winapp_calculator"])
        #expect(intent.normalizedAppWindowCounts == ["winapp_notepad": 1, "winapp_calculator": 1])
    }

    @Test("saves and loads pending app launch intent as JSON")
    func savesAndLoadsPendingAppLaunchIntent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONPendingLaunchIntentStore(directory: directory)
        let intent = PendingLaunchIntent(appId: "winapp_notepad")

        try await store.save(intent)
        let loaded = try await store.load()

        #expect(loaded == intent)
        #expect(loaded?.appId == "winapp_notepad")
    }
}
