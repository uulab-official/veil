import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import VeilHostCore

extension VeilVMControl {
    @MainActor
    static func printAppRuntimeReview(
        json: Bool,
        demo: Bool,
        evidenceDirectoryPath: String?
    ) async throws {
        let report = try await appRuntimeStatusReport(demo: demo)
        let card = appRuntimeReviewCard(
            status: report,
            evidenceDirectoryPath: evidenceDirectoryPath
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(card)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Veil Windows App Review Card")
        print("App flow: \(card.appFlowSummary)")
        print("Screenshots: \(card.attachedScreenshotCount)/\(card.requiredScreenshotCount) attached")
        if card.invalidScreenshotCount > 0 {
            print("Invalid screenshots: \(card.invalidScreenshotCount)")
        }
        print("Launch onboarding: \(card.launchOnboarding.state)")
        print("Launch step: \(card.launchOnboarding.currentStepTitle)")
        print("Continue in app: \(card.launchOnboarding.canContinueInApp ? "yes" : "no")")
        print("Next step: \(card.nextStepTitle)")
        print("Detail: \(card.detail)")
        if let nextActionCommand = card.nextActionCommand {
            print("Next command: \(nextActionCommand)")
        }
        print("Status command: \(card.statusCommand)")
        print("")
        print("Steps:")
        for step in card.steps {
            let marker = step.isPassing ? "[x]" : "[ ]"
            print("  \(marker) \(step.title) - \(step.state)")
            print("      \(step.evidence)")
            if let nextActionCommand = step.nextActionCommand, !step.isPassing {
                print("      Next: \(nextActionCommand)")
            }
        }
        print("")
        print("Screenshots to attach:")
        for slot in card.screenshotSlots {
            print("  - \(slot.title): \(slot.attachmentState)")
            print("      File: \(slot.expectedFileName)")
            if let attachmentPath = slot.attachmentPath {
                print("      Attached: \(attachmentPath)")
            }
            if let attachmentIssueReason = slot.attachmentIssueReason {
                print("      Issue: \(attachmentIssueReason)")
            }
            if let invalidAttachmentPath = slot.invalidAttachmentPath {
                print("      Invalid file: \(invalidAttachmentPath)")
            }
            print("      Expected: \(slot.expectedSurface)")
        }
        print("")
        print("Evidence:")
        print("  Diagnostics: \(card.evidence.diagnosticsDirectory)")
        if let screenshotEvidenceDirectory = card.evidence.screenshotEvidenceDirectory {
            print("  Screenshots: \(screenshotEvidenceDirectory)")
        }
        if let latestKind = card.evidence.latestAppCheckKind {
            print("  Latest app check: \(latestKind)")
        }
        if let latestPath = card.evidence.latestAppCheckPath {
            print("  Latest app check file: \(latestPath)")
        }
        if let notificationProofPath = card.evidence.latestNotificationProofPath {
            print("  Latest notification proof file: \(notificationProofPath)")
        }
        if let notificationProofStatus = card.evidence.latestNotificationProofStatus {
            print("  Latest notification proof: \(notificationProofStatus)")
        }
        if let notificationProofTitle = card.evidence.latestNotificationProofTitle {
            print("  Latest notification title: \(notificationProofTitle)")
        }
        if let printerProofPath = card.evidence.latestPrinterBridgeProofPath {
            print("  Latest printer proof file: \(printerProofPath)")
        }
        if let printerProofStatus = card.evidence.latestPrinterBridgeProofStatus {
            print("  Latest printer proof: \(printerProofStatus)")
        }
        if let printerProofEvidence = card.evidence.latestPrinterBridgeProofEvidenceFileName {
            print("  Latest printer evidence: \(printerProofEvidence)")
        }
        print("  Daily Use package identity: \(card.evidence.dailyUsePackageIdentityReady ? "ready" : "needed")")
        print("  Daily Use borderless capture: \(card.evidence.dailyUseBorderlessCapturePreflightPassed ? "ready" : "blocked")")
        print("  Daily Use notifications: \(card.evidence.dailyUseNotificationBridgePreflightPassed ? "ready" : "blocked")")
        print("  Daily Use action: \(card.evidence.dailyUseRecommendedAction)")
        if let dailyUseCommand = card.evidence.dailyUseRecommendedCommand {
            print("  Daily Use command: \(dailyUseCommand)")
        }
        if let packageIdentityStage = card.evidence.dailyUsePackageIdentityStage {
            print("  Daily Use package identity stage: \(packageIdentityStage)")
        }
        if let packageIdentitySucceeded = card.evidence.dailyUsePackageIdentitySucceeded {
            print("  Daily Use package identity status: \(packageIdentitySucceeded ? "succeeded" : "not complete")")
        }
        if let packageIdentityEvidencePath = card.evidence.dailyUsePackageIdentityEvidencePath {
            print("  Daily Use package identity evidence: \(packageIdentityEvidencePath)")
        }
        print("  Daily Use reason: \(card.evidence.dailyUseReason)")
        if let coverageHealth = card.evidence.multiAppProofCoverageHealth,
           let coverageCount = card.evidence.multiAppProofCoverageCount,
           let targetCount = card.evidence.multiAppProofTargetAppIds?.count {
            print("  App check coverage: \(coverageHealth) (\(coverageCount)/\(targetCount))")
        }
        if let latestLatencyHealth = card.evidence.latestAppCheckLatencyHealth {
            print("  Latest app check latency: \(latestLatencyHealth)")
        }
        if let latestLatencyMilliseconds = card.evidence.latestAppCheckSlowestLatencyMilliseconds,
           let latestLatencyMeasurement = card.evidence.latestAppCheckSlowestLatencyMeasurement {
            print("  Slowest app check latency: \(latestLatencyMeasurement) \(latestLatencyMilliseconds)ms")
        }
        if let recommendedCommand = card.evidence.recommendedAppCheckCommand {
            print("  Recommended app check: \(recommendedCommand)")
        }
        print("  Host app bundle: \(card.evidence.hostAppBundle.isVerificationReady ? "ready" : "needs verification")")
        print("      Verify: \(card.evidence.hostAppBundle.verificationCommand)")
        print("      Bundle: \(card.evidence.hostAppBundle.appBundlePath)")
        if let latestFailedReport = card.evidence.hostAppBundle.latestFailedLaunchReportPath {
            print("      Latest failed launch report: \(latestFailedReport)")
        }
    }

    @MainActor
    static func initAppRuntimeReview(
        json: Bool,
        demo: Bool,
        evidenceDirectoryPath: String?
    ) async throws {
        let report = try await appRuntimeStatusReport(demo: demo)
        let evidenceDirectoryURL = try appRuntimeReviewEvidenceDirectory(
            requestedPath: evidenceDirectoryPath,
            diagnosticsDirectory: report.proofArtifacts.diagnosticsDirectory
        )
        try FileManager.default.createDirectory(
            at: evidenceDirectoryURL,
            withIntermediateDirectories: true
        )

        let card = appRuntimeReviewCard(
            status: report,
            evidenceDirectoryPath: evidenceDirectoryURL.path
        )
        let manifestURL = evidenceDirectoryURL.appendingPathComponent("review-manifest.json")
        let readmeURL = evidenceDirectoryURL.appendingPathComponent("README.md")
        let reviewCommand = appRuntimeReviewCommand(evidenceDirectory: evidenceDirectoryURL.path)
        let verifyCommand = appRuntimeReviewVerifyCommand(evidenceDirectory: evidenceDirectoryURL.path)
        let openEvidenceDirectoryCommand = appRuntimeReviewOpenCommand(evidenceDirectory: evidenceDirectoryURL.path)
        let appCheckProofFile = appRuntimeReviewAppCheckProofFile(
            evidenceDirectory: evidenceDirectoryURL.path,
            recommendedCommand: card.evidence.recommendedAppCheckCommand
        )
        let screenshotFiles = card.screenshotSlots.map { slot in
            AppRuntimeReviewEvidenceFile(
                slotId: slot.id,
                title: slot.title,
                expectedFileName: slot.expectedFileName,
                path: evidenceDirectoryURL.appendingPathComponent(slot.expectedFileName).path,
                expectedSurface: slot.expectedSurface
            )
        }
        let manifest = AppRuntimeReviewEvidenceManifest(
            generatedAt: report.generatedAt,
            evidenceDirectory: evidenceDirectoryURL.path,
            manifestPath: manifestURL.path,
            readmePath: readmeURL.path,
            requiredScreenshotCount: card.requiredScreenshotCount,
            minimumScreenshotWidth: minimumReviewScreenshotWidth,
            minimumScreenshotHeight: minimumReviewScreenshotHeight,
            screenshotFiles: screenshotFiles,
            appCheckProofFile: appCheckProofFile,
            captureSteps: appRuntimeReviewCaptureSteps(
                screenshotFiles: screenshotFiles,
                appCheckProofFile: appCheckProofFile,
                card: card
            ),
            reviewCommand: reviewCommand,
            verifyCommand: verifyCommand,
            openEvidenceDirectoryCommand: openEvidenceDirectoryCommand,
            nextActions: appRuntimeReviewManifestNextActions(
                reviewCommand: reviewCommand,
                verifyCommand: verifyCommand,
                openEvidenceDirectoryCommand: openEvidenceDirectoryCommand
            )
        )
        let data = try JSONEncoder.veilDiagnostics.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic])
        let readmeData = Data(appRuntimeReviewEvidenceReadme(manifest: manifest).utf8)
        try readmeData.write(to: readmeURL, options: [.atomic])

