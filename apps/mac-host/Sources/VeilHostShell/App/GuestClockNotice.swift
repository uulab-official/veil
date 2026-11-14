import Foundation

/// The notification that tells the user the Windows clock is wrong and how to fix it once.
///
/// The guest's clock stops while the Mac sleeps. Without the elevated clock task Veil cannot set it,
/// and a Windows clock hours off breaks secure websites, sign-ins, and file times; the menu item that
/// fixes it was easy to miss, since nothing pointed at it.
enum GuestClockNotice {
    /// A clock a few seconds off is not worth a notification.
    static let minimumSkewMilliseconds = 5 * 60 * 1_000

    static let identifier = "org.uulab.veil.guest-clock-wrong"

    static func shouldNotify(needsRepair: Bool, skewMilliseconds: Int?, alreadyNotified: Bool) -> Bool {
        guard needsRepair, !alreadyNotified, let skewMilliseconds else {
            return false
        }
        return abs(skewMilliseconds) >= minimumSkewMilliseconds
    }

    static func skewText(milliseconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = abs(milliseconds) >= 86_400_000 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(abs(milliseconds)) / 1_000) ?? ""
    }

    static func body(skewMilliseconds: Int) -> String {
        let skew = skewText(milliseconds: skewMilliseconds)
        return String(localized: "The clock in Windows is \(skew) off. Choose Set Windows Clock in the Veil menu and approve it once in Windows; after that Veil keeps it right.")
    }
}
