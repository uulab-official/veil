import Foundation
import Testing
@testable import VeilHostCore

struct QEMUConsoleVisualStateTests {
    @Test("classifies a black console frame as blank")
    func classifiesBlackFrameAsBlank() throws {
        let frame = solidFrame(width: 100, height: 60, red: 0, green: 0, blue: 0)
        let metrics = try QEMUConsoleFrameAnalyzer.analyze(
            width: frame.width,
            height: frame.height,
            rgbaPixels: frame.rgbaPixels
        )

        #expect(metrics.isBlank)
        #expect(QEMUConsoleVisualStateClassifier.classify(metrics: metrics, recognizedText: []) == .blank)
    }

    @Test("classifies a varied visible frame as a desktop candidate")
    func classifiesVisibleFrameAsDesktop() throws {
        let frame = splitFrame(width: 100, height: 60)
        let metrics = try QEMUConsoleFrameAnalyzer.analyze(
            width: frame.width,
            height: frame.height,
            rgbaPixels: frame.rgbaPixels
        )

        #expect(metrics.isUsable)
        #expect(QEMUConsoleVisualStateClassifier.classify(metrics: metrics, recognizedText: []) == .desktop)
    }

    @Test("recognizes Korean Run and UAC text")
    func recognizesKoreanRunAndUACText() throws {
        let frame = splitFrame(width: 100, height: 60)
        let metrics = try QEMUConsoleFrameAnalyzer.analyze(
            width: frame.width,
            height: frame.height,
            rgbaPixels: frame.rgbaPixels
        )

        #expect(QEMUConsoleVisualStateClassifier.classify(
            metrics: metrics,
            recognizedText: ["실행", "열기", "찾아보기"]
        ) == .runDialog)
        #expect(QEMUConsoleVisualStateClassifier.classify(
            metrics: metrics,
            recognizedText: ["사용자 계정 컨트롤", "이 앱이 디바이스를 변경하도록 허용하시겠어요?"]
        ) == .uacPrompt)
    }

    @Test("detects a centered bright modal on a dimmed console")
    func detectsCenteredModalContrast() throws {
        var pixels = [UInt8](repeating: 0, count: 100 * 60 * 4)
        for y in 0..<60 {
            for x in 0..<100 {
                let isModal = x >= 20 && x < 80 && y >= 10 && y < 50
                let value: UInt8 = isModal ? 230 : 24
                let offset = ((y * 100) + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
        let metrics = try QEMUConsoleFrameAnalyzer.analyze(
            width: 100,
            height: 60,
            rgbaPixels: Data(pixels)
        )

        #expect(metrics.hasCenteredModalContrast)
        #expect(QEMUConsoleVisualStateClassifier.classify(metrics: metrics, recognizedText: []) == .modalPrompt)
    }

    @Test("measures meaningful frame changes")
    func measuresMeaningfulFrameChanges() throws {
        let before = solidFrame(width: 100, height: 60, red: 20, green: 20, blue: 20)
        let after = splitFrame(width: 100, height: 60)
        let difference = try QEMUConsoleFrameAnalyzer.difference(from: before, to: after)

        #expect(difference.hasMeaningfulChange)
        #expect(difference.changedPixelRatio > 0.4)
    }

    private func solidFrame(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) -> RFBRenderedFrame {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) {
            pixels.append(contentsOf: [red, green, blue, 255])
        }
        return RFBRenderedFrame(width: width, height: height, rgbaPixels: Data(pixels), sequence: 1)
    }

    private func splitFrame(width: Int, height: Int) -> RFBRenderedFrame {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let isBright = x >= width / 2 || y >= height * 5 / 6
                let value: UInt8 = isBright ? 220 : 35
                pixels.append(contentsOf: [value, UInt8(min(Int(value) + 20, 255)), value, 255])
            }
        }
        return RFBRenderedFrame(width: width, height: height, rgbaPixels: Data(pixels), sequence: 1)
    }
}
