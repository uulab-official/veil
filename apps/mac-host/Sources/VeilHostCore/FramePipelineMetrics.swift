import Foundation

/// Ordered summary of a sample set.
///
/// Percentiles rather than a mean alone: a mean frame interval hides exactly the stalls a user notices,
/// and a pipeline that averages 30fps while periodically pausing 400ms feels broken despite a healthy
/// average.
public struct FramePipelineSampleSummary: Codable, Equatable, Sendable {
    public var count: Int
    public var mean: Double
    public var p50: Double
    public var p95: Double
    public var maximum: Double

    public init(count: Int, mean: Double, p50: Double, p95: Double, maximum: Double) {
        self.count = count
        self.mean = mean
        self.p50 = p50
        self.p95 = p95
        self.maximum = maximum
    }

    public static let empty = FramePipelineSampleSummary(count: 0, mean: 0, p50: 0, p95: 0, maximum: 0)

    /// Builds a summary from unsorted samples.
    ///
    /// Uses nearest-rank percentiles on the sorted samples. No interpolation, so every reported value is
    /// a value that actually occurred.
    public static func summarize(_ samples: [Double]) -> FramePipelineSampleSummary {
        guard !samples.isEmpty else {
            return .empty
        }

        let sorted = samples.sorted()
        let total = sorted.reduce(0, +)
        return FramePipelineSampleSummary(
            count: sorted.count,
            mean: total / Double(sorted.count),
            p50: percentile(sorted, 0.50),
            p95: percentile(sorted, 0.95),
            maximum: sorted[sorted.count - 1]
        )
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else {
            return 0
        }

        let rank = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[min(max(0, rank), sorted.count - 1)]
    }
}

/// Why a tile could not be applied, counted separately so a report distinguishes "the guest is sending
/// tiles we cannot use" from "the guest is not sending anything".
public struct FramePipelineDroppedTileCounts: Codable, Equatable, Sendable {
    public var noSurface: Int
    public var surfaceSizeChanged: Int
    public var undecodablePayload: Int
    public var payloadRectMismatch: Int

    public init(
        noSurface: Int = 0,
        surfaceSizeChanged: Int = 0,
        undecodablePayload: Int = 0,
        payloadRectMismatch: Int = 0
    ) {
        self.noSurface = noSurface
        self.surfaceSizeChanged = surfaceSizeChanged
        self.undecodablePayload = undecodablePayload
        self.payloadRectMismatch = payloadRectMismatch
    }

    public var total: Int {
        noSurface + surfaceSizeChanged + undecodablePayload + payloadRectMismatch
    }
}

public struct FramePipelineWindowReport: Codable, Equatable, Sendable {
    public var windowId: String
    public var surfaceWidth: Int
    public var surfaceHeight: Int
    public var observedSeconds: Double

    public var keyFrameCount: Int
    public var tileCount: Int
    public var unchangedHeartbeatCount: Int
    public var droppedTiles: FramePipelineDroppedTileCounts

    public var wireBytes: Int
    public var keyFrameWireBytes: Int
    public var tileWireBytes: Int

    /// Frames per second actually delivered, key frames plus applied tiles.
    public var framesPerSecond: Double
    public var wireBytesPerSecond: Double
    /// Milliseconds between consecutive applied updates.
    public var frameIntervalMilliseconds: FramePipelineSampleSummary
    /// Percentage of the surface each tile covered. The single number that says whether dirty-rect
    /// tracking is paying off on real content.
    public var tileCoveragePercent: FramePipelineSampleSummary
    /// Host cost of decoding a tile and drawing it into the surface.
    public var compositeMilliseconds: FramePipelineSampleSummary

    /// What the same updates would have cost as full frames, estimated from observed key-frame bytes per
    /// pixel. `nil` when no key frame was observed, since there is then no measured basis for it.
    public var estimatedFullFrameWireBytes: Int?
    /// Percentage of wire bytes saved against that estimate. Negative means tiles cost more than full
    /// frames would have, which is a real possibility for content that changes everywhere.
    public var estimatedWireBytesSavedPercent: Double?

