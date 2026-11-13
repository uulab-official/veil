import Foundation

extension HostDashboardModel {
    /// Sends any pending clock or appearance sync through this model's agent connection.
    public func flushGuestStateSync(
        _ coordinator: GuestStateSyncCoordinator,
        macTheme: GuestAppearanceTheme,
        matchMacAppearance: Bool,
        reduceVisualEffects: Bool? = nil
    ) async {
        await coordinator.flush(
            service: service,
            isLive: hasLiveAgentConnection,
            capabilities: health?.capabilities,
            macTheme: macTheme,
            matchMacAppearance: matchMacAppearance,
            reduceVisualEffects: reduceVisualEffects
        )
    }
}
