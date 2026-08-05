import CoreGraphics
import Foundation
import ImageIO

public enum QEMUConsoleScreenshotReadiness {
    public static func isDesktopVisible(at imageURL: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0,
              image.height > 0 else {
            return false
        }

        let byteCount = image.width * image.height * 4
        var rgbaPixels = Data(count: byteCount)
        let didRender = rgbaPixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return true
        }
        guard didRender,
              let metrics = try? QEMUConsoleFrameAnalyzer.analyze(
                width: image.width,
                height: image.height,
                rgbaPixels: rgbaPixels
              ) else {
            return false
        }

        return QEMUConsoleVisualStateClassifier.classify(
            metrics: metrics,
            recognizedText: []
        ) == .desktop
    }
}
