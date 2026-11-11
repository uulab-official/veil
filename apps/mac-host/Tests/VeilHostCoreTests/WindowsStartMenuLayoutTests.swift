import Foundation
import Testing
@testable import VeilHostCore

struct WindowsStartMenuLayoutTests {
    private func app(_ name: String, folder: String? = nil) -> WindowsApp {
        WindowsApp(id: "start_\(name)", name: name, exePath: "", publisher: "", iconId: "", folder: folder)
    }

    @Test("apps without a folder sit at the top, sorted as Finder sorts")
    func topLevelSorted() {
        let layout = WindowsStartMenuLayout(apps: [app("Paint"), app("app 10"), app("app 9"), app("Calculator")])
        #expect(layout.topLevel.map(\.name) == ["app 9", "app 10", "Calculator", "Paint"])
        #expect(layout.folders.isEmpty)
    }

    @Test("folders become sorted submenus, and deeper folders join their top folder")
    func foldersGrouped() {
        let layout = WindowsStartMenuLayout(apps: [
            app("Task Manager", folder: "Windows Tools"),
            app("Character Map", folder: "Windows Tools\\System"),
            app("Word", folder: "Microsoft Office"),
        ])
        #expect(layout.folders.map(\.name) == ["Microsoft Office", "Windows Tools"])
        #expect(layout.folders[1].apps.map(\.name) == ["Character Map", "Task Manager"])
    }

    @Test("an older agent's apps, with no folder field, decode at the top level")
    func decodesWithoutFolder() throws {
        let json = #"{"id":"winapp_notepad","name":"Notepad","exePath":"notepad.exe","publisher":"Microsoft","iconId":"icon_notepad"}"#
        let decoded = try JSONDecoder().decode(WindowsApp.self, from: Data(json.utf8))
        #expect(decoded.folder == nil)
    }
}
