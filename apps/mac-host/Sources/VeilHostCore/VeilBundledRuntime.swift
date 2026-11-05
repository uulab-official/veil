import Foundation

/// The Windows engine Veil ships inside its app bundle: QEMU, qemu-img, swtpm, and the Arm Secure Boot
/// firmware, laid out by `script/bundle_qemu_runtime.sh` under `Contents/Resources/Runtime`.
///
/// Every QEMU, TPM, and firmware lookup checks this directory before Homebrew or another
/// virtualization app, so a Mac without either can still install and run Windows.
public enum VeilBundledRuntime {
    public static let directoryName = "Runtime"
    public static let qemuExecutable = "bin/qemu-system-aarch64"
    public static let tpmEmulator = "bin/swtpm"
    /// Creates, resizes, converts, and snapshots the Windows system disk while QEMU is not using it.
    public static let qemuImage = "bin/qemu-img"
    public static let secureFirmware = "share/qemu/edk2-aarch64-secure-code.fd"
    public static let secureFirmwareVarsTemplate = "share/qemu/edk2-arm-secure-vars.fd"

    /// `nil` for a `swift run` or test binary, which has no bundled runtime.
    public static func directory(
        bundle: Bundle = .main,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        guard let directory = bundle.resourceURL?.appendingPathComponent(directoryName, isDirectory: true),
              fileExists(directory.appendingPathComponent(qemuExecutable).path) else {
            return nil
        }
        return directory
    }

    public static func path(_ relativePath: String, in directory: URL?) -> String? {
        directory?.appendingPathComponent(relativePath).path
    }
}
