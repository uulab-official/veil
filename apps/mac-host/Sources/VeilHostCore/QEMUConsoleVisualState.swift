import Foundation

public enum QEMUConsoleVisualState: String, Codable, Equatable, Sendable {
    case blank
    case desktop
    case runDialog
    case uacPrompt
    case modalPrompt
    case commandShell
    case unknown
}

public struct QEMUConsoleFrameMetrics: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var sampledPixelCount: Int
    public var meanLuminance: Double
    public var luminanceStandardDeviation: Double
    public var darkPixelRatio: Double
    public var brightPixelRatio: Double
    public var centerMeanLuminance: Double
    public var peripheralMeanLuminance: Double
    public var centerBrightPixelRatio: Double

    public var isBlank: Bool {
        darkPixelRatio >= 0.995
            || (meanLuminance <= 3 && luminanceStandardDeviation <= 4)
    }

    public var isUsable: Bool {
        !isBlank && luminanceStandardDeviation >= 5
    }

    public var hasCenteredModalContrast: Bool {
        peripheralMeanLuminance < 90
            && centerMeanLuminance - peripheralMeanLuminance >= 18
            && centerBrightPixelRatio >= 0.06
    }
}

public struct QEMUConsoleFrameDifference: Codable, Equatable, Sendable {
    public var sampledPixelCount: Int
    public var meanAbsoluteDifference: Double
    public var changedPixelRatio: Double

    public var hasMeaningfulChange: Bool {
        meanAbsoluteDifference >= 2.5 || changedPixelRatio >= 0.008
    }
}

public enum QEMUConsoleFrameAnalyzerError: Error, LocalizedError, Equatable, Sendable {
    case invalidDimensions(width: Int, height: Int)
    case insufficientRGBABytes(expected: Int, actual: Int)
    case mismatchedFrames

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions(let width, let height):
            "Console frame dimensions must be positive; received \(width)x\(height)."
        case .insufficientRGBABytes(let expected, let actual):
            "Console frame requires \(expected) RGBA bytes; received \(actual)."
        case .mismatchedFrames:
            "Console frame comparison requires matching dimensions."
        }
    }
}

public enum QEMUConsoleFrameAnalyzer {
    public static func analyze(
        width: Int,
        height: Int,
        rgbaPixels: Data,
        maximumSampleCount: Int = 50_000
    ) throws -> QEMUConsoleFrameMetrics {
        let expectedByteCount = try expectedByteCount(width: width, height: height)
        guard rgbaPixels.count >= expectedByteCount else {
            throw QEMUConsoleFrameAnalyzerError.insufficientRGBABytes(
                expected: expectedByteCount,
                actual: rgbaPixels.count
            )
        }

        let pixelCount = width * height
        let sampleStride = max(pixelCount / max(maximumSampleCount, 1), 1)
        let bytes = [UInt8](rgbaPixels.prefix(expectedByteCount))
        var sampledPixelCount = 0
        var luminanceSum = 0.0
        var luminanceSquaredSum = 0.0
        var darkPixelCount = 0
        var brightPixelCount = 0
        var centerPixelCount = 0
        var centerLuminanceSum = 0.0
        var centerBrightPixelCount = 0
        var peripheralPixelCount = 0
        var peripheralLuminanceSum = 0.0

        var pixelIndex = 0
        while pixelIndex < pixelCount {
            let byteOffset = pixelIndex * 4
            let luminance = 0.2126 * Double(bytes[byteOffset])
                + 0.7152 * Double(bytes[byteOffset + 1])
                + 0.0722 * Double(bytes[byteOffset + 2])
            luminanceSum += luminance
            luminanceSquaredSum += luminance * luminance
            darkPixelCount += luminance <= 8 ? 1 : 0
            brightPixelCount += luminance >= 235 ? 1 : 0

            let x = pixelIndex % width
            let y = pixelIndex / width
            let isCenter = x >= width / 5
                && x < width * 4 / 5
                && y >= height / 6
                && y < height * 5 / 6
            if isCenter {
                centerPixelCount += 1
                centerLuminanceSum += luminance
                centerBrightPixelCount += luminance >= 210 ? 1 : 0
            } else {
                peripheralPixelCount += 1
                peripheralLuminanceSum += luminance
            }

            sampledPixelCount += 1
            pixelIndex += sampleStride
        }

        let count = Double(max(sampledPixelCount, 1))
        let mean = luminanceSum / count
        let variance = max((luminanceSquaredSum / count) - (mean * mean), 0)
        return QEMUConsoleFrameMetrics(
            width: width,
            height: height,
            sampledPixelCount: sampledPixelCount,
            meanLuminance: mean,
            luminanceStandardDeviation: variance.squareRoot(),
            darkPixelRatio: Double(darkPixelCount) / count,
            brightPixelRatio: Double(brightPixelCount) / count,
            centerMeanLuminance: centerLuminanceSum / Double(max(centerPixelCount, 1)),
            peripheralMeanLuminance: peripheralLuminanceSum / Double(max(peripheralPixelCount, 1)),
            centerBrightPixelRatio: Double(centerBrightPixelCount) / Double(max(centerPixelCount, 1))
        )
    }

