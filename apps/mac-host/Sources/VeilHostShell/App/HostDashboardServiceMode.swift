import Foundation
import VeilHostCore

enum HostDashboardServiceMode: Equatable {
    case live
    case demo

    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        if arguments.contains("--demo") || environment["VEIL_DEMO_MODE"] == "1" {
            return .demo
        }

        return .live
    }

    func makeService(
        transport: URLSessionWebSocketTransport?,
        connectionPlan: AppGuestAgentConnectionPlan
    ) -> any HostDashboardService {
        switch self {
        case .live:
            if let transport, connectionPlan.isAvailable {
                VeilHostClient(transport: transport)
            } else {
                UnavailableGuestAgentService(plan: connectionPlan)
            }
        case .demo:
            DemoHostDashboardService()
        }
    }
}
