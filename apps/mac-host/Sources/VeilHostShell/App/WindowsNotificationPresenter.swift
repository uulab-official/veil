import Foundation
import UserNotifications
import VeilHostCore

enum WindowsNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

struct WindowsNotificationPresentationRequest: Equatable {
    var identifier: String
    var title: String
    var body: String
    var threadIdentifier: String
    var userInfo: [String: String]
}

enum WindowsNotificationPresentationResult: Equatable {
    case scheduled(identifier: String)
    case permissionDenied
    case authorizationRequestDeclined
    case invalidNotification
}

protocol WindowsNotificationCenterClient: Sendable {
    func authorizationStatus() async -> WindowsNotificationAuthorizationStatus
    func requestAuthorization() async -> Bool
    func add(_ request: WindowsNotificationPresentationRequest) async throws
}

struct WindowsNotificationPresenter: Sendable {
    var center: any WindowsNotificationCenterClient

    func present(_ notification: WindowsNotificationReceivedEvent) async -> WindowsNotificationPresentationResult {
        guard let request = Self.presentationRequest(for: notification) else {
            return .invalidNotification
        }

        let status = await center.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            guard await center.requestAuthorization() else {
                return .authorizationRequestDeclined
            }
        case .denied, .unknown:
            return .permissionDenied
        }

        do {
            try await center.add(request)
            return .scheduled(identifier: request.identifier)
        } catch {
            return .permissionDenied
        }
    }

    static func presentationRequest(
        for notification: WindowsNotificationReceivedEvent
    ) -> WindowsNotificationPresentationRequest? {
        let title = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notification.notificationId.isEmpty, !title.isEmpty else {
            return nil
        }

        let appName = notification.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = notification.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyText: String
        if let body, !body.isEmpty, let appName, !appName.isEmpty {
            bodyText = "\(appName): \(body)"
        } else if let body, !body.isEmpty {
            bodyText = body
        } else if let appName, !appName.isEmpty {
            bodyText = appName
        } else {
            bodyText = "Windows notification"
        }

        var userInfo = [
            "notificationId": notification.notificationId,
            "receivedAt": notification.receivedAt
        ]
        if let appId = notification.appId, !appId.isEmpty {
            userInfo["appId"] = appId
        }
        if let appName, !appName.isEmpty {
            userInfo["appName"] = appName
        }
        if let sourceAumid = notification.sourceAumid, !sourceAumid.isEmpty {
            userInfo["sourceAumid"] = sourceAumid
        }

        return WindowsNotificationPresentationRequest(
            identifier: "veil.windows.\(notification.notificationId)",
            title: title,
            body: bodyText,
            threadIdentifier: notification.appId ?? "windows-notifications",
            userInfo: userInfo
        )
    }
}

struct MacUserNotificationCenter: WindowsNotificationCenterClient {
    func authorizationStatus() async -> WindowsNotificationAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: WindowsNotificationAuthorizationStatus(settings.authorizationStatus))
            }
        }
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func add(_ request: WindowsNotificationPresentationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.threadIdentifier = request.threadIdentifier
        content.userInfo = request.userInfo
        let notificationRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(notificationRequest)
    }
}

private extension WindowsNotificationAuthorizationStatus {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}
