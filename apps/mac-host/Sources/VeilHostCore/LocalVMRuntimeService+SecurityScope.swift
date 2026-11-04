import Foundation

extension LocalVMRuntimeService {
    /// Diagnostics bundles are intended to be shared for bug reports. Path fields across
    /// `VMRuntimeSnapshot`, `VMConsoleLaunchEvidence`, and other nested types are not individually
    /// sanitized, so every absolute path under the current user's home directory reveals the macOS
    /// account name. Replacing the home directory prefix in the serialized JSON text (rather than in
    /// every nested struct field) keeps the bundle informative while removing that account name.
    static func redactingHomeDirectory(in data: Data) -> Data {
        let homeDirectoryPath = FileManager.default.homeDirectoryForCurrentUser.path
        guard !homeDirectoryPath.isEmpty,
              let json = String(data: data, encoding: .utf8) else {
            return data
        }

        // JSONEncoder escapes "/" as "\/" on this platform, so the home directory can appear in the
        // serialized text either escaped or unescaped depending on the encoder's slash-escaping
        // behavior. Replace both forms to redact it reliably either way.
        let escapedHomeDirectoryPath = homeDirectoryPath.replacingOccurrences(of: "/", with: "\\/")
        let redacted = json
            .replacingOccurrences(of: escapedHomeDirectoryPath, with: "~")
            .replacingOccurrences(of: homeDirectoryPath, with: "~")
        return Data(redacted.utf8)
    }

    struct SecurityScopedFileAccess {
        var role: Role
        var url: URL
        var didStart: Bool

        enum Role {
            case installer
            case drivers
            case disk
        }

        func stop() {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    static func bookmarkData(
        for path: String?,
        existingPath: String? = nil,
        existingBookmarkData: Data? = nil
    ) -> Data? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if path == existingPath, let existingBookmarkData {
            return existingBookmarkData
        }

        return try? URL(fileURLWithPath: path).bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func startSecurityScopedAccesses(for profile: VMProfile) -> [SecurityScopedFileAccess] {
        [
            securityScopedAccess(
                role: .installer,
                bookmarkData: profile.installerMediaBookmarkData
            ),
            securityScopedAccess(
                role: .drivers,
                bookmarkData: profile.driverMediaBookmarkData
            ),
            securityScopedAccess(
                role: .disk,
                bookmarkData: profile.virtualDiskBookmarkData
            )
        ].compactMap { $0 }
    }

    static func securityScopedAccess(
        role: SecurityScopedFileAccess.Role,
        bookmarkData: Data?
    ) -> SecurityScopedFileAccess? {
        guard let bookmarkData else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return SecurityScopedFileAccess(
                role: role,
                url: url,
                didStart: url.startAccessingSecurityScopedResource()
            )
        } catch {
            return nil
        }
    }

    static func profileByResolvingSecurityScopedURLs(
        _ profile: VMProfile,
        accesses: [SecurityScopedFileAccess]
    ) -> VMProfile {
        var profile = profile
        for access in accesses {
            switch access.role {
            case .installer:
                profile.installerMediaPath = access.url.path
            case .drivers:
                profile.driverMediaPath = access.url.path
            case .disk:
                profile.virtualDiskPath = access.url.path
            }
        }
        return profile
    }
}
