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
        let needsRepair = hasLiveAgentConnection
            && health?.capabilities.timeSyncRepair == true
            && coordinator.lastTimeSync?.recommendedAction == GuestTimeSyncRepairStatus.neededAction
        if guestClockNeedsRepair != needsRepair {
            guestClockNeedsRepair = needsRepair
        }
        let skew = needsRepair ? coordinator.lastTimeSync?.skewMilliseconds : nil
        if guestClockSkewMilliseconds != skew {
            guestClockSkewMilliseconds = skew
        }
    }

    /// Asks Windows to register the task that corrects its clock. Windows shows its approval prompt, which
    /// Veil shows on the Mac. Returns the agent's answer, or nil when it could not be asked.
    public func repairGuestClock() async -> GuestTimeSyncRepairStatus? {
        guard hasLiveAgentConnection, health?.capabilities.timeSyncRepair == true else {
            return nil
        }
        do {
            return try await service.repairGuestTimeSync().repair
        } catch {
            VeilLog.agent.error("Guest clock repair failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
