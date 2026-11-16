import CoreGraphics
import Foundation
import Testing
import VeilHostCore
@testable import VeilHostShell

@MainActor
struct WindowsAppFirstFrameReadinessTests {
    @Test("a decodable PNG is renderable")
    func acceptsDecodablePNG() throws {
        let frame = try JSONDecoder().decode(WindowFrameEvent.self, from: Data(Self.pngFrameJSON.utf8))
        let session = Self.session(captureState: .streaming, frame: frame)

        #expect(WindowsAppFirstFrameReadiness.resolve(session: session, compositedImage: nil) == .ready)
    }

    @Test("a composited frame needs its compositor surface")
    func requiresCompositorSurface() throws {
        let frame = try JSONDecoder().decode(WindowFrameEvent.self, from: Data(Self.compositedFrameJSON.utf8))
        let session = Self.session(captureState: .streaming, frame: frame)

        #expect(WindowsAppFirstFrameReadiness.resolve(session: session, compositedImage: nil) == .waiting)
        #expect(WindowsAppFirstFrameReadiness.resolve(session: session, compositedImage: Self.pixelImage()) == .ready)
    }

    @Test("capture unavailable is a terminal readiness state")
    func reportsUnavailableCapture() {
        #expect(WindowsAppFirstFrameReadiness.resolve(session: Self.session(captureState: .unavailable), compositedImage: nil) == .unavailable)
    }

    @Test("missing or malformed frames keep waiting")
    func waitsForMissingOrMalformedFrame() throws {
        #expect(WindowsAppFirstFrameReadiness.resolve(session: nil, compositedImage: nil) == .waiting)
        #expect(WindowsAppFirstFrameReadiness.resolve(session: Self.session(captureState: .pending), compositedImage: nil) == .waiting)

        let malformed = try JSONDecoder().decode(WindowFrameEvent.self, from: Data(Self.malformedFrameJSON.utf8))
        #expect(WindowsAppFirstFrameReadiness.resolve(session: Self.session(captureState: .streaming, frame: malformed), compositedImage: nil) == .waiting)
    }

    @Test("polling resolves after a waiting read")
    func pollsUntilReady() async {
        var reads = 0
        let result = await WindowsAppFirstFrameReadiness.wait(
            timeoutSeconds: 1,
            pollInterval: .milliseconds(1),
            sessionProvider: {
                reads += 1
                return Self.session(captureState: .streaming, frame: reads > 1 ? Self.pngFrame() : nil)
            },
            compositedImageProvider: { _ in nil }
        )

        #expect(result == .ready)
        #expect(reads >= 2)
    }

