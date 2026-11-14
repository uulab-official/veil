import Foundation
import Testing
@testable import VeilHostCore

struct QEMUSharedFramebufferTests {
    @Test func parsesTheSocketProtocol() {
        let surface = QEMUSharedFramebuffer.Message(line: Data(#"{"t":"surface","shm":"/vfb.74602.4","width":1280,"height":800,"stride":5120,"format":537004168}"#.utf8))
        #expect(surface == .surface(name: "/vfb.74602.4", width: 1280, height: 800, stride: 5120, pixmanFormat: 537_004_168))
        #expect(QEMUSharedFramebuffer.Message.pixmanX8R8G8B8 == 537_004_168)

        let update = QEMUSharedFramebuffer.Message(line: Data(#"{"t":"update","x":0,"y":16,"w":1280,"h":32}"#.utf8))
        #expect(update == .update(x: 0, y: 16, width: 1280, height: 32))
    }

    @Test func rejectsSurfacesThatCannotBeMappedSafely() {
        // A stride shorter than a row, a name outside the shm namespace, and an absurd size.
        #expect(QEMUSharedFramebuffer.Message(line: Data(#"{"t":"surface","shm":"/vfb.1.1","width":1280,"height":800,"stride":100,"format":1}"#.utf8)) == nil)
        #expect(QEMUSharedFramebuffer.Message(line: Data(#"{"t":"surface","shm":"vfb","width":1280,"height":800,"stride":5120,"format":1}"#.utf8)) == nil)
        #expect(QEMUSharedFramebuffer.Message(line: Data(#"{"t":"surface","shm":"/vfb.1.1","width":99999,"height":800,"stride":5120,"format":1}"#.utf8)) == nil)
        #expect(QEMUSharedFramebuffer.Message(line: Data("not json".utf8)) == nil)
    }

    @Test func derivesTheSocketFromTheQMPSocket() {
        #expect(QEMUSharedFramebuffer.socketPath(forQMPSocketPath: "/tmp/vq-87024F21.qmp.sock") == "/tmp/vq-87024F21.fb.sock")
    }

    @Test func attachesTheObjectOnlyToAPatchedBundledQEMU() throws {
        let bundled = "/Applications/Veil.app/Contents/Resources/Runtime/bin/qemu-system-aarch64"
        let patch = "/Applications/Veil.app/Contents/Resources/Runtime/licenses/qemu-patches/\(QEMUSharedFramebuffer.patchFileName)"
        #expect(QEMUSharedFramebuffer.isSupported(executablePath: bundled, fileExists: { $0 == patch }))
        #expect(!QEMUSharedFramebuffer.isSupported(executablePath: "/opt/homebrew/bin/qemu-system-aarch64", fileExists: { $0 == patch }))

        let arguments = QEMUSharedFramebuffer.objectArguments(socketPath: "/tmp/vq-1.fb.sock")
        #expect(arguments == ["-object", "veil-shm-display,id=veilfb,path=/tmp/vq-1.fb.sock"])
        #expect(QEMUSharedFramebuffer.isAttached(arguments: arguments))
    }
}
