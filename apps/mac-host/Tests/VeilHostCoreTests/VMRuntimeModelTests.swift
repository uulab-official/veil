import Testing

@testable import VeilHostCore

@Suite("VM runtime model")
struct VMRuntimeModelTests {
    @Test("loads supported host with no configured VM profile")
    @MainActor
    func loadsSupportedHostWithoutProfile() async throws {
        let model = VMRuntimeModel(
            service: FakeVMRuntimeService(
                snapshot: VMRuntimeSnapshot(
                    state: .notConfigured,
                    virtualizationAvailable: true,
                    architecture: "arm64",
                    minimumOSSupported: true,
                    profileName: nil,
                    detail: "No Windows VM profile has been created."
                )
            )
        )

        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.snapshot?.state == .notConfigured)
        #expect(model.statusText == "VM profile not configured")
        #expect(model.canStart == false)
        #expect(model.capabilitySummary == "Virtualization.framework available on arm64")
    }

    @Test("loads unsupported host capability message")
    @MainActor
    func loadsUnsupportedHostCapabilityMessage() async throws {
        let model = VMRuntimeModel(
            service: FakeVMRuntimeService(
                snapshot: VMRuntimeSnapshot(
                    state: .unsupported,
                    virtualizationAvailable: false,
                    architecture: "x86_64",
                    minimumOSSupported: false,
                    profileName: nil,
                    detail: "Veil requires macOS 15+ on Apple Silicon."
                )
            )
        )

        await model.load()

        #expect(model.phase == .loaded)
        #expect(model.statusText == "VM runtime unsupported")
        #expect(model.canStart == false)
        #expect(model.capabilitySummary == "Virtualization.framework unavailable on x86_64")
    }

    @Test("stores service errors")
    @MainActor
    func storesServiceErrors() async throws {
        let model = VMRuntimeModel(service: FakeVMRuntimeService(error: VMRuntimeError.capabilityProbeFailed))

        await model.load()

        #expect(model.phase == .failed)
        #expect(model.errorMessage == "Unable to inspect VM runtime capabilities.")
    }
}

private struct FakeVMRuntimeService: VMRuntimeService {
    var snapshot: VMRuntimeSnapshot?
    var error: (any Error)?

    func loadSnapshot() async throws -> VMRuntimeSnapshot {
        if let error {
            throw error
        }

        return try #require(snapshot)
    }
}
