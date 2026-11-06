import CoreGraphics
import Foundation

/// Converts a settled macOS content size into a bounded guest framebuffer request.
///
/// All decisions come from the desktop resize design: clamp each axis, cap the total
/// area, round down to a 16-pixel boundary, and suppress sub-threshold or duplicate
/// targets so repeated geometry callbacks cannot produce a resize feedback loop.
public enum RFBDesktopSizePolicy {
    public static let minimumAxisPixels = 640
    public static let maximumAxisPixels = 3_840
    public static let maximumAreaPixels = 8_294_400
    /// The VirtIO GPU display driver pads the scanout width up to a multiple of 16 (measured on
    /// virtio-win 0.1.302), so an 8-aligned width would leave a stale strip at the right edge.
    public static let pixelAlignment = 16
    public static let minimumChangePixels = 16

    /// Returns the guest pixel target for a content size measured in macOS points,
    /// or nil when the input cannot describe a usable desktop.
    public static func target(
        contentSizeInPoints: CGSize,
        backingScaleFactor: Double
    ) -> RFBDesktopResizeTarget? {
        guard contentSizeInPoints.width.isFinite,
              contentSizeInPoints.height.isFinite,
              contentSizeInPoints.width > 0,
              contentSizeInPoints.height > 0,
              backingScaleFactor.isFinite,
              backingScaleFactor > 0 else {
            return nil
        }

        var width = clampAxis(
            roundDownToAlignment(
                Double(contentSizeInPoints.width) * backingScaleFactor,
                alignment: pixelAlignment
            )
        )
        var height = clampAxis(
            roundDownToAlignment(
                Double(contentSizeInPoints.height) * backingScaleFactor,
                alignment: pixelAlignment
            )
        )

        if width * height > maximumAreaPixels {
            let scale = sqrt(Double(maximumAreaPixels) / Double(width * height))
            width = roundDownToAlignment(Double(width) * scale, alignment: pixelAlignment)
            height = roundDownToAlignment(Double(height) * scale, alignment: pixelAlignment)
        }

        return RFBDesktopResizeTarget(widthInPixels: width, heightInPixels: height)
    }

    /// A change is significant when either axis moves by at least the threshold;
    /// sub-threshold jitter on both axes must not generate remote requests.
    public static func isSignificantChange(
        from previous: RFBDesktopResizeTarget?,
        to next: RFBDesktopResizeTarget
    ) -> Bool {
        guard let previous else {
            return true
        }

        return abs(next.widthInPixels - previous.widthInPixels) >= minimumChangePixels
            || abs(next.heightInPixels - previous.heightInPixels) >= minimumChangePixels
    }

    private static func clampAxis(_ value: Int) -> Int {
        min(max(value, minimumAxisPixels), maximumAxisPixels)
    }

    private static func roundDownToAlignment(_ value: Double, alignment: Int) -> Int {
        guard value > 0 else {
            return 0
        }

        return (Int(value) / alignment) * alignment
    }
}

public struct RFBDesktopResizeTarget: Equatable, Sendable {
    public var widthInPixels: Int
    public var heightInPixels: Int

    public init(widthInPixels: Int, heightInPixels: Int) {
        self.widthInPixels = widthInPixels
        self.heightInPixels = heightInPixels
    }
}

