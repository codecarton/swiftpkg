import CryptoKit
import Foundation

/// Build attestation written next to the package as `<pkg>.provenance.json`.
public struct Provenance: Codable, Sendable, Equatable {
    public let tool: String
    public let toolVersion: String
    public let builtAt: String
    public let name: String
    public let version: String
    public let identifier: String
    public let pkgPath: String
    public let sha256: String
    public let inputDigest: String
    public let gitCommit: String?
    public let gitRemote: String?

    enum CodingKeys: String, CodingKey {
        case tool
        case toolVersion = "tool_version"
        case builtAt = "built_at"
        case name, version, identifier
        case pkgPath = "pkg_path"
        case sha256
        case inputDigest = "input_digest"
        case gitCommit = "git_commit"
        case gitRemote = "git_remote"
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// Assembles a `Provenance` from the project, its inputs, and git metadata.
public struct ProvenanceBuilder {
    private let runner: any ProcessRunning
    private let fileManager: FileManager

    public init(runner: any ProcessRunning, fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func build(configuration: PackageConfiguration, output: URL, project: URL, now: Date = Date()) throws -> Provenance {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return Provenance(
            tool: "swiftpkg",
            toolVersion: swiftpkgVersion,
            builtAt: formatter.string(from: now),
            name: configuration.name,
            version: configuration.version,
            identifier: configuration.identifier,
            pkgPath: output.path,
            sha256: try provenanceSHA256(ofFileAt: output),
            inputDigest: try inputDigest(for: project),
            gitCommit: gitOutput(["-C", project.path, "rev-parse", "HEAD"], in: project),
            gitRemote: gitOutput(["-C", project.path, "remote", "get-url", "origin"], in: project).map(Self.sanitizedRemote)
        )
    }

    /// Deterministic digest of the build inputs (payload, scripts, build-info),
    /// hashing each file's project-relative path and contents in sorted order.
    private func inputDigest(for project: URL) throws -> String {
        var entries: [(path: String, url: URL)] = []
        for subdirectory in ["payload", "scripts"] {
            let directory = project.appendingPathComponent(subdirectory, isDirectory: true)
            guard fileManager.directoryExists(at: directory) else { continue }
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let fileURL as URL in enumerator {
                let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isRegular else { continue }
                entries.append((relativePath(of: fileURL, under: project), fileURL))
            }
        }
        for name in ["build-info.plist", "build-info.json", "build-info.yaml", "build-info.yml"] {
            let url = project.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { entries.append((name, url)) }
        }
        entries.sort { $0.path < $1.path }

        var hasher = SHA256()
        for entry in entries {
            hasher.update(data: Data(entry.path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: entry.url))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func relativePath(of url: URL, under project: URL) -> String {
        let base = project.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : url.lastPathComponent
    }

    private func gitOutput(_ arguments: [String], in project: URL) -> String? {
        guard let result = try? runner.run(executable: ToolPaths.git, arguments: arguments), result.status == 0 else { return nil }
        let trimmed = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Removes `user:pass@` userinfo from a remote URL before recording it.
    static func sanitizedRemote(_ remote: String) -> String {
        guard let schemeRange = remote.range(of: "://") else { return remote }
        let authorityAndPath = remote[schemeRange.upperBound...]
        guard let at = authorityAndPath.firstIndex(of: "@") else { return remote }
        let firstSlash = authorityAndPath.firstIndex(of: "/") ?? authorityAndPath.endIndex
        guard at < firstSlash else { return remote }
        return String(remote[..<schemeRange.upperBound]) + String(authorityAndPath[authorityAndPath.index(after: at)...])
    }
}

/// Streaming SHA-256 of a file, lowercase hex.
func provenanceSHA256(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
