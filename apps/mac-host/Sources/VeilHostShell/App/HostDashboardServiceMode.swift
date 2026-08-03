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

    func makeService(transport: URLSessionWebSocketTransport) -> any HostDashboardService {
        switch self {
        case .live:
            VeilHostClient(transport: transport)
        case .demo:
            DemoHostDashboardService()
        }
    }
}
