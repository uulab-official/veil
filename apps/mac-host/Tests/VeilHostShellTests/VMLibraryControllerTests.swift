import Foundation
import Testing
@testable import VeilHostCore
@testable import VeilHostShell

struct VMLibraryControllerTests {
    @Test("library errors name the machine and keep converter output")
    func libraryErrorMessages() {
        #expect(VMLibraryController.message(for: VMLibraryError.machineIsRunning("Office")).contains("Office"))
        #expect(VMLibraryController.message(for: VMLibraryError.diskConversionFailed("bad header")).contains("bad header"))
        #expect(VMLibraryController.message(for: VMLibraryError.diskConverterMissing).contains("brew install qemu"))
    }
}