    @Test("dock focus stays on the launcher while the current session is not renderable")
    func focusRequiresRenderableSession() {
        let session = Self.session(captureState: .pending)

        #expect(WindowsAppWindowPresentationReadiness.resolve(
            session: session,
            compositedImage: nil
        ) == .blocked(.firstFramePending))
    }

    @Test("manual recovery acknowledgement stays blocked until its reset stream produces a frame")
    func recoveryAcknowledgementRequiresNewFrame() {
        let acknowledgedSession = Self.session(captureState: .pending)
        let readySession = Self.session(captureState: .streaming, frame: Self.pngFrame())

        #expect(WindowsAppWindowPresentationReadiness.resolve(
            session: acknowledgedSession,
            compositedImage: nil
        ) == .blocked(.firstFramePending))
        #expect(WindowsAppWindowPresentationReadiness.resolve(
            session: readySession,
            compositedImage: nil
        ) == .ready)
    }

    @Test("a session removed after coordinator readiness is a typed presentation failure")
    func rejectsDisappearedSessionAtFinalPresentation() {
        #expect(WindowsAppWindowPresentationReadiness.resolve(
            session: nil,
            compositedImage: nil
        ) == .blocked(.mirrorSessionMissing))
        #expect(
            WindowsAppWindowPresentationFailure.mirrorSessionMissing.userMessage(appName: "Notepad")
                == "Notepad opened in Windows, but its app screen closed before Veil could show it. Open Notepad again to retry."
        )
    }

    @Test("final presentation rechecks a session that became unrenderable after coordinator readiness")
    func rechecksUnrenderableSessionAtFinalPresentation() {
        let readySession = Self.session(captureState: .streaming, frame: Self.pngFrame())
        let resetSession = Self.session(captureState: .pending)

        #expect(WindowsAppFirstFrameReadiness.resolve(
            session: readySession,
            compositedImage: nil
        ) == .ready)
        #expect(WindowsAppWindowPresentationReadiness.resolve(
            session: resetSession,
            compositedImage: nil
        ) == .blocked(.firstFramePending))
    }

    @Test("launch stages have product copy")
    func stageCopy() {
        #expect(OneClickAppLaunchStage.preparingApp.userMessage(appName: "Notepad") == "Preparing Notepad.")
        #expect(OneClickAppLaunchStage.startingOrResumingWindows.userMessage(appName: "Notepad") == "Starting Windows for Notepad.")
        #expect(OneClickAppLaunchStage.connectingAppBridge.userMessage(appName: "Notepad") == "Connecting Windows apps for Notepad.")
        #expect(OneClickAppLaunchStage.recoveringRuntime.userMessage(appName: "Notepad") == "Restoring the Windows connection for Notepad.")
        #expect(OneClickAppLaunchStage.repairingAppBridge(attempt: 1).userMessage(appName: "Notepad") == "Repairing the Windows app connection for Notepad (1/2).")
        #expect(OneClickAppLaunchStage.openingApp.userMessage(appName: "Notepad") == "Opening Notepad in Windows.")
        #expect(OneClickAppLaunchStage.waitingForFirstFrame.userMessage(appName: "Notepad") == "Opening Notepad screen.")
        #expect(OneClickAppLaunchStage.restartingFrameStream.userMessage(appName: "Notepad") == "Refreshing Notepad screen once.")
        #expect(OneClickAppLaunchStage.ready.userMessage(appName: "Notepad") == "Notepad is ready.")
    }

    @Test("manual recovery waits for a later frame without another user action")
    func recoveryContinuesUntilFrameArrives() async throws {
        var reads = 0
        let result = try await WindowsAppWindowPresentationReadiness.wait(
            timeoutSeconds: 1, pollInterval: .milliseconds(1),
            sessionProvider: {
                reads += 1
                return Self.session(captureState: reads > 1 ? .streaming : .pending,
                                    frame: reads > 1 ? Self.pngFrame() : nil)
            },
            compositedImageProvider: { _ in nil }
        )
        #expect(result == .ready)
        #expect(reads > 1)
    }

    @Test("closing a window during recovery ends the wait without presenting it")
    func recoveryStopsWhenWindowCloses() async throws {
        var reads = 0
        let result = try await WindowsAppWindowPresentationReadiness.wait(
            timeoutSeconds: 1, pollInterval: .milliseconds(1),
            sessionProvider: {
                reads += 1
                return reads == 1 ? Self.session(captureState: .pending) : nil
            }, compositedImageProvider: { _ in nil }
        )
        #expect(result == .blocked(.mirrorSessionMissing))
        #expect(reads == 2)
    }

    @Test("a recovery without a frame stops at its timeout")
    func recoveryHasBoundedTimeout() async throws {
        let result = try await WindowsAppWindowPresentationReadiness.wait(
            timeoutSeconds: 0,
            sessionProvider: { Self.session(captureState: .pending) },
            compositedImageProvider: { _ in nil }
        )
        #expect(result == .blocked(.firstFrameTimedOut))
    }

    @Test("cancelled recovery does not read or present an otherwise ready session")
    func recoveryCancellationWinsOverReadiness() async {
        var reads = 0
        await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) {
                _ = try await WindowsAppWindowPresentationReadiness.wait(
                    timeoutSeconds: 1,
                    sessionProvider: {
                        reads += 1
                        return Self.session(captureState: .streaming, frame: Self.pngFrame())
                    }, compositedImageProvider: { _ in nil }
                )
            }
        }.value
        #expect(reads == 0)
    }

    private static let pngFrameJSON = #"{"type":"window.frame","windowId":"hwnd:0003029A","frameId":"frame_000001","sequence":1,"format":"png","width":1,"height":1,"scale":1,"encodedData":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="}"#
    private static let compositedFrameJSON = #"{"type":"window.frame","windowId":"hwnd:0003029A","frameId":"frame_000002","sequence":2,"format":"composited","width":1,"height":1,"scale":1,"encodedData":""}"#
    private static let malformedFrameJSON = #"{"type":"window.frame","windowId":"hwnd:0003029A","frameId":"frame_bad","sequence":3,"format":"png","width":1,"height":1,"scale":1,"encodedData":"not-base64"}"#

    private static func pngFrame() -> WindowFrameEvent {
        try! JSONDecoder().decode(WindowFrameEvent.self, from: Data(pngFrameJSON.utf8))
    }

    private static func session(captureState: WindowCaptureState, frame: WindowFrameEvent? = nil) -> WindowMirrorSession {
        WindowMirrorSession(
            window: WindowCreatedEvent(windowId: "hwnd:0003029A", processId: 1, appId: "winapp_notepad", title: "Notepad", bounds: WindowBounds(x: 0, y: 0, width: 1, height: 1), state: "normal", focused: true),
            connectionMode: .agent,
            captureState: captureState,
            latestFrame: frame
        )
    }

    private static func pixelImage() -> CGImage {
        let data = Data([0xFF]) as CFData
        let provider = CGDataProvider(data: data)!
        return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 1, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
