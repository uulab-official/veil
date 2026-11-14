import Foundation
import VeilHostCore

extension VeilHostShellApp {
    /// Hands memory Windows is not using back to the Mac while Windows runs (`QEMUMemoryBalloonPolicy`).
    /// Every few seconds, at the same pace the balloon driver reports its statistics.
    func startMemoryBalloonLoopIfNeeded() {
        guard memoryBalloonTask == nil else {
            return
        }

        memoryBalloonTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(QEMUMemoryBalloon.statisticsPollingSeconds))
                guard !Task.isCancelled else {
                    return
                }
                guard vmModel.snapshot?.state == .running,
                      let service = vmModel.runtimeService as? LocalVMRuntimeService else {
                    continue
                }
                _ = await service.adjustMemoryBalloon(pressure: HostMemoryPressureMonitor.shared.current)
            }
        }
    }
}
