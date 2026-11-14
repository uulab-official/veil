import CoreGraphics
import Foundation

/// Turns the empty area around a popup's content transparent.
///
/// Windows popups such as Paint's text formatting bar live in a larger transparent window, and the agent's
/// capture records the transparent part as black, so the bar showed up inside a wide black slab. Black that
/// touches the frame's edge is backdrop rather than content: it is cleared with a flood fill from the border,
/// which keeps black text and icons inside the popup, since those never reach the edge through black alone.
public enum PopupFrameTransparency {
    /// The largest channel value still treated as backdrop black.
    static let backdropThreshold: UInt8 = 2

    public static func clearingBackdrop(of image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width * height <= 16_000_000 else {
            return nil
        }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            return nil
        }

        clearEdgeConnectedBlack(&pixels, width: width, height: height)

        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )?.makeImage()
        }
    }

    /// Clears every near-black pixel reachable from the border through near-black pixels. RGBA, 4 bytes each.
    static func clearEdgeConnectedBlack(_ pixels: inout [UInt8], width: Int, height: Int) {
        func isBackdrop(_ index: Int) -> Bool {
            let offset = index * 4
            return pixels[offset + 3] != 0
                && pixels[offset] <= backdropThreshold
                && pixels[offset + 1] <= backdropThreshold
                && pixels[offset + 2] <= backdropThreshold
        }

        var stack: [Int] = []
        stack.reserveCapacity(2 * (width + height))
        for x in 0..<width {
            stack.append(x)
            stack.append((height - 1) * width + x)
        }
        for y in 0..<height {
            stack.append(y * width)
            stack.append(y * width + width - 1)
        }

        while let index = stack.popLast() {
            guard isBackdrop(index) else {
                continue
            }
            let offset = index * 4
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0

            let x = index % width
            let y = index / width
            if x > 0 { stack.append(index - 1) }
            if x < width - 1 { stack.append(index + 1) }
            if y > 0 { stack.append(index - width) }
            if y < height - 1 { stack.append(index + width) }
        }
    }
}