    public init(
        windowId: String,
        surfaceWidth: Int,
        surfaceHeight: Int,
        observedSeconds: Double,
        keyFrameCount: Int,
        tileCount: Int,
        unchangedHeartbeatCount: Int,
        droppedTiles: FramePipelineDroppedTileCounts,
        wireBytes: Int,
        keyFrameWireBytes: Int,
        tileWireBytes: Int,
        framesPerSecond: Double,
        wireBytesPerSecond: Double,
        frameIntervalMilliseconds: FramePipelineSampleSummary,
        tileCoveragePercent: FramePipelineSampleSummary,
        compositeMilliseconds: FramePipelineSampleSummary,
        estimatedFullFrameWireBytes: Int?,
        estimatedWireBytesSavedPercent: Double?
    ) {
        self.windowId = windowId
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
        self.observedSeconds = observedSeconds
        self.keyFrameCount = keyFrameCount
        self.tileCount = tileCount
        self.unchangedHeartbeatCount = unchangedHeartbeatCount
        self.droppedTiles = droppedTiles
        self.wireBytes = wireBytes
        self.keyFrameWireBytes = keyFrameWireBytes
        self.tileWireBytes = tileWireBytes
        self.framesPerSecond = framesPerSecond
        self.wireBytesPerSecond = wireBytesPerSecond
        self.frameIntervalMilliseconds = frameIntervalMilliseconds
        self.tileCoveragePercent = tileCoveragePercent
        self.compositeMilliseconds = compositeMilliseconds
        self.estimatedFullFrameWireBytes = estimatedFullFrameWireBytes
        self.estimatedWireBytesSavedPercent = estimatedWireBytesSavedPercent
    }
}

public struct FramePipelineReport: Codable, Equatable, Sendable {
    public var kind: String
    public var generatedAt: Date
    public var observedSeconds: Double
    /// `true` only when at least one update was applied. A report with no frames must not be mistaken for
    /// a measured result of zero.
    public var didObserveFrames: Bool
    public var transport: String
    public var windows: [FramePipelineWindowReport]
    public var totalWireBytes: Int
    public var totalFramesPerSecond: Double
    public var totalWireBytesPerSecond: Double
    public var estimationBasis: String
    public var nextActions: [String]

    public init(
        kind: String = "framePipelineReport",
        generatedAt: Date,
        observedSeconds: Double,
        didObserveFrames: Bool,
        transport: String,
        windows: [FramePipelineWindowReport],
        totalWireBytes: Int,
        totalFramesPerSecond: Double,
        totalWireBytesPerSecond: Double,
        estimationBasis: String,
        nextActions: [String]
    ) {
        self.kind = kind
        self.generatedAt = generatedAt
        self.observedSeconds = observedSeconds
        self.didObserveFrames = didObserveFrames
        self.transport = transport
        self.windows = windows
        self.totalWireBytes = totalWireBytes
        self.totalFramesPerSecond = totalFramesPerSecond
        self.totalWireBytesPerSecond = totalWireBytesPerSecond
        self.estimationBasis = estimationBasis
        self.nextActions = nextActions
    }
}

/// Collects frame pipeline throughput and efficiency measurements.
///
/// Three slices of frame-pipeline work landed on reasoning alone: heartbeats for idle windows, a binary
/// channel, and dirty-rect tiles. Each is defensible and none is verified. This exists so the next
/// decision -- key-frame interval, codec choice, whether the region strategy is even right -- rests on
/// observation rather than another argument.
///
/// Latency is deliberately out of scope: `coherence-proof` already measures first-frame and post-input
/// latency against a budget. What was missing is throughput and efficiency.
public final class FramePipelineMetrics: @unchecked Sendable {
    /// Cap on retained samples per window per series.
    ///
    /// A long measurement run must not grow without limit. Once full, later samples are dropped rather
    /// than reservoir-sampled: this is a bounded diagnostic run, and a simple, obvious rule beats a
    /// statistically nicer one that is harder to reason about when a number looks wrong.
    public static let maximumRetainedSamples = 20_000

    public static let transportBinaryFrameChannel = "binaryFrameChannel"
    public static let estimationBasis =
        "Full-frame cost is estimated from the observed mean key-frame bytes per pixel for the same window. PNG size is not linear in area, so treat it as an estimate, not a measurement."

    private struct WindowState {
        var surfaceWidth = 0
        var surfaceHeight = 0
        var keyFrameCount = 0
        var tileCount = 0
        var unchangedHeartbeatCount = 0
        var droppedTiles = FramePipelineDroppedTileCounts()
        var keyFrameWireBytes = 0
        var tileWireBytes = 0
        var keyFramePixels = 0
        var tilePixels = 0
        var frameIntervals: [Double] = []
        var tileCoverage: [Double] = []
        var compositeDurations: [Double] = []
        var lastAppliedAt: Date?
    }

