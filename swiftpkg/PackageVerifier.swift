import Foundation

/// Post-build verification: asserts the finished package matches what build-info
/// declared. A belt-and-suspenders companion to the notarization failure checks.
struct PackageVerifier {
    let runner: any ProcessRunning
    let console: Console
    var fileManager: FileManager = .default

    /// - Parameters:
    ///   - expectedIdentifier: the `identifier` build-info declared.
    ///   - expectedVersion: the `version` build-info declared.
    ///   - signed: signing was requested, so a valid signature must be present.
    ///   - notarized: notarization was requested, so Gatekeeper must accept it.
    func verify(package: URL, expectedIdentifier: String, expectedVersion: String, signed: Bool, notarized: Bool) throws {
        try verifyMetadata(package: package, expectedIdentifier: expectedIdentifier, expectedVersion: expectedVersion)
        if signed {
            let result = try runner.run(executable: ToolPaths.pkgutil, arguments: ["--check-signature", package.path])
            guard result.status == 0 else {
                throw MunkiPkgError.message("Verification failed: package is not validly signed. \(diagnostics(result))")
            }
            console.display("Verified package signature")
        }
        if notarized {
            let result = try runner.run(executable: ToolPaths.spctl, arguments: ["-a", "-vvv", "-t", "install", package.path])
            guard result.status == 0 else {
                throw MunkiPkgError.message("Verification failed: package does not pass Gatekeeper assessment. \(diagnostics(result))")
            }
            console.display("Verified Gatekeeper assessment")
        }
    }

    /// Confirms the built package embeds the identifier and version build-info
    /// declared, so a stale or mismatched artifact can't silently pass `--verify`.
    ///
    /// Best-effort: component packages carry a top-level `PackageInfo`; if it
    /// can't be extracted (e.g. a distribution-style package, whose metadata
    /// lives elsewhere), the check is skipped rather than failing the build.
    private func verifyMetadata(package: URL, expectedIdentifier: String, expectedVersion: String) throws {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("swiftpkg-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let result = try runner.run(executable: ToolPaths.pkgutil, arguments: ["--expand", package.path, scratch.path])
        guard result.status == 0 else {
            throw MunkiPkgError.message("Verification failed: could not expand \(package.lastPathComponent) to inspect its metadata. \(diagnostics(result))")
        }
        // A component package carries a top-level PackageInfo. If it's absent
        // (e.g. a distribution-style package, whose metadata lives elsewhere)
        // the metadata check is skipped rather than failing the build.
        guard let data = try? Data(contentsOf: scratch.appendingPathComponent("PackageInfo")),
              let xml = String(data: data, encoding: .utf8)
        else { return }
        if let mismatch = Self.metadataMismatch(expectedIdentifier: expectedIdentifier, expectedVersion: expectedVersion, packageInfoXML: xml) {
            throw MunkiPkgError.message("Verification failed: \(mismatch)")
        }
        console.display("Verified package identifier and version")
    }

    /// Parses a `PackageInfo` document and returns a human-readable message if
    /// its `identifier`/`version` differ from what was expected, else `nil`.
    /// Pure and side-effect free so it can be unit-tested without a subprocess.
    static func metadataMismatch(expectedIdentifier: String, expectedVersion: String, packageInfoXML: String) -> String? {
        let parser = XMLParser(data: Data(packageInfoXML.utf8))
        let delegate = PackageInfoAttributes()
        parser.delegate = delegate
        guard parser.parse(), let actual = delegate.pkgInfo else { return nil }
        // A PackageInfo we could parse but that omits identifier/version is
        // incomplete and must not silently pass.
        guard let identifier = actual["identifier"] else {
            return "package PackageInfo is missing an identifier."
        }
        if identifier != expectedIdentifier {
            return "package identifier is \"\(identifier)\" but build-info declares \"\(expectedIdentifier)\"."
        }
        guard let version = actual["version"] else {
            return "package PackageInfo is missing a version."
        }
        if version != expectedVersion {
            return "package version is \"\(version)\" but build-info declares \"\(expectedVersion)\"."
        }
        return nil
    }

    private func diagnostics(_ result: ProcessResult) -> String {
        let text = (result.stderrString + result.stdoutString).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "(no output)" : text
    }
}

/// Captures the attributes of a `PackageInfo`'s root `pkg-info` element.
private final class PackageInfoAttributes: NSObject, XMLParserDelegate {
    private(set) var pkgInfo: [String: String]?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "pkg-info", pkgInfo == nil { pkgInfo = attributeDict }
    }
}