/// Computes the aspect-fit rectangle that renders the latest guest framebuffer inside
/// a container, and maps container points into normalized guest coordinates.
///
/// Pointer events outside the viewport map to nil so clicks on letterbox bars never
/// reach the guest. While a resize request is pending the caller keeps passing the
/// last applied framebuffer size, so input geometry never leads the display.
public enum RFBViewportMapper {
    public static func viewport(
        framebufferWidth: Double,
        framebufferHeight: Double,
        containerWidth: Double,
        containerHeight: Double
    ) -> CGRect {
        guard framebufferWidth.isFinite, framebufferHeight.isFinite,
              containerWidth.isFinite, containerHeight.isFinite,
              framebufferWidth > 0, framebufferHeight > 0,
              containerWidth > 0, containerHeight > 0 else {
            return CGRect(origin: .zero, size: .zero)
        }

        let framebufferAspect = framebufferWidth / framebufferHeight
        let containerAspect = containerWidth / containerHeight

        var size = CGSize(
            width: containerWidth,
            height: containerWidth / framebufferAspect
        )
        if containerAspect > framebufferAspect {
            size = CGSize(
                width: containerHeight * framebufferAspect,
                height: containerHeight
            )
        }

        // Equal-aspect inputs can round one pixel above the container; an
        // aspect-fit viewport never exceeds it.
        size.width = min(size.width, containerWidth)
        size.height = min(size.height, containerHeight)

        return CGRect(
            x: (containerWidth - size.width) / 2,
            y: (containerHeight - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Returns normalized guest coordinates in 0...1, or nil when the point falls
    /// outside the viewport. Viewport edges are inclusive so a click exactly on the
    /// corner still maps to the guest corner.
    public static func normalizedGuestPoint(
        pointInContainer: CGPoint,
        viewport: CGRect
    ) -> CGPoint? {
        guard viewport.width > 0, viewport.height > 0,
              pointInContainer.x >= viewport.minX,
              pointInContainer.x <= viewport.maxX,
              pointInContainer.y >= viewport.minY,
              pointInContainer.y <= viewport.maxY else {
            return nil
        }

        let x = (pointInContainer.x - viewport.minX) / viewport.width
        let y = (pointInContainer.y - viewport.minY) / viewport.height
        return CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

/// Tracks the RFB ExtendedDesktopSize lifecycle for one connection.
///
/// The machine is pure: timestamps are injected so timeout behavior is
/// deterministically testable. One request may be in flight; a newer host target
/// replaces the queued target but never overtakes the in-flight request.
public struct RFBDesktopResizeStateMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case unknown
        case probing
        case supported
        case requestPending(RFBDesktopResizeTarget)
        /// QEMU accepted the size and passed it to the guest display device (RFB result 4). The
        /// guest applies it, through the Veil agent today, and QEMU then announces the new size.
        case forwarded(RFBDesktopResizeTarget)
        case applied(RFBDesktopResizeTarget)
        case unsupported
        case rejected(rejection: RFBDesktopResizeRejection, requested: RFBDesktopResizeTarget)
        case timedOut(requested: RFBDesktopResizeTarget)
    }

    public var phase: Phase
    public var requestTimeoutSeconds: TimeInterval
    /// How long a forwarded request may wait for the guest, counted from when it was sent. The agent
    /// applies a size with up to two mode changes, which takes longer than QEMU's own answer.
    public var forwardedTimeoutSeconds: TimeInterval

    /// The newest host target that could not go out while a request was in flight.
    /// It is sent after the in-flight request resolves successfully and is dropped
    /// when the connection disables resize.
    public private(set) var queuedTarget: RFBDesktopResizeTarget?
    private var requestStartedAt: TimeInterval?

    public init(
        phase: Phase = .unknown,
        requestTimeoutSeconds: TimeInterval = 3,
        forwardedTimeoutSeconds: TimeInterval = 10
    ) {
        self.phase = phase
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.forwardedTimeoutSeconds = forwardedTimeoutSeconds
    }

    /// A framebuffer update without an ExtendedDesktopSize rectangle is normal
    /// before the first SetDesktopSize request. RFB servers generally report the
    /// capability only in response to that request, so keep probing instead of
    /// permanently disabling dynamic resolution on the first ordinary frame.
    public mutating func handleFramebufferUpdateWithoutResizeResponse() {
        // Intentionally a no-op while the connection is probing. A later resize
        // request will resolve this state as applied, rejected, or timed out.
    }

    /// An ExtendedDesktopSize rectangle arrived. Success marks the capability as
    /// supported and records the applied framebuffer size; failure is only
    /// meaningful while a request is pending.
    public mutating func handleDesktopSizeResponse(_ response: RFBDesktopSizeResponse) {
        guard response.isSuccess else {
            guard case .requestPending(let requested) = phase,
                  // QEMU reports the currently applied framebuffer dimensions
                  // in a rejection rectangle rather than echoing the requested
                  // dimensions. Its reason field is the explicit reject marker.
                  (response.matches(requested) || response.reasonCode == 1) else {
                return
            }

            // Not a refusal: the request clock keeps running, and the guest's own resize arrives
            // later as an ordinary successful response.
            if response.isForwardedToGuest {
                phase = .forwarded(requested)
                return
            }

            phase = .rejected(
                rejection: RFBDesktopResizeRejection(
                    reasonCode: response.reasonCode,
                    resultCode: response.resultCode
                ),
                requested: requested
            )
            requestStartedAt = nil
            queuedTarget = nil
            return
        }

        let applied = RFBDesktopResizeTarget(
            widthInPixels: response.width,
            heightInPixels: response.height
        )
        switch phase {
        case .requestPending, .forwarded:
            requestStartedAt = nil
        default:
            break
        }
        phase = .applied(applied)
    }

    /// Registers a host-window target. The first target is sent optimistically while
    /// probing because many RFB servers advertise ExtendedDesktopSize only in their
    /// response. Returns nil only when a request is already in flight (the target
    /// then replaces any queued one) or a prior failure disabled resize.
    @discardableResult
    public mutating func request(_ target: RFBDesktopResizeTarget) -> RFBDesktopResizeTarget? {
        switch phase {
        case .supported, .applied, .probing, .unknown:
            phase = .requestPending(target)
            return target
        case .requestPending, .forwarded:
            queuedTarget = target
            return nil
        case .unsupported, .rejected, .timedOut:
            return nil
        }
    }

    /// Transitions an expired in-flight request to ``Phase/timedOut``. Returns the
    /// request that timed out, or nil while nothing is pending or still in budget.
    @discardableResult
    public mutating func checkTimeout(now: TimeInterval) -> RFBDesktopResizeTarget? {
        let requested: RFBDesktopResizeTarget
        let budget: TimeInterval
        switch phase {
        case .requestPending(let target):
            requested = target
            budget = requestTimeoutSeconds
        case .forwarded(let target):
            requested = target
            budget = forwardedTimeoutSeconds
        default:
            return nil
        }
        guard let startedAt = requestStartedAt, now - startedAt >= budget else {
            return nil
        }

        phase = .timedOut(requested: requested)
        requestStartedAt = nil
        queuedTarget = nil
        return requested
    }

    /// Pops the queued host target once the in-flight request resolved successfully.
    /// The caller sends the returned target and confirms with ``markRequestSent``.
    public mutating func takeQueuedTarget() -> RFBDesktopResizeTarget? {
        guard case .applied = phase, let queued = queuedTarget else {
            return nil
        }

        queuedTarget = nil
        return queued
    }

    /// Marks that a request actually went out on the wire.
    public mutating func markRequestSent(_ target: RFBDesktopResizeTarget, now: TimeInterval) {
        phase = .requestPending(target)
        requestStartedAt = now
    }

    /// Reconnect starts a fresh capability probe; nothing is cached across sockets.
    public mutating func resetForReconnect() {
        phase = .probing
        requestStartedAt = nil
        queuedTarget = nil
    }

    /// Concise state for the display status overlay.
    public var presentation: RFBDesktopResizePresentation {
        switch phase {
        case .unknown, .probing:
            return .recovering
        case .supported, .applied:
            return .available
        case .requestPending:
            return .available
        case .forwarded:
            return .forwardedToGuest
        case .unsupported:
            return .scaled
        case .rejected, .timedOut:
            return .rejected
        }
    }
}

public enum RFBDesktopResizePresentation: Equatable, Sendable {
    case available
    /// The guest has to apply the requested size itself; the caller asks the Veil agent to.
    case forwardedToGuest
    case scaled
    case rejected
    case recovering
    case unavailable
}

public struct RFBDesktopResizeRejection: Equatable, Sendable {
    public var reasonCode: Int
    public var resultCode: Int

    public init(reasonCode: Int, resultCode: Int) {
        self.reasonCode = reasonCode
        self.resultCode = resultCode
    }
}