    private let lock = NSLock()
    private var windows: [String: WindowState] = [:]
    private var startedAt: Date?
    private var lastActivityAt: Date?

    public init() {}

    public func start(at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        windows.removeAll()
        startedAt = date
        lastActivityAt = nil
    }

    /// Records an update that was successfully applied to a surface.
    ///
    /// `wireByteCount` is the full encoded message size including the header, not just the payload, so the
    /// report reflects what actually crossed the connection.
    public func recordApplied(
        tile: WindowFrameTile,
        wireByteCount: Int,
        compositeDuration: TimeInterval,
        receivedAt: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        if startedAt == nil {
            startedAt = receivedAt
        }
        lastActivityAt = receivedAt

        var state = windows[tile.windowId] ?? WindowState()
        state.surfaceWidth = tile.surfaceWidth
        state.surfaceHeight = tile.surfaceHeight

        let tilePixels = tile.rect.width * tile.rect.height
        let surfacePixels = tile.surfaceWidth * tile.surfaceHeight

        if tile.isKeyFrame {
            state.keyFrameCount += 1
            state.keyFrameWireBytes += wireByteCount
            state.keyFramePixels += surfacePixels
        } else {
            state.tileCount += 1
            state.tileWireBytes += wireByteCount
            state.tilePixels += tilePixels
        }

        if surfacePixels > 0 {
            Self.append(
                Double(tilePixels) / Double(surfacePixels) * 100,
                to: &state.tileCoverage
            )
        }
        Self.append(compositeDuration * 1_000, to: &state.compositeDurations)

        if let lastAppliedAt = state.lastAppliedAt {
            Self.append(
                max(0, receivedAt.timeIntervalSince(lastAppliedAt) * 1_000),
                to: &state.frameIntervals
            )
        }
        state.lastAppliedAt = receivedAt

        windows[tile.windowId] = state
    }

    public func recordDropped(
        windowId: String,
        reason: WindowFrameCompositor.RejectionReason,
        at date: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        if startedAt == nil {
            startedAt = date
        }
        lastActivityAt = date

        var state = windows[windowId] ?? WindowState()
        switch reason {
        case .noSurface:
            state.droppedTiles.noSurface += 1
        case .surfaceSizeChanged:
            state.droppedTiles.surfaceSizeChanged += 1
        case .undecodablePayload:
            state.droppedTiles.undecodablePayload += 1
        case .payloadRectMismatch:
            state.droppedTiles.payloadRectMismatch += 1
        }
        windows[windowId] = state
    }

    public func recordUnchangedHeartbeat(windowId: String, at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        if startedAt == nil {
            startedAt = date
        }
        lastActivityAt = date

        var state = windows[windowId] ?? WindowState()
        state.unchangedHeartbeatCount += 1
        windows[windowId] = state
    }

    public func report(generatedAt: Date = Date()) -> FramePipelineReport {
        lock.lock()
        defer { lock.unlock() }

        // Measured against the requested window, not the last event, so an idle tail is honestly included
        // in the rate rather than inflating it.
        let observedSeconds = max(0, generatedAt.timeIntervalSince(startedAt ?? generatedAt))
        var windowReports: [FramePipelineWindowReport] = []
        var totalWireBytes = 0
        var totalAppliedUpdates = 0

        for (windowId, state) in windows.sorted(by: { $0.key < $1.key }) {
            let appliedUpdates = state.keyFrameCount + state.tileCount
            let wireBytes = state.keyFrameWireBytes + state.tileWireBytes
            totalWireBytes += wireBytes
            totalAppliedUpdates += appliedUpdates

            let estimate = Self.estimatedFullFrameWireBytes(
                keyFrameWireBytes: state.keyFrameWireBytes,
                keyFramePixels: state.keyFramePixels,
                surfacePixels: state.surfaceWidth * state.surfaceHeight,
                appliedUpdates: appliedUpdates
            )

            windowReports.append(
                FramePipelineWindowReport(
                    windowId: windowId,
                    surfaceWidth: state.surfaceWidth,
                    surfaceHeight: state.surfaceHeight,
                    observedSeconds: observedSeconds,
                    keyFrameCount: state.keyFrameCount,
                    tileCount: state.tileCount,
                    unchangedHeartbeatCount: state.unchangedHeartbeatCount,
                    droppedTiles: state.droppedTiles,
                    wireBytes: wireBytes,
                    keyFrameWireBytes: state.keyFrameWireBytes,
                    tileWireBytes: state.tileWireBytes,
                    framesPerSecond: Self.perSecond(Double(appliedUpdates), observedSeconds),
                    wireBytesPerSecond: Self.perSecond(Double(wireBytes), observedSeconds),
                    frameIntervalMilliseconds: FramePipelineSampleSummary.summarize(state.frameIntervals),
                    tileCoveragePercent: FramePipelineSampleSummary.summarize(state.tileCoverage),
                    compositeMilliseconds: FramePipelineSampleSummary.summarize(state.compositeDurations),
                    estimatedFullFrameWireBytes: estimate,
                    estimatedWireBytesSavedPercent: Self.savedPercent(actual: wireBytes, estimated: estimate)
                )
            )
        }

        return FramePipelineReport(
            generatedAt: generatedAt,
            observedSeconds: observedSeconds,
            didObserveFrames: totalAppliedUpdates > 0,
            transport: Self.transportBinaryFrameChannel,
            windows: windowReports,
            totalWireBytes: totalWireBytes,
            totalFramesPerSecond: Self.perSecond(Double(totalAppliedUpdates), observedSeconds),
            totalWireBytesPerSecond: Self.perSecond(Double(totalWireBytes), observedSeconds),
            estimationBasis: Self.estimationBasis,
            nextActions: Self.nextActions(windows: windowReports, didObserveFrames: totalAppliedUpdates > 0)
        )
    }

