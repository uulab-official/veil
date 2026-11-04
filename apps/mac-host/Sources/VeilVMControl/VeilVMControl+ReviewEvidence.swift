import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    static func appRuntimeReviewCard(
        status report: WindowsAppRuntimeStatusReport,
        evidenceDirectoryPath: String?
    ) -> AppRuntimeReviewCard {
        let evidenceDirectoryURL = evidenceDirectoryPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        let screenshotSlots = report.releaseGate.screenshotSlots.map { slot in
            let expectedFileName = "\(slot.id).png"
            let attachmentURL = evidenceDirectoryURL?.appendingPathComponent(expectedFileName)
            let attachmentPath = attachmentURL?.path
            let attachmentMetadata = attachmentPath.flatMap(pngScreenshotMetadata(atPath:))
            let invalidAttachment = attachmentMetadata == nil
                ? attachmentPath.flatMap(invalidReviewScreenshotFile(atPath:))
                : nil
            let attachmentExists = attachmentMetadata != nil
            return AppRuntimeReviewScreenshotSlot(
                id: slot.id,
                title: slot.title,
                expectedSurface: slot.expectedSurface,
                expectedFileName: expectedFileName,
                attachmentState: attachmentExists ? "attached" : "missing",
                attachmentPath: attachmentExists ? attachmentPath : nil,
                attachmentIssueReason: invalidAttachment?.reason,
                invalidAttachmentPath: invalidAttachment?.path,
                attachmentByteCount: attachmentMetadata?.byteCount,
                attachmentWidth: attachmentMetadata?.width,
                attachmentHeight: attachmentMetadata?.height,
                invalidAttachmentByteCount: invalidAttachment?.byteCount,
                invalidAttachmentWidth: invalidAttachment?.width,
                invalidAttachmentHeight: invalidAttachment?.height
            )
        }
        let requiredScreenshotCount = report.releaseGate.screenshotSlots.filter(\.isRequired).count
        let attachedScreenshotCount = screenshotSlots.filter { $0.attachmentState == "attached" }.count
        let invalidScreenshotCount = screenshotSlots.filter { $0.attachmentIssueReason != nil }.count
        let areRequiredScreenshotsAttached = requiredScreenshotCount == attachedScreenshotCount
        let hostAppBundle = hostAppBundleEvidence()

        return AppRuntimeReviewCard(
            generatedAt: report.generatedAt,
            isReadyForReview: report.releaseGate.isPassing
                && hostAppBundle.isVerificationReady
                && areRequiredScreenshotsAttached,
            areRequiredScreenshotsAttached: areRequiredScreenshotsAttached,
            requiredScreenshotCount: requiredScreenshotCount,
            attachedScreenshotCount: attachedScreenshotCount,
            invalidScreenshotCount: invalidScreenshotCount,
            minimumScreenshotWidth: minimumReviewScreenshotWidth,
            minimumScreenshotHeight: minimumReviewScreenshotHeight,
            appFlowSummary: appRuntimeReviewSummary(
                releaseGate: report.releaseGate,
                hostAppBundle: hostAppBundle,
                requiredScreenshotCount: requiredScreenshotCount,
                attachedScreenshotCount: attachedScreenshotCount,
                invalidScreenshotCount: invalidScreenshotCount
            ),
            nextStepTitle: appRuntimeReviewNextStepTitle(
                releaseGate: report.releaseGate,
                hostAppBundle: hostAppBundle,
                areRequiredScreenshotsAttached: areRequiredScreenshotsAttached,
                invalidScreenshotCount: invalidScreenshotCount
            ),
            nextActionCommand: appRuntimeReviewNextCommand(
                releaseGate: report.releaseGate,
                hostAppBundle: hostAppBundle,
                areRequiredScreenshotsAttached: areRequiredScreenshotsAttached,
                evidenceDirectoryPath: evidenceDirectoryURL?.path
            ),
            launchOnboarding: report.launchOnboarding,
            detail: appRuntimeReviewDetail(
                releaseGate: report.releaseGate,
                hostAppBundle: hostAppBundle,
                requiredScreenshotCount: requiredScreenshotCount,
                attachedScreenshotCount: attachedScreenshotCount,
                invalidScreenshotCount: invalidScreenshotCount
            ),
            steps: report.releaseGate.steps.map { step in
                AppRuntimeReviewStep(
                    id: step.id,
                    title: step.title,
                    state: step.state,
                    isPassing: step.isPassing,
                    evidence: step.evidence,
                    nextActionCommand: step.nextActionCommand
                )
            },
            screenshotSlots: screenshotSlots,
            evidence: AppRuntimeReviewEvidence(
                latestAppCheckKind: report.proofArtifacts.latestProofKind,
                latestAppCheckPath: report.proofArtifacts.latestProofPath,
                latestAppCheckModifiedAt: report.proofArtifacts.latestProofModifiedAt,
                multiAppProofTargetAppIds: report.proofArtifacts.multiAppProofTargetAppIds,
                multiAppProofCoverageCount: report.proofArtifacts.multiAppProofCoverageCount,
                multiAppProofCoverageHealth: report.proofArtifacts.multiAppProofCoverageHealth,
                latestAppCheckLatencyHealth: report.proofArtifacts.latestProofLatencyHealth,
                latestAppCheckSlowestLatencyMeasurement: report.proofArtifacts.latestProofSlowestLatencyMeasurement,
                latestAppCheckSlowestLatencyMilliseconds: report.proofArtifacts.latestProofSlowestLatencyMilliseconds,
                latestAppCheckLatencyBudgetMilliseconds: report.proofArtifacts.latestProofLatencyBudgetMilliseconds,
                latestAppCheckStaleTimeoutMilliseconds: report.proofArtifacts.latestProofStaleTimeoutMilliseconds,
                latestAppCheckLatencyRecommendedAction: report.proofArtifacts.latestProofLatencyRecommendedAction,
                latestNotificationProofPath: report.proofArtifacts.latestNotificationProofPath,
                latestNotificationProofModifiedAt: report.proofArtifacts.latestNotificationProofModifiedAt,
                latestNotificationProofStatus: report.proofArtifacts.latestNotificationProofStatus,
                latestNotificationProofId: report.proofArtifacts.latestNotificationProofId,
                latestNotificationProofTitle: report.proofArtifacts.latestNotificationProofTitle,
                latestNotificationProofReceivedAt: report.proofArtifacts.latestNotificationProofReceivedAt,
                latestPrinterBridgeProofPath: report.proofArtifacts.latestPrinterBridgeProofPath,
                latestPrinterBridgeProofModifiedAt: report.proofArtifacts.latestPrinterBridgeProofModifiedAt,
                latestPrinterBridgeProofStatus: report.proofArtifacts.latestPrinterBridgeProofStatus,
                latestPrinterBridgeProofEvidencePath: report.proofArtifacts.latestPrinterBridgeProofEvidencePath,
                latestPrinterBridgeProofEvidenceFileName: report.proofArtifacts.latestPrinterBridgeProofEvidenceFileName,
                latestPrinterBridgeProofEvidenceByteCount: report.proofArtifacts.latestPrinterBridgeProofEvidenceByteCount,
                latestPrinterBridgeProofEvidenceModifiedAt: report.proofArtifacts.latestPrinterBridgeProofEvidenceModifiedAt,
                latestPrinterBridgeProofIppEndpoint: report.proofArtifacts.latestPrinterBridgeProofIppEndpoint,
                dailyUsePackageIdentityReady: report.dailyUseReadiness.packageIdentityReady,
                dailyUseBorderlessCapturePreflightPassed: report.dailyUseReadiness.borderlessCapturePreflightPassed,
                dailyUseNotificationBridgePreflightPassed: report.dailyUseReadiness.notificationBridgePreflightPassed,
                dailyUseRecommendedAction: report.dailyUseReadiness.recommendedAction,
                dailyUseRecommendedCommand: report.dailyUseReadiness.recommendedCommand,
                dailyUseReason: report.dailyUseReadiness.reason,
                dailyUsePackageIdentityStage: report.dailyUseReadiness.packageIdentityStage,
                dailyUsePackageIdentitySucceeded: report.dailyUseReadiness.packageIdentitySucceeded,
                dailyUsePackageIdentityEvidencePath: report.dailyUseReadiness.packageIdentityEvidencePath,
                diagnosticsDirectory: report.proofArtifacts.diagnosticsDirectory,
                screenshotEvidenceDirectory: evidenceDirectoryURL?.path,
                recommendedAppCheckCommand: report.proofPlan.recommendedProofCommand,
                hostAppBundle: hostAppBundle
            ),
            statusCommand: "veil-vmctl app-runtime-status --json",
            status: report
        )
    }

    private static func appRuntimeReviewSummary(
        releaseGate: WindowsAppRuntimeReleaseGateStatus,
        hostAppBundle: AppRuntimeReviewHostAppBundleEvidence,
        requiredScreenshotCount: Int,
        attachedScreenshotCount: Int,
        invalidScreenshotCount: Int
    ) -> String {
        guard hostAppBundle.isVerificationReady else {
            return "\(appFlowSummary(releaseGate)); host app bundle needs verification"
        }
        guard invalidScreenshotCount == 0 else {
            return "\(appFlowSummary(releaseGate)); review screenshots \(attachedScreenshotCount)/\(requiredScreenshotCount) attached; \(invalidScreenshotCount) invalid"
        }
        guard requiredScreenshotCount == attachedScreenshotCount else {
            return "\(appFlowSummary(releaseGate)); review screenshots \(attachedScreenshotCount)/\(requiredScreenshotCount) attached"
        }

        return appFlowSummary(releaseGate)
    }

    private static func appRuntimeReviewNextStepTitle(
        releaseGate: WindowsAppRuntimeReleaseGateStatus,
        hostAppBundle: AppRuntimeReviewHostAppBundleEvidence,
        areRequiredScreenshotsAttached: Bool,
        invalidScreenshotCount: Int
    ) -> String {
        if releaseGate.isPassing && !hostAppBundle.isVerificationReady {
            return "Verify Host App Bundle"
        }
        if releaseGate.isPassing && invalidScreenshotCount > 0 {
            return "Replace Review Screenshots"
        }
        if releaseGate.isPassing && !areRequiredScreenshotsAttached {
            return "Attach Review Screenshots"
        }

        return appFlowNextStepTitle(releaseGate)
    }

    private static func appRuntimeReviewNextCommand(
        releaseGate: WindowsAppRuntimeReleaseGateStatus,
        hostAppBundle: AppRuntimeReviewHostAppBundleEvidence,
        areRequiredScreenshotsAttached: Bool,
        evidenceDirectoryPath: String?
    ) -> String? {
        if releaseGate.isPassing && !hostAppBundle.isVerificationReady {
            return hostAppBundle.verificationCommand
        }
        if releaseGate.isPassing,
           !areRequiredScreenshotsAttached,
           let evidenceDirectoryPath {
            return appRuntimeReviewVerifyCommand(evidenceDirectory: evidenceDirectoryPath)
        }

        return appFlowNextCommand(releaseGate)
    }

    private static func appRuntimeReviewDetail(
        releaseGate: WindowsAppRuntimeReleaseGateStatus,
        hostAppBundle: AppRuntimeReviewHostAppBundleEvidence,
        requiredScreenshotCount: Int,
        attachedScreenshotCount: Int,
        invalidScreenshotCount: Int
    ) -> String {
        let releaseGateDetail = appFlowDetail(releaseGate)
        guard !hostAppBundle.isVerificationReady else {
            guard invalidScreenshotCount == 0 else {
                return "\(releaseGateDetail) Replace \(invalidScreenshotCount) invalid review screenshot\(invalidScreenshotCount == 1 ? "" : "s") before sharing evidence."
            }
            guard requiredScreenshotCount != attachedScreenshotCount else {
                return releaseGateDetail
            }
            return "\(releaseGateDetail) Attach all \(requiredScreenshotCount) review screenshots before sharing evidence."
        }

        if invalidScreenshotCount > 0 {
            return "\(releaseGateDetail) Run bundled launcher verification and replace \(invalidScreenshotCount) invalid review screenshot\(invalidScreenshotCount == 1 ? "" : "s") before sharing evidence."
        }
        if requiredScreenshotCount != attachedScreenshotCount {
            return "\(releaseGateDetail) Run bundled launcher verification and attach all \(requiredScreenshotCount) review screenshots before sharing evidence."
        }

        return "\(releaseGateDetail) Run bundled launcher verification before sharing review evidence."
    }

    private static func hostAppBundleEvidence() -> AppRuntimeReviewHostAppBundleEvidence {
        let rootURL = projectRootDirectory()
        let distURL = rootURL.appendingPathComponent("dist", isDirectory: true)
        let appBundleURL = distURL.appendingPathComponent("Veil.app", isDirectory: true)
        let infoPlistURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let executableURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("veil-host-shell")
        let iconURL = appBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("VeilAppIcon.icns")
        let expectedBundleIdentifier = "org.uulab.veil.host-shell"
        let bundleIdentifier = bundleIdentifier(in: infoPlistURL)
        let latestFailedReport = latestLaunchVerificationFailureReport(in: distURL)
        let latestBundleModifiedAt = latestModificationDate(
            for: [infoPlistURL, executableURL, iconURL]
        )
        let latestLaunchReport = latestLaunchVerificationReport(
            in: distURL,
            expectedBundleIdentifier: expectedBundleIdentifier,
            latestBundleModifiedAt: latestBundleModifiedAt
        )

        let isBundlePresent = directoryExists(at: appBundleURL)
        let infoPlistExists = FileManager.default.fileExists(atPath: infoPlistURL.path)
        let executableExists = FileManager.default.isExecutableFile(atPath: executableURL.path)
        let iconExists = FileManager.default.fileExists(atPath: iconURL.path)

        return AppRuntimeReviewHostAppBundleEvidence(
            verificationCommand: "./script/build_and_run.sh --verify",
            appBundlePath: appBundleURL.path,
            isStagedBundlePresent: isBundlePresent,
            infoPlistExists: infoPlistExists,
            executableExists: executableExists,
            appIconExists: iconExists,
            bundleIdentifier: bundleIdentifier,
            expectedBundleIdentifier: expectedBundleIdentifier,
            latestLaunchReport: latestLaunchReport,
            latestFailedLaunchReportPath: latestFailedReport?.url.path,
            latestFailedLaunchReportModifiedAt: latestFailedReport?.modifiedAt,
            isVerificationReady: isBundlePresent
                && infoPlistExists
                && executableExists
                && iconExists
                && bundleIdentifier == expectedBundleIdentifier
                && latestLaunchReport.meetsLauncherContract
                && latestLaunchReport.isCurrentForBundle
                && latestLaunchReport.bundleIdentifier == expectedBundleIdentifier
        )
    }

    private static func projectRootDirectory() -> URL {
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .standardizedFileURL

        while true {
            let scriptURL = candidate
                .appendingPathComponent("script", isDirectory: true)
                .appendingPathComponent("build_and_run.sh")
            if FileManager.default.isExecutableFile(atPath: scriptURL.path) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
            }
            candidate = parent
        }
    }

    private static func bundleIdentifier(in infoPlistURL: URL) -> String? {
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }

        return dictionary["CFBundleIdentifier"] as? String
    }

    private static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func isPNGFile(atPath path: String) -> Bool {
        pngScreenshotMetadata(atPath: path) != nil
    }

    static func invalidReviewScreenshotFile(atPath path: String) -> AppRuntimeReviewInvalidScreenshotFile? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return AppRuntimeReviewInvalidScreenshotFile(
                path: path,
                reason: "unreadableFile",
                byteCount: nil,
                width: nil,
                height: nil,
                minimumWidth: minimumReviewScreenshotWidth,
                minimumHeight: minimumReviewScreenshotHeight
            )
        }
        guard data.count >= pngIHDRMinimumByteCount,
              data.prefix(pngSignature.count).elementsEqual(pngSignature),
              String(data: data[12..<16], encoding: .ascii) == "IHDR" else {
            return AppRuntimeReviewInvalidScreenshotFile(
                path: path,
                reason: "notValidPNG",
                byteCount: data.count,
                width: nil,
                height: nil,
                minimumWidth: minimumReviewScreenshotWidth,
                minimumHeight: minimumReviewScreenshotHeight
            )
        }

        let width = readPNGUInt32(data, offset: 16)
        let height = readPNGUInt32(data, offset: 20)
        guard width >= minimumReviewScreenshotWidth,
              height >= minimumReviewScreenshotHeight else {
            return AppRuntimeReviewInvalidScreenshotFile(
                path: path,
                reason: "belowMinimumDimensions",
                byteCount: data.count,
                width: width,
                height: height,
                minimumWidth: minimumReviewScreenshotWidth,
                minimumHeight: minimumReviewScreenshotHeight
            )
        }

        return nil
    }

    static func appRuntimeReviewAppCheckProofEvidence(
        file: AppRuntimeReviewAppCheckProofFile
    ) -> AppRuntimeReviewAppCheckProofEvidence {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return AppRuntimeReviewAppCheckProofEvidence(
                expectedFileName: file.expectedFileName,
                path: file.path,
                command: file.command,
                requiredKind: file.requiredKind,
                requiredStatus: file.requiredStatus,
                exists: false,
                isValid: false,
                kind: nil,
                status: nil,
                appId: nil,
                issueReason: "missing"
            )
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                return appRuntimeReviewInvalidAppCheckProofEvidence(file: file, reason: "notObject")
            }

            let kind = dictionary["kind"] as? String
            let status = dictionary["status"] as? String
            let appId = dictionary["appId"] as? String
            let issueReason: String?
            if kind != file.requiredKind {
                issueReason = "wrongKind"
            } else if status != file.requiredStatus {
                issueReason = "notProved"
            } else {
                issueReason = nil
            }

            return AppRuntimeReviewAppCheckProofEvidence(
                expectedFileName: file.expectedFileName,
                path: file.path,
                command: file.command,
                requiredKind: file.requiredKind,
                requiredStatus: file.requiredStatus,
                exists: true,
                isValid: issueReason == nil,
                kind: kind,
                status: status,
                appId: appId,
                issueReason: issueReason
            )
        } catch {
            return appRuntimeReviewInvalidAppCheckProofEvidence(file: file, reason: "notValidJSON")
        }
    }

    private static func appRuntimeReviewInvalidAppCheckProofEvidence(
        file: AppRuntimeReviewAppCheckProofFile,
        reason: String
    ) -> AppRuntimeReviewAppCheckProofEvidence {
        AppRuntimeReviewAppCheckProofEvidence(
            expectedFileName: file.expectedFileName,
            path: file.path,
            command: file.command,
            requiredKind: file.requiredKind,
            requiredStatus: file.requiredStatus,
            exists: true,
            isValid: false,
            kind: nil,
            status: nil,
            appId: nil,
            issueReason: reason
        )
    }

    static func appRuntimeReviewNotificationProofEvidence(
        card: AppRuntimeReviewCard
    ) -> AppRuntimeReviewNotificationProofEvidence? {
        guard let path = card.evidence.latestNotificationProofPath else {
            return nil
        }

        let requiredKind = "windowsNotificationProof"
        let requiredStatus = "proved"
        let command = "veil-vmctl notification-proof --json --require-proved --output \(shellQuoted(path))"
        guard FileManager.default.fileExists(atPath: path) else {
            return AppRuntimeReviewNotificationProofEvidence(
                path: path,
                command: command,
                requiredKind: requiredKind,
                requiredStatus: requiredStatus,
                exists: false,
                isValid: false,
                kind: nil,
                status: nil,
                notificationId: nil,
                title: nil,
                receivedAt: nil,
                issueReason: "missing"
            )
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                return appRuntimeReviewInvalidNotificationProofEvidence(
                    path: path,
                    command: command,
                    reason: "notObject"
                )
            }

            let kind = dictionary["kind"] as? String
            let status = dictionary["status"] as? String
            let notification = dictionary["notification"] as? [String: Any]
            let notificationId = notification?["notificationId"] as? String
            let title = notification?["title"] as? String
            let receivedAt = (notification?["receivedAt"] as? String).flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
            let issueReason: String?
            if kind != requiredKind {
                issueReason = "wrongKind"
            } else if status != requiredStatus {
                issueReason = "notProved"
            } else if notificationId != card.evidence.latestNotificationProofId
                || title != card.evidence.latestNotificationProofTitle
                || receivedAt != card.evidence.latestNotificationProofReceivedAt {
                issueReason = "notificationMismatch"
            } else {
                issueReason = nil
            }

            return AppRuntimeReviewNotificationProofEvidence(
                path: path,
                command: command,
                requiredKind: requiredKind,
                requiredStatus: requiredStatus,
                exists: true,
                isValid: issueReason == nil,
                kind: kind,
                status: status,
                notificationId: notificationId,
                title: title,
                receivedAt: receivedAt,
                issueReason: issueReason
            )
        } catch {
            return appRuntimeReviewInvalidNotificationProofEvidence(
                path: path,
                command: command,
                reason: "notValidJSON"
            )
        }
    }

    private static func appRuntimeReviewInvalidNotificationProofEvidence(
        path: String,
        command: String,
        reason: String
    ) -> AppRuntimeReviewNotificationProofEvidence {
        AppRuntimeReviewNotificationProofEvidence(
            path: path,
            command: command,
            requiredKind: "windowsNotificationProof",
            requiredStatus: "proved",
            exists: true,
            isValid: false,
            kind: nil,
            status: nil,
            notificationId: nil,
            title: nil,
            receivedAt: nil,
            issueReason: reason
        )
    }

    static func appRuntimeReviewPrinterBridgeProofEvidence(
        card: AppRuntimeReviewCard
    ) -> AppRuntimeReviewPrinterBridgeProofEvidence? {
        guard let path = card.evidence.latestPrinterBridgeProofPath else {
            return nil
        }

        let requiredKind = "windowsPrinterBridgeProof"
        let requiredStatus = "proved"
        guard FileManager.default.fileExists(atPath: path) else {
            return AppRuntimeReviewPrinterBridgeProofEvidence(
                path: path,
                requiredKind: requiredKind,
                requiredStatus: requiredStatus,
                exists: false,
                isValid: false,
                kind: nil,
                status: nil,
                evidencePath: nil,
                evidenceFileName: nil,
                evidenceByteCount: nil,
                ippEndpoint: nil,
                issueReason: "missing"
            )
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                return appRuntimeReviewInvalidPrinterBridgeProofEvidence(path: path, reason: "notObject")
            }

            let kind = dictionary["kind"] as? String
            let status = dictionary["status"] as? String
            let evidencePath = dictionary["evidencePath"] as? String
            let evidenceFileName = dictionary["evidenceFileName"] as? String
            let evidenceByteCount = (dictionary["evidenceByteCount"] as? NSNumber)?.intValue
            let plan = dictionary["plan"] as? [String: Any]
            let ippEndpoint = plan?["ippEndpoint"] as? String
            let issueReason: String?
            if kind != requiredKind {
                issueReason = "wrongKind"
            } else if status != requiredStatus {
                issueReason = "notProved"
            } else if evidencePath != card.evidence.latestPrinterBridgeProofEvidencePath
                || evidenceFileName != card.evidence.latestPrinterBridgeProofEvidenceFileName
                || evidenceByteCount != card.evidence.latestPrinterBridgeProofEvidenceByteCount {
                issueReason = "evidenceMismatch"
            } else if ippEndpoint != card.evidence.latestPrinterBridgeProofIppEndpoint
                || ippEndpoint?.hasPrefix("http://10.0.2.2:631/printers/") != true {
                issueReason = "endpointMismatch"
            } else {
                issueReason = nil
            }

            return AppRuntimeReviewPrinterBridgeProofEvidence(
                path: path,
                requiredKind: requiredKind,
                requiredStatus: requiredStatus,
                exists: true,
                isValid: issueReason == nil,
                kind: kind,
                status: status,
                evidencePath: evidencePath,
                evidenceFileName: evidenceFileName,
                evidenceByteCount: evidenceByteCount,
                ippEndpoint: ippEndpoint,
                issueReason: issueReason
            )
        } catch {
            return appRuntimeReviewInvalidPrinterBridgeProofEvidence(path: path, reason: "notValidJSON")
        }
    }

    private static func appRuntimeReviewInvalidPrinterBridgeProofEvidence(
        path: String,
        reason: String
    ) -> AppRuntimeReviewPrinterBridgeProofEvidence {
        AppRuntimeReviewPrinterBridgeProofEvidence(
            path: path,
            requiredKind: "windowsPrinterBridgeProof",
            requiredStatus: "proved",
            exists: true,
            isValid: false,
            kind: nil,
            status: nil,
            evidencePath: nil,
            evidenceFileName: nil,
            evidenceByteCount: nil,
            ippEndpoint: nil,
            issueReason: reason
        )
    }

    private static func pngScreenshotMetadata(atPath path: String) -> (byteCount: Int, width: Int, height: Int)? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]),
              data.count >= pngIHDRMinimumByteCount,
              data.prefix(pngSignature.count).elementsEqual(pngSignature),
              String(data: data[12..<16], encoding: .ascii) == "IHDR" else {
            return nil
        }

        let width = readPNGUInt32(data, offset: 16)
        let height = readPNGUInt32(data, offset: 20)
        guard width >= minimumReviewScreenshotWidth,
              height >= minimumReviewScreenshotHeight else {
            return nil
        }

        return (byteCount: data.count, width: width, height: height)
    }

    private static func readPNGUInt32(_ data: Data, offset: Int) -> Int {
        data[offset..<(offset + 4)].reduce(0) { result, byte in
            (result << 8) | Int(byte)
        }
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let pngIHDRMinimumByteCount = 24
    static let minimumReviewScreenshotWidth = 640
    static let minimumReviewScreenshotHeight = 360
}
