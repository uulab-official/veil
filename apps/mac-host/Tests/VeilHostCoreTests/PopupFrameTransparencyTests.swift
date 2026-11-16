import CoreGraphics
import Foundation
import Testing

@testable import VeilHostCore

@Suite("Popup frame transparency")
struct PopupFrameTransparencyTests {
    @Test("clears black backdrop that reaches the edge and keeps black content inside the popup")
    func clearsEdgeBlackOnly() {
        // 7x5: a white popup body at x 1...5, y 1...3 holding one black "text" pixel at (3, 2), on black.
        let width = 7, height = 5
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let insideBody = (1...5).contains(x) && (1...3).contains(y)
                let value: UInt8 = insideBody ? 255 : 0
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
        let text = (2 * width + 3) * 4
        pixels[text] = 0
        pixels[text + 1] = 0
        pixels[text + 2] = 0

        PopupFrameTransparency.clearEdgeConnectedBlack(&pixels, width: width, height: height)

        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
        #expect(alpha(0, 0) == 0)
        #expect(alpha(6, 4) == 0)
        #expect(alpha(1, 1) == 255)
        // Black text enclosed by the popup body is content, not backdrop.
        #expect(alpha(3, 2) == 255)
    }

    @Test("produces an image the size of the capture")
    func keepsImageSize() throws {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 10, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        let image = try #require(context.makeImage())

        let cleared = try #require(PopupFrameTransparency.clearingBackdrop(of: image))

        #expect(cleared.width == 40)
        #expect(cleared.height == 10)
    }

    @Test("decodes popup and owner from window.created and omits them for ordinary windows")
    func decodesPopupFields() throws {
        let popup = try JSONDecoder().decode(WindowCreatedEvent.self, from: Data(#"""
        {"type":"window.created","windowId":"hwnd:20","processId":1,"appId":"winapp_paint","title":"Popup Host",
         "bounds":{"x":40,"y":120,"width":942,"height":84},"state":"normal","focused":false,
         "popup":true,"ownerWindowId":"hwnd:10"}
        """#.utf8))
        #expect(popup.isPopup)
        #expect(popup.ownerWindowId == "hwnd:10")

        let ordinary = WindowCreatedEvent(
            windowId: "hwnd:10", processId: 1, appId: "winapp_paint", title: "Paint",
            bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600), state: "normal", focused: true
        )
        let encoded = String(decoding: try JSONEncoder().encode(ordinary), as: UTF8.self)
        #expect(!ordinary.isPopup)
        #expect(!encoded.contains("popup"))
        #expect(!encoded.contains("ownerWindowId"))
    }
}