    /// Estimates what the observed updates would have cost as full frames.
    ///
    /// Uses the observed key-frame bytes per pixel for the same window rather than a constant, so the
    /// estimate is anchored to this content at this resolution. Returns `nil` without a key frame, since
    /// there is then no measured basis and inventing one would make a guess look like data.
    static func estimatedFullFrameWireBytes(
        keyFrameWireBytes: Int,
        keyFramePixels: Int,
        surfacePixels: Int,
        appliedUpdates: Int
    ) -> Int? {
        guard keyFramePixels > 0, surfacePixels > 0, appliedUpdates > 0 else {
            return nil
        }

        let bytesPerPixel = Double(keyFrameWireBytes) / Double(keyFramePixels)
        return Int((bytesPerPixel * Double(surfacePixels) * Double(appliedUpdates)).rounded())
    }

    static func savedPercent(actual: Int, estimated: Int?) -> Double? {
        guard let estimated, estimated > 0 else {
            return nil
        }

        return (Double(estimated - actual) / Double(estimated)) * 100
    }

    static func perSecond(_ total: Double, _ seconds: Double) -> Double {
        // A zero-length observation window cannot produce a rate. Reporting zero is honest; dividing would
        // produce infinity and poison every downstream consumer.
        guard seconds > 0 else {
            return 0
        }

        return total / seconds
    }

    static func nextActions(windows: [FramePipelineWindowReport], didObserveFrames: Bool) -> [String] {
        guard didObserveFrames else {
            return [
                "No frames were observed. Confirm a Windows app window is open and its frame stream is subscribed, then re-run with a longer duration.",
                "Run `veil-vmctl app-runtime-status --json` and check mirrorSessions[].frameStreamStatus."
            ]
        }

        var actions: [String] = []

        if windows.contains(where: { $0.droppedTiles.total > 0 }) {
            actions.append(
                "Tiles were dropped. Inspect droppedTiles per window: repeated noSurface or surfaceSizeChanged means key frames are too rare, and payloadRectMismatch or undecodablePayload means the guest and host disagree about the format."
            )
        }

        // The number this whole slice exists to answer.
        if let worst = windows.max(by: { $0.tileCoveragePercent.p50 < $1.tileCoveragePercent.p50 }),
           worst.tileCoveragePercent.p50 >= 50 {
            actions.append(
                "Median tile coverage is \(Int(worst.tileCoveragePercent.p50.rounded()))% of the surface for \(worst.windowId). Dirty-rect tracking is not paying off on this content; revisit the region strategy or the key-frame promotion threshold before changing the codec."
            )
        }

        if let saved = windows.compactMap(\.estimatedWireBytesSavedPercent).min(), saved < 0 {
            actions.append(
                "Tiles cost more wire bytes than full frames would have. Lower the key-frame promotion threshold so large changes stop being sent as tiles."
            )
        }

        if actions.isEmpty {
            actions.append(
                "Record this report alongside a matching run from before the tile change so the improvement is documented rather than assumed."
            )
        }

        return actions
    }

    private static func append(_ sample: Double, to samples: inout [Double]) {
        guard samples.count < maximumRetainedSamples else {
            return
        }

        samples.append(sample)
    }
}
