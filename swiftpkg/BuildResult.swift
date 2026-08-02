import CryptoKit
import Foundation

/// Machine-readable summary of one completed build. Booleans reflect what
/// actually happened, not what build-info requested.
public struct BuildResult: Sendable, Codable, Equatable {
    public let name: String
    public let version: String
    public let identifier: String
    public let pkgPath: String
    public let sha256: String
    public let signed: Bool
    public let notarized: Bool
    public let stapled: Bool

    enum CodingKeys: String, CodingKey {
        case name, version, identifier
        case pkgPath = "pkg_path"
        case sha256, signed, notarized, stapled
    }

    public init(
        name: String, version: String, identifier: String, pkgPath: String,
        sha256: String, signed: Bool, notarized: Bool, stapled: Bool
    ) {
        self.name = name
        self.version = version
        self.identifier = identifier
        self.pkgPath = pkgPath
        self.sha256 = sha256
        self.signed = signed
        self.notarized = notarized
        self.stapled = stapled
    }

    /// Pretty-printed, stable-key JSON for the CLI's `--output-format json`.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// Streaming SHA-256 of a file, lowercase hex. Reads in 1 MB chunks so a large
/// package is not loaded into memory all at once.
public func sha256Hex(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