        if json {
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Veil Windows App Review Evidence")
        print("Folder: \(manifest.evidenceDirectory)")
        print("Manifest: \(manifest.manifestPath)")
        print("Guide: \(manifest.readmePath)")
        print("Screenshots needed: \(manifest.requiredScreenshotCount)")
        print("Open folder: \(manifest.openEvidenceDirectoryCommand)")
        for file in manifest.screenshotFiles {
            print("  - \(file.expectedFileName): \(file.title)")
        }
        print("Capture steps:")
        for step in manifest.captureSteps {
            print("  \(step.order). \(step.title) -> \(step.expectedFileName)")
            print("     \(step.instruction)")
            print("     Capture: \(step.captureCommand)")
            if let supportingCommand = step.supportingCommand {
                print("     Command: \(supportingCommand)")
            }
        }
        print("Review command: \(manifest.reviewCommand)")
        print("Verify command: \(manifest.verifyCommand)")
    }

    @MainActor
    static func verifyAppRuntimeReview(
        json: Bool,
        demo: Bool,
        evidenceDirectoryPath: String
    ) async throws {
        let report = try await appRuntimeStatusReport(demo: demo)
        let evidenceDirectoryURL = URL(fileURLWithPath: evidenceDirectoryPath).standardizedFileURL
        let manifestURL = evidenceDirectoryURL.appendingPathComponent("review-manifest.json")
        let readmeURL = evidenceDirectoryURL.appendingPathComponent("README.md")
        let manifest: AppRuntimeReviewEvidenceManifest?
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            let decodedManifest = try JSONDecoder.veilDiagnostics.decode(AppRuntimeReviewEvidenceManifest.self, from: data)
            manifest = appRuntimeReviewManifestWithCurrentCommands(
                decodedManifest,
                evidenceDirectory: evidenceDirectoryURL.path
            )
        } else {
            manifest = nil
        }
        let card = appRuntimeReviewCard(
            status: report,
            evidenceDirectoryPath: evidenceDirectoryURL.path
        )
        let expectedFiles = manifest?.screenshotFiles.map(\.path)
            ?? card.screenshotSlots.map { evidenceDirectoryURL.appendingPathComponent($0.expectedFileName).path }
        let reviewCommand = manifest?.reviewCommand
            ?? appRuntimeReviewCommand(evidenceDirectory: evidenceDirectoryURL.path)
        let verifyCommand = manifest?.verifyCommand
            ?? appRuntimeReviewVerifyCommand(evidenceDirectory: evidenceDirectoryURL.path)
        let openEvidenceDirectoryCommand = manifest?.openEvidenceDirectoryCommand
            ?? appRuntimeReviewOpenCommand(evidenceDirectory: evidenceDirectoryURL.path)
        let appCheckProofFile = manifest?.appCheckProofFile
            ?? appRuntimeReviewAppCheckProofFile(
                evidenceDirectory: evidenceDirectoryURL.path,
                recommendedCommand: card.evidence.recommendedAppCheckCommand
            )
        let captureSteps = manifest?.captureSteps
            ?? appRuntimeReviewCaptureSteps(
                screenshotFiles: card.screenshotSlots.map { slot in
                    AppRuntimeReviewEvidenceFile(
                        slotId: slot.id,
                        title: slot.title,
                        expectedFileName: slot.expectedFileName,
                        path: evidenceDirectoryURL.appendingPathComponent(slot.expectedFileName).path,
                        expectedSurface: slot.expectedSurface
                    )
                },
                appCheckProofFile: appCheckProofFile,
                card: card
            )
        let missingFiles = expectedFiles.filter { !isPNGFile(atPath: $0) }
        let absentFiles = expectedFiles.filter { !FileManager.default.fileExists(atPath: $0) }
        let invalidScreenshotFiles = expectedFiles.compactMap { invalidReviewScreenshotFile(atPath: $0) }
        let attachedScreenshotCount = expectedFiles.count - missingFiles.count
        let missingCaptureSteps = appRuntimeReviewMissingCaptureSteps(
            expectedFiles: expectedFiles,
            captureSteps: captureSteps,
            missingFiles: missingFiles
        )
        let invalidCaptureSteps = appRuntimeReviewMissingCaptureSteps(
            expectedFiles: expectedFiles,
            captureSteps: captureSteps,
            missingFiles: invalidScreenshotFiles.map(\.path)
        )
        let screenshotEvidenceSummary = appRuntimeReviewScreenshotEvidenceSummary(
            requiredScreenshotCount: expectedFiles.count,
            validScreenshotCount: attachedScreenshotCount,
            missingScreenshotCount: absentFiles.count,
            invalidScreenshotCount: invalidScreenshotFiles.count,
            pendingScreenshotCount: missingFiles.count,
            invalidCaptureSteps: invalidCaptureSteps,
            missingCaptureSteps: missingCaptureSteps
        )
        let appCheckProof = appRuntimeReviewAppCheckProofEvidence(file: appCheckProofFile)
        let notificationProof = appRuntimeReviewNotificationProofEvidence(card: card)
        let printerBridgeProof = appRuntimeReviewPrinterBridgeProofEvidence(card: card)
        let nextEvidenceAction = appRuntimeReviewNextEvidenceAction(
            invalidCaptureSteps: invalidCaptureSteps,
            missingCaptureSteps: missingCaptureSteps,
            appCheckProof: appCheckProof,
            notificationProof: notificationProof,
            printerBridgeProof: printerBridgeProof,
            openEvidenceDirectoryCommand: openEvidenceDirectoryCommand
        )
        let verification = AppRuntimeReviewEvidenceVerification(
            generatedAt: report.generatedAt,
            evidenceDirectory: evidenceDirectoryURL.path,
            manifestPath: manifestURL.path,
            readmePath: readmeURL.path,
            manifestExists: manifest != nil,
            readmeExists: FileManager.default.fileExists(atPath: readmeURL.path),
            requiredScreenshotCount: expectedFiles.count,
            attachedScreenshotCount: attachedScreenshotCount,
            minimumScreenshotWidth: minimumReviewScreenshotWidth,
            minimumScreenshotHeight: minimumReviewScreenshotHeight,
            isComplete: manifest != nil
                && FileManager.default.fileExists(atPath: readmeURL.path)
                && missingFiles.isEmpty
                && appCheckProof.isValid
                && (notificationProof?.isValid ?? true)
                && (printerBridgeProof?.isValid ?? true)
                && card.areRequiredScreenshotsAttached,
            missingFiles: missingFiles,
            invalidScreenshotFiles: invalidScreenshotFiles,
            appCheckProof: appCheckProof,
            notificationProof: notificationProof,
            printerBridgeProof: printerBridgeProof,
            screenshotEvidenceSummary: screenshotEvidenceSummary,
            nextEvidenceAction: nextEvidenceAction,
            invalidCaptureSteps: invalidCaptureSteps,
            nextInvalidCaptureStep: invalidCaptureSteps.first,
            missingCaptureSteps: missingCaptureSteps,
            nextMissingCaptureStep: missingCaptureSteps.first,
            review: card,
            manifest: manifest,
            reviewCommand: reviewCommand,
            verifyCommand: verifyCommand,
            openEvidenceDirectoryCommand: openEvidenceDirectoryCommand,
            nextActions: appRuntimeReviewVerificationNextActions(
                evidenceDirectory: evidenceDirectoryURL.path,
                manifestExists: manifest != nil,
                readmeExists: FileManager.default.fileExists(atPath: readmeURL.path),
                invalidScreenshotFiles: invalidScreenshotFiles,
                appCheckProof: appCheckProof,
                notificationProof: notificationProof,
                printerBridgeProof: printerBridgeProof,
                invalidCaptureSteps: invalidCaptureSteps,
                missingCaptureSteps: missingCaptureSteps,
                reviewCommand: reviewCommand,
                verifyCommand: verifyCommand,
                openEvidenceDirectoryCommand: openEvidenceDirectoryCommand
            )
        )

