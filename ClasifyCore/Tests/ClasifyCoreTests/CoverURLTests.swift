import Testing
@testable import ClasifyCore

@Test func coverURLAllowsOnlySpotifysCDNAndApplesImageServer() {
    let spotify = String(repeating: "ab", count: 20)
    #expect(CoverURL.url(for: spotify)?.absoluteString == "https://i.scdn.co/image/\(spotify)")
    let apple = "https://is1-ssl.mzstatic.com/image/thumb/Music/x/300x300bb.jpg"
    #expect(CoverURL.url(for: apple)?.absoluteString == apple)
    #expect(CoverURL.url(for: "HTTPS://IS1-SSL.MZSTATIC.COM/a.jpg") != nil)
    for refused in [
        "http://is1-ssl.mzstatic.com/a.jpg",  // not https
        "https://mzstatic.com.example.com/a.jpg", "https://evilmzstatic.com/a.jpg", "https://example.com/a.jpg",
        "https://user@is1-ssl.mzstatic.com/a.jpg", "https://is1-ssl.mzstatic.com:8443/a.jpg",
        "file:///tmp/a.jpg", "abc", "", String(repeating: "g", count: 40),
    ] {
        #expect(CoverURL.url(for: refused) == nil, "\(refused)")
    }
}
