import Foundation
import Testing

@testable import VeilHostCore

@Suite("Frame pipeline metrics")
struct FramePipelineMetricsTests {
    private static let startedAt = Date(timeIntervalSince1970: 5_000)

    private static func tile(
        windowId: String = "hwnd:0003029A",
        sequence: Int = 1,
        surfaceWidth: Int = 100,
        surfaceHeight: Int = 100,
        isKeyFrame: Bool = false,
        rect: WindowFrameTileRect = WindowFrameTileRect(x: 0, y: 0, width: 10, height: 10),
        payloadByteCount: Int = 64
    ) -> WindowFrameTile {
        WindowFrameTile(
            windowId: windowId,
            sequence: sequence,
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight,
            scale: 1,
            isKeyFrame: isKeyFrame,
            rect: rect,
            payload: Data(repeating: 0xAB, count: payloadByteCount)
        )
    }

    private static func keyFrame(
        windowId: String = "hwnd:0003029A",
        sequence: Int = 1,
        surfaceWidth: Int = 100,
        surfaceHeight: Int = 100,
        payloadByteCount: Int = 5_000
    ) -> WindowFrameTile {
        tile(
            windowId: windowId,
            sequence: sequence,
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight,
            isKeyFrame: true,
            rect: WindowFrameTileRect(x: 0, y: 0, width: surfaceWidth, height: surfaceHeight),
            payloadByteCount: payloadByteCount
        )
    }

    @Test("reports achieved frame rate and wire byte rate over the observation window")
    func reportsRatesOverObservationWindow() {
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)

        metrics.recordApplied(
            tile: Self.keyFrame(),
            wireByteCount: 5_100,
            compositeDuration: 0.002,
            receivedAt: Self.startedAt
        )
        for index in 1...4 {
            metrics.recordApplied(
                tile: Self.tile(sequence: index + 1),
                wireByteCount: 100,
                compositeDuration: 0.001,
                receivedAt: Self.startedAt.addingTimeInterval(Double(index) * 0.25)
            )
        }