        if json {
            let data = try JSONEncoder.veilDiagnostics.encode(verification)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        print("Veil Windows App Review Verification")
        print("Folder: \(verification.evidenceDirectory)")
        print("Manifest: \(verification.manifestExists ? "present" : "missing")")
        print("Guide: \(verification.readmeExists ? "present" : "missing")")
        print("Screenshots: \(verification.attachedScreenshotCount)/\(verification.requiredScreenshotCount) attached")
        print("Screenshot evidence: \(verification.screenshotEvidenceSummary.state)")
        print("App check proof: \(verification.appCheckProof.isValid ? "proved" : (verification.appCheckProof.issueReason ?? "missing"))")
        if let notificationProof = verification.notificationProof {
            print("Notification proof: \(notificationProof.isValid ? "proved" : (notificationProof.issueReason ?? "missing"))")
        }
        if let printerBridgeProof = verification.printerBridgeProof {
            print("Printer bridge proof: \(printerBridgeProof.isValid ? "proved" : (printerBridgeProof.issueReason ?? "missing"))")
        }
        print("Next evidence action: \(verification.nextEvidenceAction.title)")
        print("Next evidence command: \(verification.nextEvidenceAction.command)")
        print("Complete: \(verification.isComplete ? "yes" : "no")")
        print("Open folder: \(verification.openEvidenceDirectoryCommand)")
        if !verification.missingFiles.isEmpty {
            print("Missing files:")
            for file in verification.missingFiles {
                print("  - \(file)")
            }
        }
        if let nextInvalidCaptureStep = verification.nextInvalidCaptureStep {
            print("Next replacement:")
            print("  \(nextInvalidCaptureStep.order). \(nextInvalidCaptureStep.title) -> \(nextInvalidCaptureStep.expectedFileName)")
            print("     Capture: \(nextInvalidCaptureStep.captureCommand)")
        }
        if let nextMissingCaptureStep = verification.nextMissingCaptureStep {
            print("Next capture:")
            print("  \(nextMissingCaptureStep.order). \(nextMissingCaptureStep.title) -> \(nextMissingCaptureStep.expectedFileName)")
            print("     \(nextMissingCaptureStep.instruction)")
            print("     Capture: \(nextMissingCaptureStep.captureCommand)")
            if let supportingCommand = nextMissingCaptureStep.supportingCommand {
                print("     Command: \(supportingCommand)")
            }
        }
        if !verification.appCheckProof.isValid {
            print("App check proof:")
            print("  \(verification.appCheckProof.command)")
        }
        print("Next actions:")
        for action in verification.nextActions {
            print("  - \(action)")
        }
    }