    public static func difference(
        from previous: RFBRenderedFrame,
        to current: RFBRenderedFrame,
        maximumSampleCount: Int = 50_000
    ) throws -> QEMUConsoleFrameDifference {
        guard previous.width == current.width,
              previous.height == current.height else {
            throw QEMUConsoleFrameAnalyzerError.mismatchedFrames
        }
        let expectedByteCount = try expectedByteCount(width: current.width, height: current.height)
        guard previous.rgbaPixels.count >= expectedByteCount else {
            throw QEMUConsoleFrameAnalyzerError.insufficientRGBABytes(
                expected: expectedByteCount,
                actual: previous.rgbaPixels.count
            )
        }
        guard current.rgbaPixels.count >= expectedByteCount else {
            throw QEMUConsoleFrameAnalyzerError.insufficientRGBABytes(
                expected: expectedByteCount,
                actual: current.rgbaPixels.count
            )
        }

        let previousBytes = [UInt8](previous.rgbaPixels.prefix(expectedByteCount))
        let currentBytes = [UInt8](current.rgbaPixels.prefix(expectedByteCount))
        let pixelCount = current.width * current.height
        let sampleStride = max(pixelCount / max(maximumSampleCount, 1), 1)
        var sampledPixelCount = 0
        var differenceSum = 0.0
        var changedPixelCount = 0
        var pixelIndex = 0

        while pixelIndex < pixelCount {
            let byteOffset = pixelIndex * 4
            let redDifference = abs(Int(previousBytes[byteOffset]) - Int(currentBytes[byteOffset]))
            let greenDifference = abs(Int(previousBytes[byteOffset + 1]) - Int(currentBytes[byteOffset + 1]))
            let blueDifference = abs(Int(previousBytes[byteOffset + 2]) - Int(currentBytes[byteOffset + 2]))
            let pixelDifference = Double(redDifference + greenDifference + blueDifference) / 3.0
            differenceSum += pixelDifference
            changedPixelCount += pixelDifference >= 24 ? 1 : 0
            sampledPixelCount += 1
            pixelIndex += sampleStride
        }

        let count = Double(max(sampledPixelCount, 1))
        return QEMUConsoleFrameDifference(
            sampledPixelCount: sampledPixelCount,
            meanAbsoluteDifference: differenceSum / count,
            changedPixelRatio: Double(changedPixelCount) / count
        )
    }

    private static func expectedByteCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else {
            throw QEMUConsoleFrameAnalyzerError.invalidDimensions(width: width, height: height)
        }
        return width * height * 4
    }
}

public enum QEMUConsoleVisualStateClassifier {
    public static func classify(
        metrics: QEMUConsoleFrameMetrics,
        recognizedText: [String]
    ) -> QEMUConsoleVisualState {
        if metrics.isBlank {
            return .blank
        }

        let lines = recognizedText.map(normalized)
        let combined = lines.joined(separator: " ")
        if containsAny(combined, [
            "user account control",
            "do you want to allow this app",
            "사용자 계정 컨트롤",
            "이 앱이 디바이스를 변경"
        ]) {
            return .uacPrompt
        }

        let hasRunTitle = lines.contains("run") || lines.contains("실행")
        if (hasRunTitle && containsAny(combined, ["open", "browse", "열기", "찾아보기"]))
            || containsAny(combined, ["v.cmd", "p.cmd"]) {
            return .runDialog
        }

        if containsAny(combined, [
            "windows powershell",
            "command prompt",
            "cmd.exe",
            "veil guest agent",
            "guestagenthealth"
        ]) {
            return .commandShell
        }

        if metrics.hasCenteredModalContrast {
            return .modalPrompt
        }
        if metrics.isUsable {
            return .desktop
        }
        return .unknown
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: value.contains)
    }
}
