import Foundation

/// The guest display in shared memory, from the `veil-shm-display` object Veil's patched QEMU provides
/// (`script/qemu-patches/0003-ui-add-a-shared-memory-display-listener.patch`).
///
/// QEMU mirrors the default console into a POSIX shared-memory object and tells one client over a Unix
/// socket which rectangles changed, as newline-terminated JSON. Unlike the loopback VNC server it has no
/// 30 ms refresh tick and copies only dirty rectangles, so the host can follow the guest at whatever rate
/// it presents. See docs/superpowers/specs/2026-11-10-coherence-framebuffer-design.md, stage 4.
public enum QEMUSharedFramebuffer {
    public static let objectID = "veilfb"
    public static let patchFileName = "0003-ui-add-a-shared-memory-display-listener.patch"

    /// Whether the QEMU at this path understands `-object veil-shm-display`: only Veil's bundled runtime
    /// built with the patch. Any other QEMU refuses to start with the unknown object type.
    public static func isSupported(
        executablePath: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        let runtime = URL(fileURLWithPath: executablePath).deletingLastPathComponent().deletingLastPathComponent()
        return fileExists(runtime.appendingPathComponent("licenses/qemu-patches/\(patchFileName)").path)
    }

    /// The socket beside a launch's QMP socket, so it needs no field of its own in the launch record.
    public static func socketPath(forQMPSocketPath qmpSocketPath: String) -> String {
        if qmpSocketPath.hasSuffix(".qmp.sock") {
            return String(qmpSocketPath.dropLast(".qmp.sock".count)) + ".fb.sock"
        }
        return qmpSocketPath + ".fb"
    }

    public static func objectArguments(socketPath: String) -> [String] {
        ["-object", "veil-shm-display,id=\(objectID),path=\(socketPath)"]
    }

    /// Whether a launch's arguments include the object, which is what tells the host to read the
    /// shared framebuffer instead of VNC.
    public static func isAttached(arguments: [String]) -> Bool {
        arguments.contains { $0.hasPrefix("veil-shm-display,id=\(objectID),") }
    }

    /// One line of the socket protocol.
    public enum Message: Equatable, Sendable {
        /// A new shared-memory object holding the whole display.
        case surface(name: String, width: Int, height: Int, stride: Int, pixmanFormat: UInt32)
        /// A rectangle of the current surface was rewritten.
        case update(x: Int, y: Int, width: Int, height: Int)

        /// `PIXMAN_x8r8g8b8` and `PIXMAN_a8r8g8b8`: 32-bit little-endian BGRA in memory.
        public static let pixmanX8R8G8B8: UInt32 = 0x2002_0888
        public static let pixmanA8R8G8B8: UInt32 = 0x2002_8888

        public init?(line: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = object["t"] as? String else {
                return nil
            }
            func int(_ key: String) -> Int? {
                (object[key] as? NSNumber)?.intValue
            }
            switch type {
            case "surface":
                guard let name = object["shm"] as? String,
                      name.hasPrefix("/"),
                      let width = int("width"), width > 0, width <= 16_384,
                      let height = int("height"), height > 0, height <= 16_384,
                      let stride = int("stride"), stride >= width * 4, stride <= 16_384 * 4,
                      let format = (object["format"] as? NSNumber)?.uint32Value else {
                    return nil
                }
                self = .surface(name: name, width: width, height: height, stride: stride, pixmanFormat: format)
            case "update":
                guard let x = int("x"), let y = int("y"), let width = int("w"), let height = int("h") else {
                    return nil
                }
                self = .update(x: x, y: y, width: width, height: height)
            default:
                return nil
            }
        }
    }
}
