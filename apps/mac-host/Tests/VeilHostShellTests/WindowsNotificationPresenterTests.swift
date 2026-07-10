import Testing
import VeilHostCore

@testable import VeilHostShell

@Suite("Windows notification presenter")
struct WindowsNotificationPresenterTests {
    @Test("builds macOS notification requests from Windows notification events")
    func buildsMacNotificationRequests() throws {
        let request = try #require(
            WindowsNotificationPresenter.presentationRequest(for: .notepadNotification)
        )

        #expect(request.identifier == "veil.windows.toast:winapp_notepad:0001")
        #expect(request.title == "Notepad")
        #expect(request.body == "Notepad: Autosaved Notes.txt")
        #expect(request.threadIdentifier == "winapp_notepad")
        #expect(request.userInfo["notificationId"] == "toast:winapp_notepad:0001")
        #expect(request.userInfo["appId"] == "winapp_notepad")
        #expect(request.userInfo["sourceAumid"] == "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App")
    }

    @Test("requests permission once before scheduling first Windows notification")
    func requestsPermissionBeforeScheduling() async throws {
        let center = FakeNotificationCenter(status: .notDetermined, requestAuthorizationResult: true)
        let presenter = WindowsNotificationPresenter(center: center)

        let result = await presenter.present(.notepadNotification)
        let requests = await center.requests

        #expect(result == .scheduled(identifier: "veil.windows.toast:winapp_notepad:0001"))
        #expect(await center.authorizationRequestCount == 1)
        #expect(requests.map(\.identifier) == ["veil.windows.toast:winapp_notepad:0001"])
    }

    @Test("does not schedule when macOS notification permission is denied")
    func doesNotScheduleWhenPermissionDenied() async throws {
        let center = FakeNotificationCenter(status: .denied)
        let presenter = WindowsNotificationPresenter(center: center)

        let result = await presenter.present(.notepadNotification)

        #expect(result == .permissionDenied)
        #expect(await center.authorizationRequestCount == 0)
        #expect(await center.requests.isEmpty)
    }

    @Test("rejects invalid Windows notification events")
    func rejectsInvalidNotifications() async throws {
        let center = FakeNotificationCenter(status: .authorized)
        let presenter = WindowsNotificationPresenter(center: center)
        let notification = WindowsNotificationReceivedEvent(
            notificationId: "toast:empty",
            title: " ",
            receivedAt: "2026-07-10T12:15:00Z"
        )

        let result = await presenter.present(notification)

        #expect(result == .invalidNotification)
        #expect(await center.requests.isEmpty)
    }
}

private actor FakeNotificationCenter: WindowsNotificationCenterClient {
    var status: WindowsNotificationAuthorizationStatus
    var requestAuthorizationResult: Bool
    var authorizationRequestCount = 0
    var requests: [WindowsNotificationPresentationRequest] = []

    init(
        status: WindowsNotificationAuthorizationStatus,
        requestAuthorizationResult: Bool = false
    ) {
        self.status = status
        self.requestAuthorizationResult = requestAuthorizationResult
    }

    func authorizationStatus() async -> WindowsNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> Bool {
        authorizationRequestCount += 1
        if requestAuthorizationResult {
            status = .authorized
        }
        return requestAuthorizationResult
    }

    func add(_ request: WindowsNotificationPresentationRequest) async throws {
        requests.append(request)
    }
}

private extension WindowsNotificationReceivedEvent {
    static var notepadNotification: WindowsNotificationReceivedEvent {
        WindowsNotificationReceivedEvent(
            notificationId: "toast:winapp_notepad:0001",
            appId: "winapp_notepad",
            appName: "Notepad",
            title: "Notepad",
            body: "Autosaved Notes.txt",
            receivedAt: "2026-07-10T12:15:00Z",
            sourceAumid: "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App"
        )
    }
}
