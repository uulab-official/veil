import Foundation

/// Bounds how often a guest-driven event is accepted.
///
/// Guest events cross into things the user owns — the macOS pasteboard, Notification Center — and the guest
/// controls both their content and their timing. Bounding the size of one message does nothing about a
/// megabyte every ten milliseconds.
///
/// Deliberately a value type that is *told* the time rather than reading a clock. Rate limiting that depends on
/// wall-clock time cannot be tested deterministically, and this is exactly the kind of rule that has to be:
/// a limiter that is slightly wrong either lets a flood through or silently discards a user's real work.
public struct GuestEventRateLimiter: Equatable, Sendable {
    /// How many events may be accepted inside ``window``.
    public let maximumEvents: Int
    public let window: TimeInterval

    /// Acceptance times inside the current window, oldest first.
    ///
    /// Bounded by construction: it never holds more than `maximumEvents` entries, because an event is only
    /// appended when the count is already below that.
    private var acceptedAt: [Date] = []

    public init(maximumEvents: Int, window: TimeInterval) {
        self.maximumEvents = max(1, maximumEvents)
        self.window = max(0, window)
    }

    /// Whether an event at `now` is within the rate, recording it if so.
    ///
    /// Only *accepted* events consume budget. A message rejected for another reason — wrong origin, stale
    /// sequence, oversized payload — must not spend the allowance, or a guest could deny the user their
    /// clipboard by sending malformed messages.
    public mutating func allows(at now: Date) -> Bool {
        // Anything older than the window no longer counts. Dropped by prefix rather than filtered, since the
        // array is ordered and this keeps it O(dropped) instead of O(n).
        //
        // Strictly greater, so an event exactly `window` old has expired. Treating the far edge as still inside
        // would mean "30 per 5 seconds" never freed budget until 5 seconds *plus* a tick had passed, which is a
        // slower rate than the configuration says.
        let windowStart = now.addingTimeInterval(-window)
        if let firstInsideWindow = acceptedAt.firstIndex(where: { $0 > windowStart }) {
            if firstInsideWindow > 0 {
                acceptedAt.removeFirst(firstInsideWindow)
            }
        } else {
            acceptedAt.removeAll()
        }

        guard acceptedAt.count < maximumEvents else {
            return false
        }

        acceptedAt.append(now)
        return true
    }

    /// Number of events currently counted against the rate. Exposed for diagnostics and tests.
    public var recordedEventCount: Int {
        acceptedAt.count
    }
}

public extension GuestEventRateLimiter {
    /// Guest clipboard updates.
    ///
    /// A person copies a few times a second at most, and the guest broadcasts on clipboard change. Six per
    /// second is well above deliberate human use and far below what it takes to keep the macOS pasteboard
    /// permanently occupied.
    static var guestClipboard: GuestEventRateLimiter {
        GuestEventRateLimiter(maximumEvents: 30, window: 5)
    }

    /// Windows notifications promoted to macOS notifications.
    ///
    /// These are intrusive and carry guest-chosen text under Veil's identity, so the flood case is a phishing
    /// surface rather than only a nuisance. Twenty a minute covers a busy mail or chat client; beyond that
    /// nothing is being communicated to a human.
    ///
    /// The existing five-entry dedupe history does not help here: rotating six ids defeats it entirely, which
    /// is why a rate limit is the right tool and deduplication is not.
    static var guestNotifications: GuestEventRateLimiter {
        GuestEventRateLimiter(maximumEvents: 20, window: 60)
    }
}
