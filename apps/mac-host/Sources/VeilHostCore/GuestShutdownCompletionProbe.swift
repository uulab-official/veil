import CoreGraphics
import Foundation
import ImageIO

/// Tells whether a Windows asked to shut down has finished, for a VM that never powers off afterwards
/// (`GracefulWindowsShutdown.settledSeconds`).
///
/// Three signs must agree:
/// - the tools are gone;
/// - QEMU is nearly idle;
/// - the display is black.
///
/// Idle alone is not enough: Windows waiting on "This app is preventing shutdown" is also idle, and
/// turning it off there would lose the user's unsaved work. That screen is not black.
public final class GuestShutdownCompletionProbe: @unchecked Sendable {
    /// Brightest channel value a pixel may have for the display to count as black.
    static let darkThreshold: UInt8 = 24

    private let activity: QEMUProcessActivity
    private let monitorSocketPath: String
    private let captureURL: URL

    public init(pid: Int32, monitorSocketPath: String) {
        activity = QEMUProcessActivity(pid: pid)
        self.monitorSocketPath = monitorSocketPath
        captureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("veil-shutdown-check-\(pid).png")
    }

    public convenience init?(launchRecord: QEMULaunchRecord?) {
        guard let launchRecord, let pid = launchRecord.pid else {
            return nil
        }
        self.init(pid: pid, monitorSocketPath: launchRecord.monitorSocketPath)
    }

    public func isFinished(toolsConnected: Bool) -> Bool {
        // Sampled every call so the next call measures only its own interval.
        let fraction = activity.coreFractionSinceLastSample()
        guard !toolsConnected, let fraction, fraction < QEMUProcessActivity.idleCoreFraction else {
            return false
        }
        try? FileManager.default.removeItem(at: captureURL)
        QEMUVMRuntimeBooter.captureConsoleScreenshot(
            monitorSocketURL: URL(fileURLWithPath: monitorSocketPath),
            imageURL: captureURL
        )
        defer { try? FileManager.default.removeItem(at: captureURL) }
        guard let source = CGImageSourceCreateWithURL(captureURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return false
        }
        return Self.isBlack(image)
    }

    /// Samples a grid of pixels; any brighter than `darkThreshold` means something is drawn.
    static func isBlack(_ image: CGImage) -> Bool {
        let width = 64
        let height = 48
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return false
        }
        for index in stride(from: 0, to: width * height * 4, by: 4)
        where max(pixels[index], pixels[index + 1], pixels[index + 2]) > darkThreshold {
            return false
        }
        return true
    }
}
