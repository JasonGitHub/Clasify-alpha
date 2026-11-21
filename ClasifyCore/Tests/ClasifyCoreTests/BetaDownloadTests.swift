import Foundation
import Testing
@testable import ClasifyCore

/// CLA-171: "Get New Beta" opens the feed's DMG url only when it is on dl.getmypod.app.
@Suite struct BetaDownloadTests {
    @Test func aValidURLIsKept() {
        let url = BetaDownload.url("https://dl.getmypod.app/beta/myPod-beta-400.dmg")
        #expect(url?.absoluteString == "https://dl.getmypod.app/beta/myPod-beta-400.dmg")
        #expect(BetaDownload.url("HTTPS://DL.getmypod.app/beta/myPod-beta-400.dmg") != nil)
    }

    @Test func aMissingURLGivesNil() {
        #expect(BetaDownload.url(nil) == nil)
        #expect(BetaDownload.url("") == nil)
        #expect(BetaDownload.url("not a url") == nil)
        #expect(BetaDownload.url("https://dl.getmypod.app") == nil)  // no file
        #expect(BetaDownload.url("https://dl.getmypod.app/") == nil)
    }

    @Test func anotherHostGivesNil() {
        for value in [
            "https://example.com/beta/myPod-beta-400.dmg",
            "https://getmypod.app/beta/myPod-beta-400.dmg",
            "https://evil.dl.getmypod.app/beta/myPod-beta-400.dmg",
            "https://dl.getmypod.app.evil.com/beta/myPod-beta-400.dmg",  // a lookalike host
            "https://dl.getmypod.app@evil.com/beta/myPod-beta-400.dmg",  // a user part
            "https://user@dl.getmypod.app/beta/myPod-beta-400.dmg",
            "https://dl.getmypod.app:8443/beta/myPod-beta-400.dmg",
            "http://dl.getmypod.app/beta/myPod-beta-400.dmg",  // not https
            "file:///dl.getmypod.app/beta/myPod-beta-400.dmg",
        ] {
            #expect(BetaDownload.url(value) == nil, "\(value)")
        }
    }
}
