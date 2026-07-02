import Foundation

public struct WindowFrameRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct WindowFramePoint: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct WindowFrameViewport: Equatable, Sendable {
    public var viewWidth: Double
    public var viewHeight: Double
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var fitsSourceIntoView: Bool

    public init(
        viewWidth: Double,
        viewHeight: Double,
        sourceWidth: Int,
        sourceHeight: Int,
        fitsSourceIntoView: Bool = true
    ) {
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.fitsSourceIntoView = fitsSourceIntoView
    }

    public var visibleFrame: WindowFrameRect {
        guard fitsSourceIntoView,
              viewWidth > 0,
              viewHeight > 0,
              sourceWidth > 0,
              sourceHeight > 0 else {
            return WindowFrameRect(x: 0, y: 0, width: max(viewWidth, 0), height: max(viewHeight, 0))
        }

        let scale = min(viewWidth / Double(sourceWidth), viewHeight / Double(sourceHeight))
        let width = Double(sourceWidth) * scale
        let height = Double(sourceHeight) * scale
        return WindowFrameRect(
            x: (viewWidth - width) / 2,
            y: (viewHeight - height) / 2,
            width: width,
            height: height
        )
    }

    public func guestPoint(forViewX viewX: Double, viewYFromBottom: Double) -> WindowFramePoint? {
        let frame = visibleFrame
        guard frame.width > 0,
              frame.height > 0,
              sourceWidth > 0,
              sourceHeight > 0,
              viewX >= frame.x,
              viewX <= frame.x + frame.width,
              viewYFromBottom >= frame.y,
              viewYFromBottom <= frame.y + frame.height else {
            return nil
        }

        let normalizedX = (viewX - frame.x) / frame.width
        let normalizedYFromBottom = (viewYFromBottom - frame.y) / frame.height
        let x = clamp(Int(normalizedX * Double(sourceWidth)), lower: 0, upper: sourceWidth - 1)
        let y = clamp(Int((1 - normalizedYFromBottom) * Double(sourceHeight)), lower: 0, upper: sourceHeight - 1)
        return WindowFramePoint(x: x, y: y)
    }

    private func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