        let report = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(10))
        let window = report.windows.first

        #expect(report.didObserveFrames)
        #expect(report.observedSeconds == 10)
        #expect(report.totalWireBytes == 5_500)
        #expect(report.totalFramesPerSecond == 0.5)
        #expect(report.totalWireBytesPerSecond == 550)
        #expect(window?.keyFrameCount == 1)
        #expect(window?.tileCount == 4)
        #expect(window?.keyFrameWireBytes == 5_100)
        #expect(window?.tileWireBytes == 400)
    }

    @Test("rates are measured against the requested window, not the last event")
    func ratesUseRequestedWindow() {
        // An idle tail must be honestly included. Ending the window at the last frame would report a rate
        // the pipeline never sustained.
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)
        metrics.recordApplied(
            tile: Self.keyFrame(),
            wireByteCount: 1_000,
            compositeDuration: 0.001,
            receivedAt: Self.startedAt
        )

        let report = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(20))

        #expect(report.observedSeconds == 20)
        #expect(report.totalFramesPerSecond == 0.05)
    }

    @Test("reports tile coverage as a percentage of the surface")
    func reportsTileCoverage() {
        // The single number that says whether dirty-rect tracking is paying off on real content.
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)

        metrics.recordApplied(
            tile: Self.tile(rect: WindowFrameTileRect(x: 0, y: 0, width: 10, height: 10)),
            wireByteCount: 100,
            compositeDuration: 0,
            receivedAt: Self.startedAt
        )
        metrics.recordApplied(
            tile: Self.tile(sequence: 2, rect: WindowFrameTileRect(x: 0, y: 0, width: 50, height: 100)),
            wireByteCount: 100,
            compositeDuration: 0,
            receivedAt: Self.startedAt.addingTimeInterval(0.1)
        )

        let coverage = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(1)).windows.first?.tileCoveragePercent

        #expect(coverage?.count == 2)
        // Nearest-rank p50 for the two observed samples selects the larger sample.
        #expect(coverage?.p50 == 50)
        #expect(coverage?.maximum == 50)
    }

    @Test("estimates full-frame cost from observed key-frame bytes per pixel")
    func estimatesFullFrameCostFromObservedKeyFrames() {
        // Anchored to this content at this resolution rather than a constant, because PNG size depends on
        // what is being encoded.
        let estimate = FramePipelineMetrics.estimatedFullFrameWireBytes(
            keyFrameWireBytes: 10_000,
            keyFramePixels: 10_000,
            surfacePixels: 10_000,
            appliedUpdates: 5
        )

        #expect(estimate == 50_000)
        #expect(FramePipelineMetrics.savedPercent(actual: 12_500, estimated: estimate) == 75)
    }

    @Test("withholds the estimate when no key frame was observed")
    func withholdsEstimateWithoutKeyFrame() {
        // Inventing a bytes-per-pixel constant would make a guess look like data.
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)
        metrics.recordApplied(
            tile: Self.tile(),
            wireByteCount: 100,
            compositeDuration: 0,
            receivedAt: Self.startedAt
        )

        let window = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(1)).windows.first

        #expect(window?.estimatedFullFrameWireBytes == nil)
        #expect(window?.estimatedWireBytesSavedPercent == nil)
    }

    @Test("reports a negative saving when tiles cost more than full frames would have")
    func reportsNegativeSaving() {
        // A real outcome for content that changes everywhere, and one the report must not hide.
        #expect(
            FramePipelineMetrics.savedPercent(actual: 200, estimated: 100) == -100
        )
    }

    @Test("counts dropped tiles by reason without treating them as delivered frames")
    func countsDroppedTilesByReason() {
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)

        metrics.recordDropped(windowId: "hwnd:0003029A", reason: .noSurface, at: Self.startedAt)
        metrics.recordDropped(windowId: "hwnd:0003029A", reason: .noSurface, at: Self.startedAt)
        metrics.recordDropped(windowId: "hwnd:0003029A", reason: .surfaceSizeChanged, at: Self.startedAt)

        let report = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(1))
        let window = report.windows.first

        // A dropped tile never reached the screen, so it cannot count as a delivered frame.
        #expect(!report.didObserveFrames)
        #expect(window?.droppedTiles.noSurface == 2)
        #expect(window?.droppedTiles.surfaceSizeChanged == 1)
        #expect(window?.droppedTiles.total == 3)
        #expect(window?.keyFrameCount == 0)
        #expect(window?.tileCount == 0)
    }

    @Test("keeps per-window measurements separate and ordered")
    func keepsWindowsSeparateAndOrdered() {
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)

        metrics.recordApplied(
            tile: Self.keyFrame(windowId: "hwnd:B"),
            wireByteCount: 2_000,
            compositeDuration: 0,
            receivedAt: Self.startedAt
        )
        metrics.recordApplied(
            tile: Self.keyFrame(windowId: "hwnd:A"),
            wireByteCount: 1_000,
            compositeDuration: 0,
            receivedAt: Self.startedAt
        )

        let report = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(1))

        #expect(report.windows.map(\.windowId) == ["hwnd:A", "hwnd:B"])
        #expect(report.totalWireBytes == 3_000)
    }

    @Test("a run with no activity reports honestly rather than as a measured zero")
    func runWithNoActivityReportsHonestly() {
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)

        let report = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(10))

        #expect(!report.didObserveFrames)
        #expect(report.windows.isEmpty)
        #expect(report.nextActions.contains { $0.contains("app-runtime-status") })
    }

    @Test("a zero-length observation window reports zero rates instead of infinity")
    func zeroLengthWindowReportsZeroRates() {
        #expect(FramePipelineMetrics.perSecond(10, 0) == 0)
        #expect(FramePipelineMetrics.perSecond(10, 2) == 5)
    }

    @Test("bounds retained samples so a long run cannot grow without limit")
    func boundsRetainedSamples() {
        let metrics = FramePipelineMetrics()
        metrics.start(at: Self.startedAt)

        for index in 0..<(FramePipelineMetrics.maximumRetainedSamples + 500) {
            metrics.recordApplied(
                tile: Self.tile(sequence: index + 1),
                wireByteCount: 10,
                compositeDuration: 0.001,
                receivedAt: Self.startedAt.addingTimeInterval(Double(index) * 0.001)
            )
        }

        let window = metrics.report(generatedAt: Self.startedAt.addingTimeInterval(60)).windows.first

        // Counts stay exact; only the retained samples used for percentiles are capped.
        #expect(window?.tileCount == FramePipelineMetrics.maximumRetainedSamples + 500)
        #expect(window?.compositeMilliseconds.count == FramePipelineMetrics.maximumRetainedSamples)
    }

    @Test("flags content where dirty-rect tracking is not paying off")
    func flagsContentWhereTilesDoNotPayOff() {
        // The report is supposed to answer the question, not leave the arithmetic to the reader.
        let heavy = FramePipelineWindowReport(
            windowId: "hwnd:0003029A",
            surfaceWidth: 100,
            surfaceHeight: 100,
            observedSeconds: 10,
            keyFrameCount: 1,
            tileCount: 20,
            unchangedHeartbeatCount: 0,
            droppedTiles: FramePipelineDroppedTileCounts(),
            wireBytes: 1_000,
            keyFrameWireBytes: 500,
            tileWireBytes: 500,
            framesPerSecond: 2.1,
            wireBytesPerSecond: 100,
            frameIntervalMilliseconds: .empty,
            tileCoveragePercent: FramePipelineSampleSummary(count: 20, mean: 72, p50: 74, p95: 90, maximum: 100),
            compositeMilliseconds: .empty,
            estimatedFullFrameWireBytes: 2_000,
            estimatedWireBytesSavedPercent: 50
        )

        let actions = FramePipelineMetrics.nextActions(windows: [heavy], didObserveFrames: true)

        #expect(actions.contains { $0.contains("Median tile coverage") })
        #expect(actions.contains { $0.contains("region strategy") })
    }

    @Test("summarizes samples with ordered nearest-rank percentiles")
    func summarizesWithOrderedPercentiles() {
        let summary = FramePipelineSampleSummary.summarize([5, 1, 3, 9, 7])

        #expect(summary.count == 5)
        #expect(summary.mean == 5)
        #expect(summary.p50 == 5)
        #expect(summary.maximum == 9)
        // Nearest-rank, so every reported value is one that actually occurred.
        #expect([1.0, 3, 5, 7, 9].contains(summary.p95))
        #expect(summary.p50 <= summary.p95)
        #expect(summary.p95 <= summary.maximum)
    }

    @Test("an empty sample set summarizes to all zeroes")
    func emptySampleSetSummarizesToZero() {
        #expect(FramePipelineSampleSummary.summarize([]) == .empty)
    }
}
