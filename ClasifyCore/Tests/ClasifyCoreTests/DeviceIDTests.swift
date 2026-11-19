import Testing
@testable import ClasifyCore

/// CLA-145: the device ID from the hardware UUID.
@Suite struct DeviceIDTests {
    /// A stand-in for SHA-256 with the same output size: 32 bytes that depend on every input byte.
    static func fakeHash(_ bytes: [UInt8]) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 32)
        for (i, b) in bytes.enumerated() {
            h[i % 32] = h[i % 32] &* 31 &+ b
            h[(i * 7 + 3) % 32] ^= b &+ UInt8(truncatingIfNeeded: i)
        }
        return h
    }

    let a = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
    let b = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8FA"

    @Test func theSameUUIDGivesTheSameID() {
        #expect(DeviceID.make(uuid: a, sha256: Self.fakeHash) == DeviceID.make(uuid: a, sha256: Self.fakeHash))
    }

    @Test func anotherUUIDGivesAnotherID() {
        #expect(DeviceID.make(uuid: a, sha256: Self.fakeHash) != DeviceID.make(uuid: b, sha256: Self.fakeHash))
    }

    /// No UUID: no ID, never a random one.
    @Test func noUUIDGivesNoID() {
        #expect(DeviceID.make(uuid: nil, sha256: Self.fakeHash) == nil)
        #expect(DeviceID.make(uuid: "", sha256: Self.fakeHash) == nil)
        #expect(DeviceID.make(uuid: a) { _ in [1, 2, 3] } == nil)
    }

    /// The server takes `Device [A-Za-z0-9_-]{32,128}`. The UUID itself never goes out.
    @Test func theIDFitsTheServerAndHidesTheUUID() throws {
        let id = try #require(DeviceID.make(uuid: a, sha256: Self.fakeHash))
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(id.count == 43 && id.allSatisfy { allowed.contains($0) })
        #expect(!id.contains(a) && !id.contains("0A1B2C3D"))
    }

    /// The hash gets the salt and the UUID, nothing else.
    @Test func theHashGetsTheSaltAndTheUUID() {
        var seen: [UInt8] = []
        _ = DeviceID.make(uuid: a) { seen = $0; return Self.fakeHash($0) }
        #expect(seen == Array(("com.cappyai.mypod.activation.v1:" + a).utf8))
    }

    /// RFC 4648 test vectors, in the URL-safe alphabet with no padding.
    @Test func base64URLMatchesTheStandard() {
        #expect(DeviceID.base64URL(Array("".utf8)) == "")
        #expect(DeviceID.base64URL(Array("f".utf8)) == "Zg")
        #expect(DeviceID.base64URL(Array("fo".utf8)) == "Zm8")
        #expect(DeviceID.base64URL(Array("foo".utf8)) == "Zm9v")
        #expect(DeviceID.base64URL(Array("foob".utf8)) == "Zm9vYg")
        #expect(DeviceID.base64URL([0xFB, 0xFF, 0xBF]) == "-_-_")
    }
}