    @MainActor
    static func appRuntimeStatusReport(
        demo: Bool,
        hostBackingScale: Double? = nil
    ) async throws -> WindowsAppRuntimeStatusReport {
        let model = HostDashboardModel(service: appRuntimeStatusService(demo: demo))

        await model.loadRestoreIntent()
        await model.load()

        let localRuntimeSnapshot = try? await LocalVMRuntimeService().loadSnapshot()
        return model.runtimeStatusReport(
            localRuntime: model.localRuntimeStatus(snapshot: localRuntimeSnapshot),
            hostBackingScale: hostBackingScale
        )
    }

    private static func appRuntimeReviewEvidenceDirectory(
        requestedPath: String?,
        diagnosticsDirectory: String
    ) throws -> URL {
        if let requestedPath,
           !requestedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: requestedPath).standardizedFileURL
        }

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return URL(fileURLWithPath: diagnosticsDirectory)
            .appendingPathComponent("App Runtime Review")
            .appendingPathComponent(timestamp)
            .standardizedFileURL
    }

    private static func appRuntimeReviewEvidenceReadme(
        manifest: AppRuntimeReviewEvidenceManifest
    ) -> String {
        var lines: [String] = [
            "# Veil Windows App Review Evidence",
            "",
            "This folder stores one live Windows App Runtime review pass.",
            "",
            "## Checklist",
            "",
            "- Open this folder with `\(manifest.openEvidenceDirectoryCommand)`.",
            "- Capture every PNG listed below into this folder as a valid PNG of at least 640 x 360.",
            "- Run `\(manifest.appCheckProofFile.command)` and keep `\(manifest.appCheckProofFile.expectedFileName)` in this folder.",
            "- If the review card lists a latest notification proof, keep the referenced `Notification Proof` JSON available or regenerate it with `veil-vmctl notification-proof --json --require-proved --output ...`.",
            "- If the review card lists a latest printer proof, keep the referenced `Printer Proof` JSON available or regenerate it with `veil-vmctl printer-bridge-proof --json --evidence ...`.",
            "- Run `\(manifest.reviewCommand)`.",
            "- Confirm the review card reports `Screenshots: \(manifest.requiredScreenshotCount)/\(manifest.requiredScreenshotCount) attached`.",
            "- Run `\(manifest.verifyCommand)` before sharing evidence.",
            "- Keep `review-manifest.json`, `\(manifest.appCheckProofFile.expectedFileName)`, and the screenshots when sharing review evidence.",
            "",
            "## Capture Steps",
            ""
        ]

        for step in manifest.captureSteps {
            lines.append("\(step.order). \(step.title) -> `\(step.expectedFileName)`")
            lines.append("   \(step.instruction)")
            lines.append("   Capture: `\(step.captureCommand)`")
            if let supportingCommand = step.supportingCommand {
                lines.append("   Command: `\(supportingCommand)`")
            }
        }

        lines.append("")
        lines.append("## Expected Files")
        lines.append("")
        for file in manifest.screenshotFiles {
            lines.append("- `\(file.expectedFileName)`: \(file.expectedSurface)")
        }
        lines.append("- `\(manifest.appCheckProofFile.expectedFileName)`: proved Windows app launch, frame, input, and clipboard JSON evidence")
        lines.append("- Referenced `Notification Proof/*.json`: optional Windows notification proof JSON shown by the review card")
        lines.append("- Referenced `Printer Proof/*.json`: optional Windows printer bridge proof JSON shown by the review card")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func appRuntimeReviewManifestWithCurrentCommands(
        _ manifest: AppRuntimeReviewEvidenceManifest,
        evidenceDirectory: String
    ) -> AppRuntimeReviewEvidenceManifest {
        let pathsBySlotId = Dictionary(
            uniqueKeysWithValues: manifest.screenshotFiles.map { ($0.slotId, $0.path) }
        )
        let captureSteps = manifest.captureSteps.map { step in
            AppRuntimeReviewCaptureStep(
                order: step.order,
                slotId: step.slotId,
                title: step.title,
                expectedFileName: step.expectedFileName,
                instruction: step.instruction,
                captureCommand: step.captureCommand.isEmpty
                    ? appRuntimeReviewCaptureCommand(path: pathsBySlotId[step.slotId] ?? "\(evidenceDirectory)/\(step.expectedFileName)")
                    : step.captureCommand,
                supportingCommand: step.supportingCommand
            )
        }
        let reviewCommand = manifest.reviewCommand.isEmpty
            ? appRuntimeReviewCommand(evidenceDirectory: evidenceDirectory)
            : manifest.reviewCommand
        let verifyCommand = manifest.verifyCommand.isEmpty
            ? appRuntimeReviewVerifyCommand(evidenceDirectory: evidenceDirectory)
            : manifest.verifyCommand
        let openEvidenceDirectoryCommand = manifest.openEvidenceDirectoryCommand.isEmpty
            ? appRuntimeReviewOpenCommand(evidenceDirectory: evidenceDirectory)
            : manifest.openEvidenceDirectoryCommand
        let appCheckProofFile = AppRuntimeReviewAppCheckProofFile(
            expectedFileName: manifest.appCheckProofFile.expectedFileName,
            path: manifest.appCheckProofFile.path.isEmpty
                ? "\(evidenceDirectory)/mvp-proof.json"
                : manifest.appCheckProofFile.path,
            command: manifest.appCheckProofFile.command.isEmpty
                ? appRuntimeReviewProofCommand(
                    recommendedCommand: nil,
                    proofPath: "\(evidenceDirectory)/mvp-proof.json"
                )
                : manifest.appCheckProofFile.command,
            requiredKind: manifest.appCheckProofFile.requiredKind.isEmpty
                ? "windowsMVPProof"
                : manifest.appCheckProofFile.requiredKind,
            requiredStatus: manifest.appCheckProofFile.requiredStatus.isEmpty
                ? "proved"
                : manifest.appCheckProofFile.requiredStatus
        )

        return AppRuntimeReviewEvidenceManifest(
            generatedAt: manifest.generatedAt,
            evidenceDirectory: manifest.evidenceDirectory,
            manifestPath: manifest.manifestPath,
            readmePath: manifest.readmePath,
            requiredScreenshotCount: manifest.requiredScreenshotCount,
            minimumScreenshotWidth: minimumReviewScreenshotWidth,
            minimumScreenshotHeight: minimumReviewScreenshotHeight,
            screenshotFiles: manifest.screenshotFiles,
            appCheckProofFile: appCheckProofFile,
            captureSteps: captureSteps,
            reviewCommand: reviewCommand,
            verifyCommand: verifyCommand,
            openEvidenceDirectoryCommand: openEvidenceDirectoryCommand,
            nextActions: appRuntimeReviewManifestNextActions(
                reviewCommand: reviewCommand,
                verifyCommand: verifyCommand,
                openEvidenceDirectoryCommand: openEvidenceDirectoryCommand
            )
        )
    }

    private static func appRuntimeReviewManifestNextActions(
        reviewCommand: String,
        verifyCommand: String,
        openEvidenceDirectoryCommand: String
    ) -> [String] {
        [
            "Open the evidence folder with `\(openEvidenceDirectoryCommand)`.",
            "Capture the five required screenshots into the evidence directory as valid PNG files of at least 640 x 360.",
            "Run the saved app check proof command from `review-manifest.json` and keep `mvp-proof.json` in the evidence directory.",
            "If the review card lists notification proof, keep the referenced Notification Proof JSON available or regenerate it with `veil-vmctl notification-proof --json --require-proved --output ...`.",
            "If the review card lists printer proof, keep the referenced Printer Proof JSON available or regenerate it with `veil-vmctl printer-bridge-proof --json --evidence ...`.",
            "Run `\(reviewCommand)` and confirm Screenshots is 5/5 attached.",
            "Run `\(verifyCommand)` before sharing evidence."
        ]
    }

    private static func appRuntimeReviewScreenshotEvidenceSummary(
        requiredScreenshotCount: Int,
        validScreenshotCount: Int,
        missingScreenshotCount: Int,
        invalidScreenshotCount: Int,
        pendingScreenshotCount: Int,
        invalidCaptureSteps: [AppRuntimeReviewMissingCaptureStep],
        missingCaptureSteps: [AppRuntimeReviewMissingCaptureStep]
    ) -> AppRuntimeReviewScreenshotEvidenceSummary {
        if let nextInvalidCaptureStep = invalidCaptureSteps.first {
            return AppRuntimeReviewScreenshotEvidenceSummary(
                state: "needs-replacement",
                requiredScreenshotCount: requiredScreenshotCount,
                validScreenshotCount: validScreenshotCount,
                missingScreenshotCount: missingScreenshotCount,
                invalidScreenshotCount: invalidScreenshotCount,
                pendingScreenshotCount: pendingScreenshotCount,
                minimumWidth: minimumReviewScreenshotWidth,
                minimumHeight: minimumReviewScreenshotHeight,
                isScreenshotEvidenceReady: false,
                nextStepKind: "replaceInvalidScreenshot",
                nextStepTitle: "Replace \(nextInvalidCaptureStep.expectedFileName)",
                nextExpectedFileName: nextInvalidCaptureStep.expectedFileName,
                nextCaptureCommand: nextInvalidCaptureStep.captureCommand
            )
        }

        if let nextMissingCaptureStep = missingCaptureSteps.first {
            return AppRuntimeReviewScreenshotEvidenceSummary(
                state: "needs-capture",
                requiredScreenshotCount: requiredScreenshotCount,
                validScreenshotCount: validScreenshotCount,
                missingScreenshotCount: missingScreenshotCount,
                invalidScreenshotCount: invalidScreenshotCount,
                pendingScreenshotCount: pendingScreenshotCount,
                minimumWidth: minimumReviewScreenshotWidth,
                minimumHeight: minimumReviewScreenshotHeight,
                isScreenshotEvidenceReady: false,
                nextStepKind: "captureMissingScreenshot",
                nextStepTitle: "Capture \(nextMissingCaptureStep.expectedFileName)",
                nextExpectedFileName: nextMissingCaptureStep.expectedFileName,
                nextCaptureCommand: nextMissingCaptureStep.captureCommand
            )
        }

        return AppRuntimeReviewScreenshotEvidenceSummary(
            state: "ready",
            requiredScreenshotCount: requiredScreenshotCount,
            validScreenshotCount: validScreenshotCount,
            missingScreenshotCount: missingScreenshotCount,
            invalidScreenshotCount: invalidScreenshotCount,
            pendingScreenshotCount: pendingScreenshotCount,
            minimumWidth: minimumReviewScreenshotWidth,
            minimumHeight: minimumReviewScreenshotHeight,
            isScreenshotEvidenceReady: true,
            nextStepKind: "shareEvidence",
            nextStepTitle: "Share Review Evidence",
            nextExpectedFileName: nil,
            nextCaptureCommand: nil
        )
    }

    private static func appRuntimeReviewNextEvidenceAction(
        invalidCaptureSteps: [AppRuntimeReviewMissingCaptureStep],
        missingCaptureSteps: [AppRuntimeReviewMissingCaptureStep],
        appCheckProof: AppRuntimeReviewAppCheckProofEvidence,
        notificationProof: AppRuntimeReviewNotificationProofEvidence?,
        printerBridgeProof: AppRuntimeReviewPrinterBridgeProofEvidence?,
        openEvidenceDirectoryCommand: String
    ) -> AppRuntimeReviewNextEvidenceAction {
        if let nextInvalidCaptureStep = invalidCaptureSteps.first {
            return AppRuntimeReviewNextEvidenceAction(
                kind: "replaceInvalidScreenshot",
                title: "Replace \(nextInvalidCaptureStep.expectedFileName)",
                command: nextInvalidCaptureStep.captureCommand,
                isReadyToShare: false,
                expectedFileName: nextInvalidCaptureStep.expectedFileName,
                path: nextInvalidCaptureStep.path,
                instruction: nextInvalidCaptureStep.instruction,
                supportingCommand: nextInvalidCaptureStep.supportingCommand
            )
        }

        if let nextMissingCaptureStep = missingCaptureSteps.first {
            return AppRuntimeReviewNextEvidenceAction(
                kind: "captureMissingScreenshot",
                title: "Capture \(nextMissingCaptureStep.expectedFileName)",
                command: nextMissingCaptureStep.captureCommand,
                isReadyToShare: false,
                expectedFileName: nextMissingCaptureStep.expectedFileName,
                path: nextMissingCaptureStep.path,
                instruction: nextMissingCaptureStep.instruction,
                supportingCommand: nextMissingCaptureStep.supportingCommand
            )
        }

        if !appCheckProof.isValid {
            return AppRuntimeReviewNextEvidenceAction(
                kind: "runAppCheckProof",
                title: "Run App Check Proof",
                command: appCheckProof.command,
                isReadyToShare: false,
                expectedFileName: appCheckProof.expectedFileName,
                path: appCheckProof.path,
                instruction: "Run the saved Windows app proof and keep the proved JSON artifact in the evidence folder.",
                supportingCommand: "veil-vmctl app-runtime-status --json"
            )
        }

        if let notificationProof, !notificationProof.isValid {
            return AppRuntimeReviewNextEvidenceAction(
                kind: "regenerateNotificationProof",
                title: "Regenerate Notification Proof",
                command: notificationProof.command,
                isReadyToShare: false,
                expectedFileName: URL(fileURLWithPath: notificationProof.path).lastPathComponent,
                path: notificationProof.path,
                instruction: "Regenerate the Windows notification proof JSON before sharing review evidence.",
                supportingCommand: "veil-vmctl app-runtime-status --json"
            )
        }

        if let printerBridgeProof, !printerBridgeProof.isValid {
            return AppRuntimeReviewNextEvidenceAction(
                kind: "regeneratePrinterProof",
                title: "Regenerate Printer Proof",
                command: "veil-vmctl printer-bridge-proof --json --evidence ...",
                isReadyToShare: false,
                expectedFileName: URL(fileURLWithPath: printerBridgeProof.path).lastPathComponent,
                path: printerBridgeProof.path,
                instruction: "Regenerate the Windows printer test-page proof JSON before sharing review evidence.",
                supportingCommand: "veil-vmctl app-runtime-status --json"
            )
        }

        return AppRuntimeReviewNextEvidenceAction(
            kind: "shareEvidence",
            title: "Share Review Evidence",
            command: openEvidenceDirectoryCommand,
            isReadyToShare: true,
            expectedFileName: nil,
            path: nil,
            instruction: "Open the complete evidence folder and share the verified review artifacts.",
            supportingCommand: nil
        )
    }

    private static func appRuntimeReviewVerificationNextActions(
        evidenceDirectory: String,
        manifestExists: Bool,
        readmeExists: Bool,
        invalidScreenshotFiles: [AppRuntimeReviewInvalidScreenshotFile],
        appCheckProof: AppRuntimeReviewAppCheckProofEvidence,
        notificationProof: AppRuntimeReviewNotificationProofEvidence?,
        printerBridgeProof: AppRuntimeReviewPrinterBridgeProofEvidence?,
        invalidCaptureSteps: [AppRuntimeReviewMissingCaptureStep],
        missingCaptureSteps: [AppRuntimeReviewMissingCaptureStep],
        reviewCommand: String,
        verifyCommand: String,
        openEvidenceDirectoryCommand: String
    ) -> [String] {
        var actions: [String] = []
        if !manifestExists || !readmeExists {
            actions.append("Run `veil-vmctl app-runtime-review-init --evidence-dir '\(evidenceDirectory)'` to recreate the review manifest and guide.")
        }
        actions.append("Open the evidence folder with `\(openEvidenceDirectoryCommand)`.")
        if let invalidScreenshotFile = invalidScreenshotFiles.first {
            actions.append("Replace invalid screenshot `\(URL(fileURLWithPath: invalidScreenshotFile.path).lastPathComponent)`: \(invalidScreenshotFile.reason).")
        }
        if let nextInvalidCaptureStep = invalidCaptureSteps.first {
            actions.append("Recapture replacement with `\(nextInvalidCaptureStep.captureCommand)`.")
        }
        if let nextMissingCaptureStep = missingCaptureSteps.first {
            actions.append("Capture `\(nextMissingCaptureStep.expectedFileName)` for \(nextMissingCaptureStep.title): \(nextMissingCaptureStep.instruction)")
            actions.append("Save it as a valid PNG of at least 640 x 360 with `\(nextMissingCaptureStep.captureCommand)`.")
            if let supportingCommand = nextMissingCaptureStep.supportingCommand {
                actions.append("Use `\(supportingCommand)` to reach the next capture state before saving `\(nextMissingCaptureStep.expectedFileName)`.")
            }
        }
        if !appCheckProof.isValid {
            if let issueReason = appCheckProof.issueReason {
                actions.append("Run `\(appCheckProof.command)` to create `\(appCheckProof.expectedFileName)` with \(appCheckProof.requiredKind) status=\(appCheckProof.requiredStatus); current issue: \(issueReason).")
            } else {
                actions.append("Run `\(appCheckProof.command)` to create `\(appCheckProof.expectedFileName)` with \(appCheckProof.requiredKind) status=\(appCheckProof.requiredStatus).")
            }
        }
        if let notificationProof, !notificationProof.isValid {
            if let issueReason = notificationProof.issueReason {
                actions.append("Regenerate notification proof at `\(notificationProof.path)` with `\(notificationProof.command)`; current issue: \(issueReason).")
            } else {
                actions.append("Regenerate notification proof at `\(notificationProof.path)` with `\(notificationProof.command)`.")
            }
        }
        if let printerBridgeProof, !printerBridgeProof.isValid {
            if let issueReason = printerBridgeProof.issueReason {
                actions.append("Regenerate printer bridge proof at `\(printerBridgeProof.path)` with `veil-vmctl printer-bridge-proof --json --evidence ...`; current issue: \(issueReason).")
            } else {
                actions.append("Regenerate printer bridge proof at `\(printerBridgeProof.path)` with `veil-vmctl printer-bridge-proof --json --evidence ...`.")
            }
        }
        actions.append("Run `\(reviewCommand)` and confirm Screenshots is 5/5 attached.")
        actions.append("Run `\(verifyCommand)` before sharing evidence.")
        return actions
    }

    private static func appRuntimeReviewMissingCaptureSteps(
        expectedFiles: [String],
        captureSteps: [AppRuntimeReviewCaptureStep],
        missingFiles: [String]
    ) -> [AppRuntimeReviewMissingCaptureStep] {
        let missingFileSet = Set(missingFiles)
        return captureSteps.enumerated().compactMap { index, step in
            guard index < expectedFiles.count else {
                return nil
            }
            let path = expectedFiles[index]
            guard missingFileSet.contains(path) else {
                return nil
            }
            return AppRuntimeReviewMissingCaptureStep(
                order: step.order,
                slotId: step.slotId,
                title: step.title,
                expectedFileName: step.expectedFileName,
                path: path,
                instruction: step.instruction,
                captureCommand: step.captureCommand,
                supportingCommand: step.supportingCommand
            )
        }
    }

    private static func appRuntimeReviewCaptureSteps(
        screenshotFiles: [AppRuntimeReviewEvidenceFile],
        appCheckProofFile: AppRuntimeReviewAppCheckProofFile,
        card: AppRuntimeReviewCard
    ) -> [AppRuntimeReviewCaptureStep] {
        screenshotFiles.enumerated().map { index, file in
            AppRuntimeReviewCaptureStep(
                order: index + 1,
                slotId: file.slotId,
                title: file.title,
                expectedFileName: file.expectedFileName,
                instruction: appRuntimeReviewCaptureInstruction(slotId: file.slotId),
                captureCommand: appRuntimeReviewCaptureCommand(path: file.path),
                supportingCommand: appRuntimeReviewCaptureCommand(
                    slotId: file.slotId,
                    appCheckProofFile: appCheckProofFile,
                    card: card
                )
            )
        }
    }

    private static func appRuntimeReviewAppCheckProofFile(
        evidenceDirectory: String,
        recommendedCommand: String?
    ) -> AppRuntimeReviewAppCheckProofFile {
        let path = URL(fileURLWithPath: evidenceDirectory)
            .appendingPathComponent("mvp-proof.json")
            .standardizedFileURL
            .path

        return AppRuntimeReviewAppCheckProofFile(
            expectedFileName: "mvp-proof.json",
            path: path,
            command: appRuntimeReviewProofCommand(
                recommendedCommand: recommendedCommand,
                proofPath: path
            ),
            requiredKind: "windowsMVPProof",
            requiredStatus: "proved"
        )
    }

    private static func appRuntimeReviewProofCommand(
        recommendedCommand: String?,
        proofPath: String
    ) -> String {
        let fallback = "veil-vmctl mvp-proof --json --app-id winapp_notepad --require-proved"
        let baseCommand = recommendedCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = baseCommand?.isEmpty == false ? baseCommand! : fallback
        guard !command.contains(" --output ") else {
            return command
        }
        return "\(command) --output \(shellQuoted(proofPath))"
    }

    private static func appRuntimeReviewCaptureCommand(path: String) -> String {
        "screencapture -i \(shellQuoted(path))"
    }

    private static func appRuntimeReviewCommand(evidenceDirectory: String) -> String {
        "veil-vmctl app-runtime-review --evidence-dir \(shellQuoted(evidenceDirectory))"
    }

    static func appRuntimeReviewVerifyCommand(evidenceDirectory: String) -> String {
        "veil-vmctl app-runtime-review-verify --json --evidence-dir \(shellQuoted(evidenceDirectory))"
    }

    private static func appRuntimeReviewOpenCommand(evidenceDirectory: String) -> String {
        "open \(shellQuoted(evidenceDirectory))"
    }

    private static func appRuntimeReviewCaptureInstruction(slotId: String) -> String {
        switch slotId {
        case "preBootLauncher":
            return "Capture the one-screen Veil launcher before opening the selected Windows app."
        case "firstAppLaunch":
            return "Start or queue the selected Windows app and capture the first visible launch state."
        case "appWindowOnly":
            return "Capture the mirrored Windows app window after the launcher is hidden."
        case "menuRestore":
            return "Open the menu or Dock control and capture restore, reconnect, bring-forward, or close actions."
        case "closeQuiet":
            return "Close the final Windows app window and capture the returned launcher or quiet-Windows control."
        default:
            return "Capture the expected Windows app runtime surface."
        }
    }

    private static func appRuntimeReviewCaptureCommand(
        slotId: String,
        appCheckProofFile: AppRuntimeReviewAppCheckProofFile,
        card: AppRuntimeReviewCard
    ) -> String? {
        switch slotId {
        case "preBootLauncher":
            return card.statusCommand
        case "firstAppLaunch":
            return card.steps.first { $0.id == "openWindowsApp" }?.nextActionCommand
        case "appWindowOnly":
            return appCheckProofFile.command
        case "menuRestore":
            return "veil-vmctl app-runtime-action --json --action bring-forward"
        case "closeQuiet":
            return card.steps.first { $0.id == "closeOrRestore" }?.nextActionCommand
        default:
            return nil
        }
    }
}
