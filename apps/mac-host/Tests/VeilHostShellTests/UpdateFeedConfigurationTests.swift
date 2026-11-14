import Foundation
import Testing

@testable import VeilHostShell

@Suite("Update feed configuration")
struct UpdateFeedConfigurationTests {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()
    private let feed = "https://github.com/uulab-official/veil/releases/download/appcast/appcast.xml"

    @Test("A release build with an HTTPS feed and an Ed25519 key can update")
    func releaseBuild() {
        let configuration = UpdateFeedConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": key])
        #expect(configuration?.feedURL.absoluteString == feed)
        #expect(configuration?.publicKey == key)
    }

    @Test("A development build, a plain HTTP feed, or a malformed key cannot")
    func otherBuilds() {
        #expect(UpdateFeedConfiguration(info: [:]) == nil)
        #expect(UpdateFeedConfiguration(info: ["SUFeedURL": feed]) == nil)
        #expect(UpdateFeedConfiguration(info: ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": key]) == nil)
        #expect(UpdateFeedConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": "not a key"]) == nil)
        #expect(UpdateFeedConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": Data(count: 16).base64EncodedString()]) == nil)
    }
}
