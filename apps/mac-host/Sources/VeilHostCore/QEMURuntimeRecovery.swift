import Foundation

/// The outcome of one conservative attempt to recover a live QEMU control/display path.
///
/// Recovery is deliberately narrower than restarting QEMU: it may only toggle a machine that
/// QMP first reports as running, and it must confirm the machine is running again before it reports
/// success. A missing or ambiguous control channel is surfaced instead of risking a data-lossy stop.
public enum QEMURuntimeRecoveryResult: Equatable, Sendable {
    case unsupported
    case notNeeded
    case recovered
    case unavailable(String)
    case failed(String)

    public var detail: String {
        switch self {
        case .unsupported:
            "Automatic QEMU runtime recovery is not supported by this provider."
        case .notNeeded:
            "QEMU is not in a running state that needs recovery."
        case .recovered:
            "QEMU runtime recovery completed and the machine is running."
        case .unavailable(let message), .failed(let message):
            message
        }
    }
}

/// Reconnects a stalled QEMU display/guest-agent path without restarting the guest.
///
/// The observed failure mode is a QEMU process whose QMP socket still answers while the RFB and
/// guest-agent paths stop responding. A pause/resume cycle refreshes those paths on the live machine
/// and preserves guest RAM and disk state. This controller never calls `quit`, sends a host kill, or
/// resumes a machine that was already paused before recovery began.
public struct QEMURuntimeRecoveryController: Sendable {
    public static let qmpControlIdleTimeoutSeconds = 10

    private let qmp: any QEMUQMPControlling
    private let launchRecordStore: any QEMULaunchRecordStore

    public init(
        qmp: any QEMUQMPControlling = QEMUQMPClient(),
        launchRecordStore: any QEMULaunchRecordStore = JSONQEMULaunchRecordStore()
    ) {
        self.qmp = qmp
        self.launchRecordStore = launchRecordStore
    }

    public func recoverStalledRuntime() async -> QEMURuntimeRecoveryResult {
        let launchRecord: QEMULaunchRecord?
        do {
            launchRecord = try await launchRecordStore.loadLatest()
        } catch {
            return .unavailable("The QEMU launch record could not be read.")
        }

        guard let qmpSocketPath = launchRecord?.qmpSocketPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !qmpSocketPath.isEmpty else {
            return .unavailable("QEMU control is unavailable because no QMP socket is recorded.")
        }

        let initialStatus: QEMUQMPReply
        do {
            initialStatus = try await qmp.run(
                .queryStatus,
                socketPath: qmpSocketPath,
                idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
            )
        } catch {
            return .unavailable(Self.userFacingMessage(for: error, operation: "QEMU status check"))
        }

        guard Self.isRunning(initialStatus) else {
            // A paused/stopped VM may be intentional. Never turn an automatic connection repair
            // into an unsolicited VM resume.
            return .notNeeded
        }

        do {
            try await pause(
                qmpSocketPath: qmpSocketPath,
                initialStatus: initialStatus
            )
        } catch let error as QEMURuntimeRecoveryError {
            return error.result
        } catch {
            return .failed(Self.userFacingMessage(for: error, operation: "QEMU pause"))
        }

        do {
            try await resume(qmpSocketPath: qmpSocketPath)
        } catch let error as QEMURuntimeRecoveryError {
            return error.result
        } catch {
            return .failed(Self.userFacingMessage(for: error, operation: "QEMU resume"))
        }

        do {
            let finalStatus = try await qmp.run(
                .queryStatus,
                socketPath: qmpSocketPath,
                idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
            )
            guard Self.isRunning(finalStatus) else {
                return .failed("QEMU did not return to a running state after connection recovery.")
            }
        } catch {
            return .unavailable(Self.userFacingMessage(for: error, operation: "QEMU recovery verification"))
        }

        return .recovered
    }

    private func pause(
        qmpSocketPath: String,
        initialStatus: QEMUQMPReply
    ) async throws {
        do {
            try await qmp.run(
                .stop,
                socketPath: qmpSocketPath,
                idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
            )
        } catch let error as QEMUQMPClientError {
            guard Self.isTransportUncertainty(error) else {
                throw QEMURuntimeRecoveryError.result(
                    .failed(Self.userFacingMessage(for: error, operation: "QEMU pause"))
                )
            }

            // QMP can apply `stop` just as the local nc process times out. Accept that case only
            // after an explicit paused-state query; a timeout alone is never treated as success.
            let status: QEMUQMPReply
            do {
                status = try await qmp.run(
                    .queryStatus,
                    socketPath: qmpSocketPath,
                    idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
                )
            } catch {
                throw QEMURuntimeRecoveryError.result(
                    .unavailable(Self.userFacingMessage(for: error, operation: "QEMU pause verification"))
                )
            }

            guard Self.isPaused(status) else {
                let detail = initialStatus.statusReturn ?? "running"
                throw QEMURuntimeRecoveryError.result(
                    .failed("QEMU pause was not confirmed; the machine still reports " + detail + ".")
                )
            }
        }
    }

    private func resume(qmpSocketPath: String) async throws {
        do {
            try await qmp.run(
                .cont,
                socketPath: qmpSocketPath,
                idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
            )
        } catch let error as QEMUQMPClientError {
            guard Self.isTransportUncertainty(error) else {
                throw QEMURuntimeRecoveryError.result(
                    .failed(Self.userFacingMessage(for: error, operation: "QEMU resume"))
                )
            }

            // As above, a transport timeout is recoverable only when a follow-up query proves the
            // requested state transition was applied.
            let status: QEMUQMPReply
            do {
                status = try await qmp.run(
                    .queryStatus,
                    socketPath: qmpSocketPath,
                    idleTimeoutSeconds: Self.qmpControlIdleTimeoutSeconds
                )
            } catch {
                throw QEMURuntimeRecoveryError.result(
                    .unavailable(Self.userFacingMessage(for: error, operation: "QEMU resume verification"))
                )
            }

            guard Self.isRunning(status) else {
                throw QEMURuntimeRecoveryError.result(
                    .failed("QEMU resume was not confirmed after the control channel timed out.")
                )
            }
        }
    }

    private static func isRunning(_ reply: QEMUQMPReply) -> Bool {
        reply.isRunning == true || reply.statusReturn == "running"
    }

    private static func isPaused(_ reply: QEMUQMPReply) -> Bool {
        reply.isRunning == false || reply.statusReturn == "paused"
    }

    private static func isTransportUncertainty(_ error: QEMUQMPClientError) -> Bool {
        switch error {
        case .socketUnavailable, .transportUnavailable, .noReply:
            true
        case .commandFailed:
            false
        }
    }

    private static func userFacingMessage(for error: Error, operation: String) -> String {
        if let qmpError = error as? QEMUQMPClientError {
            switch qmpError {
            case .socketUnavailable, .transportUnavailable:
                return operation + " could not reach QEMU control."
            case .noReply:
                return operation + " received no confirmed reply from QEMU."
            case .commandFailed(_, let message):
                return operation + " was rejected by QEMU: " + message
            }
        }

        return operation + " failed."
    }
}

private enum QEMURuntimeRecoveryError: Error {
    case result(QEMURuntimeRecoveryResult)

    var result: QEMURuntimeRecoveryResult {
        switch self {
        case .result(let result):
            result
        }
    }
}
