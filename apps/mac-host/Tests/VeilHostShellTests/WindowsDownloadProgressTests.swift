import Foundation
import Testing

@testable import VeilHostShell

@Suite("Windows download progress presentation")
struct WindowsDownloadProgressTests {
    @Test("time left reads in plain minutes and hours")
    func remainingText() {
        #expect(WindowsDownloadTransfer.remainingText(seconds: 20) == "Less than a minute left")
        #expect(WindowsDownloadTransfer.remainingText(seconds: 61) == "About 2 minutes left")
        #expect(WindowsDownloadTransfer.remainingText(seconds: 60) == "About 1 minute left")
        #expect(WindowsDownloadTransfer.remainingText(seconds: 3600) == "About 1 hr left")
        #expect(WindowsDownloadTransfer.remainingText(seconds: 5400) == "About 1 hr 30 min left")
    }

    @Test("the first sample sets the rate and later samples are smoothed")
    func rateSmoothing() {
        let start = WindowsDownloadTransfer(receivedBytes: 0, totalBytes: 10_000_000)
        #expect(start.rateText == nil && start.remainingText == nil)

        let first = start.advanced(toReceivedBytes: 1_000_000, totalBytes: 10_000_000, over: 1)
        #expect(first.bytesPerSecond == 1_000_000)
        #expect(first.remainingText == "Less than a minute left")

        let stalled = first.advanced(toReceivedBytes: 1_000_000, totalBytes: 10_000_000, over: 1)
        #expect(stalled.bytesPerSecond == 750_000)
    }

    @Test("a zero-length interval keeps the previous rate")
    func zeroElapsedKeepsRate() {
        let transfer = WindowsDownloadTransfer(receivedBytes: 5, totalBytes: 10, bytesPerSecond: 2)
        #expect(transfer.advanced(toReceivedBytes: 6, totalBytes: 10, over: 0).bytesPerSecond == 2)
    }

    @Test("the tracker follows download, verification, and VM preparation, and stops on failure")
    func stageTracker() {
        #expect(WindowsDownloadStage.resolve(phase: .loadingPage, isPreparingWindows: false) == .download)
        #expect(WindowsDownloadStage.resolve(phase: .downloading(filename: "a.iso"), isPreparingWindows: false) == .download)
        #expect(WindowsDownloadStage.resolve(phase: .verifying(filename: "a.iso"), isPreparingWindows: false) == .verify)
        #expect(WindowsDownloadStage.resolve(phase: .downloaded(URL(fileURLWithPath: "/a.iso")), isPreparingWindows: true) == .prepare)
        #expect(WindowsDownloadStage.resolve(phase: .failed("x"), isPreparingWindows: false) == nil)
    }
}
