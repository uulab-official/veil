import Foundation

/// Reads the VM's UEFI variable store without parsing it. Windows Setup adds a `Boot####` entry
/// titled "Windows Boot Manager" once the disk holds a bootable Windows; the title is stored as
/// UTF-16LE, and the variable store sits at the front of the 64 MiB file.
enum UEFIBootEntries {
    static let variableStoreSearchBytes = 1_024 * 1_024
    private static let windowsBootManagerTitle = Data("Windows Boot Manager".utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] })

    static func registersWindowsBootManager(varsURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: varsURL) else {
            return false
        }
        defer {
            try? handle.close()
        }
        guard let bytes = try? handle.read(upToCount: variableStoreSearchBytes) else {
            return false
        }
        return bytes.range(of: windowsBootManagerTitle) != nil
    }
}
