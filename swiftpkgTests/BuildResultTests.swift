import Foundation
import Testing
@testable import SwiftPkgCore

struct BuildResultTests {

    @Test("sha256Hex matches the known vector for \"abc\"")
    func sha256KnownVector() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appendingPathComponent("abc.bin")
        try write("abc", to: file)
        let digest = try sha256Hex(ofFileAt: file)
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("sha256Hex handles files that span multiple read chunks")
    func sha256LargeFile() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = temp.url.appendingPathComponent("big.bin")
        try Data(repeating: 0x61, count: 3 * (1 << 20) + 7).write(to: file)
        let hex = try sha256Hex(ofFileAt: file)
        // Known digest of 3 MiB + 7 bytes of 0x61, so a chunk-boundary bug in the
        // streaming hash would change the value, not just the shape.
        #expect(hex == "7d8aedf62548b6943c912ca5192d7a2c13322cd689d7a47d4b3944b4bb2e30c6")
    }

    @Test("manifest JSON uses snake_case pkg_path and round-trips")
    func jsonRoundTrip() throws {
        let result = BuildResult(
            name: "App-1.0.pkg", version: "1.0", identifier: "com.example.app",
            pkgPath: "/tmp/App-1.0.pkg", sha256: "deadbeef",
            signed: true, notarized: false, stapled: false
        )
        let json = try result.jsonString()
        #expect(json.contains("\"pkg_path\""))
        #expect(!json.contains("\"pkgPath\""))
        let decoded = try JSONDecoder().decode(BuildResult.self, from: Data(json.utf8))
        #expect(decoded == result)
    }
}
