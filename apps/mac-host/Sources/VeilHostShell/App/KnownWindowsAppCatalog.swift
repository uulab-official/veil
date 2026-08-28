import VeilHostCore

enum KnownWindowsAppCatalog {
    /// Stable Windows inbox apps that remain launchable while the guest catalog
    /// connection is recovering. A live agent overview replaces this bootstrap list.
    static let apps = [
        WindowsApp(
            id: "winapp_notepad",
            name: "Notepad",
            exePath: "C:\\Windows\\System32\\notepad.exe",
            publisher: "Microsoft",
            iconId: "icon_notepad"
        ),
        WindowsApp(
            id: "winapp_calculator",
            name: "Calculator",
            exePath: "C:\\Windows\\System32\\calc.exe",
            publisher: "Microsoft",
            iconId: "icon_calculator"
        ),
        WindowsApp(
            id: "winapp_paint",
            name: "Paint",
            exePath: "C:\\Windows\\System32\\mspaint.exe",
            publisher: "Microsoft",
            iconId: "icon_paint"
        )
    ]
}
