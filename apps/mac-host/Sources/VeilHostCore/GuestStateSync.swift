import Foundation

/// Host settings for making Windows follow the Mac's state.
public enum GuestStateSyncSettings {
    /// `UserDefaults` key for "Match Mac appearance in Windows". Absent means on.
    public static let matchMacAppearanceKey = "veil.guestSync.matchMacAppearance"

    public static func matchMacAppearance(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: matchMacAppearanceKey) as? Bool ?? true
    }
}

/// Decides when to send `time.sync.request` and `appearance.set.request`, and remembers what the guest
/// last reported.
///
/// Triggers only *mark* work as pending. `flush` sends it once the agent connection is live, because a
/// wake or a resume usually lands while the agent socket is still reconnecting. Each pending item gets a
/// small retry budget so a guest that keeps failing is not hammered on every reconnect-loop tick.
@MainActor
public final class GuestStateSyncCoordinator {
    public static let maximumAttemptsPerTrigger = 3

    public private(set) var pendingTimeSyncReason: GuestTimeSyncReason?
    public private(set) var lastTimeSync: GuestTimeSyncStatus?
    public private(set) var lastAppearance: GuestAppearanceStatus?
    public private(set) var lastErrorMessage: String?
    /// The theme the guest last confirmed. Cleared on disconnect so a restarted agent is told again.
    public private(set) var confirmedTheme: GuestAppearanceTheme?

    private let now: () -> Date
    private var wasLive = false
    private var isFlushing = false
    private var timeSyncAttempts = 0
    private var appearanceAttempts = 0
    private var appearanceAttemptTheme: GuestAppearanceTheme?

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Marks a clock check as needed. The guest leaves its clock alone when it is already in sync, so
    /// asking too often is harmless.
    public func requestTimeSync(_ reason: GuestTimeSyncReason) {
        pendingTimeSyncReason = reason
        timeSyncAttempts = 0
    }

    /// Forces the next flush to resend the appearance, e.g. after the setting is turned back on.
    public func invalidateAppearance() {
        confirmedTheme = nil
        appearanceAttempts = 0
        appearanceAttemptTheme = nil
    }

    public func flush(
        service: any HostDashboardService,
        isLive: Bool,
        capabilities: AgentCapabilities?,
        macTheme: GuestAppearanceTheme,
        matchMacAppearance: Bool
    ) async {
        guard isLive else {
            if wasLive {
                // The next live connection may be a different agent process (a Windows restart, a
                // resumed session), so it has to be told both things again.
                wasLive = false
                invalidateAppearance()
            }
            return
        }

        if !wasLive {
            wasLive = true
            if pendingTimeSyncReason == nil {
                requestTimeSync(.agentConnected)
            }
        }

        guard !isFlushing else {
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        await flushTimeSync(service: service, supported: capabilities?.timeSync == true)
        await flushAppearance(
            service: service,
            supported: capabilities?.appearanceSync == true,
            macTheme: macTheme,
            enabled: matchMacAppearance
        )
    }

    private func flushTimeSync(service: any HostDashboardService, supported: Bool) async {
        guard let reason = pendingTimeSyncReason else {
            return
        }

        guard supported else {
            // An older agent cannot answer; asking would only draw unknown_message_type.
            pendingTimeSyncReason = nil
            return
        }

        guard timeSyncAttempts < Self.maximumAttemptsPerTrigger else {
            pendingTimeSyncReason = nil
            return
        }
        timeSyncAttempts += 1

        do {
            let response = try await service.syncGuestTime(hostUtc: now(), reason: reason)
            lastTimeSync = response.timeSync
            lastErrorMessage = nil
            pendingTimeSyncReason = nil
            VeilLog.agent.notice(
                "Guest time sync (\(reason.rawValue, privacy: .public)): \(response.timeSync.outcome.rawValue, privacy: .public), skew \(response.timeSync.skewMilliseconds ?? 0, privacy: .public) ms, action \(response.timeSync.recommendedAction, privacy: .public)."
            )
        } catch {
            lastErrorMessage = "Windows clock sync failed: \(error.localizedDescription)"
            VeilLog.agent.error("Guest time sync (\(reason.rawValue, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushAppearance(
        service: any HostDashboardService,
        supported: Bool,
        macTheme: GuestAppearanceTheme,
        enabled: Bool
    ) async {
        guard enabled, supported, confirmedTheme != macTheme else {
            return
        }

        if appearanceAttemptTheme != macTheme {
            appearanceAttemptTheme = macTheme
            appearanceAttempts = 0
        }
        guard appearanceAttempts < Self.maximumAttemptsPerTrigger else {
            return
        }
        appearanceAttempts += 1

        do {
            let response = try await service.setGuestAppearance(theme: macTheme)
            lastAppearance = response.appearance
            lastErrorMessage = nil
            confirmedTheme = response.appearance.isSupported ? response.appearance.theme : macTheme
            VeilLog.agent.notice(
                "Guest appearance set to \(macTheme.rawValue, privacy: .public): changed=\(response.appearance.changed, privacy: .public) broadcast=\(response.appearance.broadcast, privacy: .public)."
            )
        } catch {
            lastErrorMessage = "Windows appearance sync failed: \(error.localizedDescription)"
            VeilLog.agent.error("Guest appearance sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
