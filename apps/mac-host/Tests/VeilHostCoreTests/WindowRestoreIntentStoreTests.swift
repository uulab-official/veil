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
        let intent = WindowRestoreIntent(appIds: ["winapp_notepad"])

        try await store.save(intent)
        let loaded = try await store.load()

        #expect(loaded == intent)
        #expect(loaded?.appIds == ["winapp_notepad"])
    }
}
