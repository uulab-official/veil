import Foundation

extension LocalVMRuntimeService {
    /// Gives Windows a new CPU and memory size, kept inside this Mac's limits. QEMU reads them at the
    /// next start, so Windows must be stopped (not suspended: a saved session needs the same sizes).
    public func updateHardware(cpuCount: Int, memoryMB: Int) async throws -> VMRuntimeSnapshot {
        try await requireResourceMutationAllowed()
        var profile = try await profileStore.load() ?? defaultProfile()
        let limits = resourceLimits ?? VMResourceLimits.currentHost()
        profile.cpuCount = limits.clampedCPUCount(cpuCount)
        profile.memoryMB = limits.clampedMemoryMB(memoryMB)
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }

    /// What Veil does with Windows when it opens and quits. These change no VM hardware, so they can be
    /// set while Windows runs.
    public func updateStartupBehavior(autoStart: Bool, suspendOnQuit: Bool) async throws -> VMRuntimeSnapshot {
        var profile = try await profileStore.load() ?? defaultProfile()
        profile.autoStart = autoStart
        profile.suspendOnQuit = suspendOnQuit
        try await profileStore.save(profile)
        return try await loadSnapshot()
    }
}
