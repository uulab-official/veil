import Testing
@testable import VeilHostShell

struct RFBDesktopSizeFollowUpTests {
    @Test("a refused or no-op resize still asks for the next update, so the picture keeps moving")
    func refusedResizeKeepsStreaming() {
        #expect(RFBDesktopSizeFollowUp.request(responseIsSuccess: false, framebufferSizeChanged: false) == .incrementalUpdate)
        #expect(RFBDesktopSizeFollowUp.request(responseIsSuccess: false, framebufferSizeChanged: true) == .incrementalUpdate)
        #expect(RFBDesktopSizeFollowUp.request(responseIsSuccess: true, framebufferSizeChanged: false) == .incrementalUpdate)
    }

    @Test("an applied resize asks for a full frame at the new size")
    func appliedResizeRedraws() {
        #expect(RFBDesktopSizeFollowUp.request(responseIsSuccess: true, framebufferSizeChanged: true) == .fullUpdate)
    }
}
