import Foundation

/// Post-build verification: asserts the finished package matches what build-info
/// declared. A belt-and-suspenders companion to the notarization failure checks.
struct PackageVerifier {
    let runner: any ProcessRunning
    let console: Console
    var fileManager: FileManager = .default

    /// - Parameters:
    ///   - expectedIdentifier: the identifier build-info declares for the
    ///     finished package (the product identifier for distributions).
    ///   - expectedVersion: the `version` build-info declared.
    ///   - signed: signing was requested, so a valid signature must be present.
    ///   - notarized: notarization was requested, so Gatekeeper must accept it.
    func verify(package: URL, expectedIdentifier: String, expectedVersion: String, signed: Bool, notarized: Bool) throws {
        try verifyMetadata(package: package, expectedIdentifier: expectedIdentifier, expectedVersion: expectedVersion)
        if signed {
            let result = try runner.run(executable: ToolPaths.pkgutil, arguments: ["--check-signature", package.path])
            guard result.status == 0 else {
                throw SwiftPkgError.message("Verification failed: package is not validly signed. \(diagnostics(result))")
            }
            console.display("Verified package signature")
        }
        if notarized {
            let result = try runner.run(executable: ToolPaths.spctl, arguments: ["-a", "-vvv", "-t", "install", package.path])
            guard result.status == 0 else {
                throw SwiftPkgError.message("Verification failed: package does not pass Gatekeeper assessment. \(diagnostics(result))")
            }
            console.display("Verified Gatekeeper assessment")
        }
    }

    /// Confirms the built package embeds the identifier and version build-info
    /// declared, so a stale or mismatched artifact can't silently pass `--verify`.
    /// Component packages store this metadata in `PackageInfo`; distribution
    /// packages store it in the expanded `Distribution` document.
    private func verifyMetadata(package: URL, expectedIdentifier: String, expectedVersion: String) throws {
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("swiftpkg-verify-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let result = try runner.run(executable: ToolPaths.pkgutil, arguments: ["--expand", package.path, scratch.path])
        guard result.status == 0 else {
            throw SwiftPkgError.message("Verification failed: could not expand \(package.lastPathComponent) to inspect its metadata. \(diagnostics(result))")
        }

        let metadataFile: URL
        let mismatch: String?
        if fileManager.itemExists(at: scratch.appendingPathComponent("Distribution")) {
            metadataFile = scratch.appendingPathComponent("Distribution")
            let xml = try metadataXML(at: metadataFile, package: package, kind: "Distribution")
            mismatch = Self.distributionMetadataMismatch(
                expectedIdentifier: expectedIdentifier,
                expectedVersion: expectedVersion,
                distributionXML: xml
            )
        } else {
            metadataFile = scratch.appendingPathComponent("PackageInfo")
            let xml = try metadataXML(at: metadataFile, package: package, kind: "PackageInfo")
            mismatch = Self.metadataMismatch(
                expectedIdentifier: expectedIdentifier,
                expectedVersion: expectedVersion,
                packageInfoXML: xml
            )
        }
        if let mismatch {
            throw SwiftPkgError.message("Verification failed: \(mismatch)")
        }
        console.display("Verified package identifier and version")
    }

    private func metadataXML(at url: URL, package: URL, kind: String) throws -> String {
        do {
            let data = try Data(contentsOf: url)
            guard let xml = String(data: data, encoding: .utf8) else {
                throw SwiftPkgError.message("Verification failed: expanded \(package.lastPathComponent) has invalid UTF-8 in its \(kind) metadata at \(url.path).")
            }
            return xml
        } catch let error as SwiftPkgError {
            throw error
        } catch {
            throw SwiftPkgError.message(
                "Verification failed: expanded \(package.lastPathComponent) is missing readable "
                    + "\(kind) metadata at \(url.path). \(error.localizedDescription)"
            )
        }
    }

    /// Parses a `PackageInfo` document and returns a human-readable message if
    /// its `identifier`/`version` differ from what was expected, else `nil`.
    /// Pure and side-effect free so it can be unit-tested without a subprocess.
    static func metadataMismatch(expectedIdentifier: String, expectedVersion: String, packageInfoXML: String) -> String? {
        let parser = XMLParser(data: Data(packageInfoXML.utf8))
        let delegate = PackageInfoAttributes()
        parser.delegate = delegate
        guard parser.parse() else {
            return "package PackageInfo is malformed: \(parser.parserError?.localizedDescription ?? "XML parsing failed")"
        }
        guard let actual = delegate.pkgInfo else {
            return "package PackageInfo is missing a pkg-info element."
        }
        // A PackageInfo we could parse but that omits identifier/version is
        // incomplete and must not silently pass.
        guard let identifier = actual["identifier"], !identifier.isEmpty else {
            return "package PackageInfo is missing an identifier."
        }
        if identifier != expectedIdentifier {
            return "package identifier is \"\(identifier)\" but build-info declares \"\(expectedIdentifier)\"."
        }
        guard let version = actual["version"], !version.isEmpty else {
            return "package PackageInfo is missing a version."
        }
        if version != expectedVersion {
            return "package version is \"\(version)\" but build-info declares \"\(expectedVersion)\"."
        }
        return nil
    }

    /// Parses the product metadata emitted by `productbuild` in a distribution
    /// package and returns a human-readable mismatch, or `nil` when it agrees
    /// with build-info.
    static func distributionMetadataMismatch(expectedIdentifier: String, expectedVersion: String, distributionXML: String) -> String? {
        let parser = XMLParser(data: Data(distributionXML.utf8))
        let delegate = DistributionProductAttributes()
        parser.delegate = delegate
        guard parser.parse() else {
            return "package Distribution metadata is malformed: \(parser.parserError?.localizedDescription ?? "XML parsing failed")"
        }
        guard let product = delegate.product else {
            return "package Distribution metadata is missing a product element."
        }
        guard let identifier = product["id"], !identifier.isEmpty else {
            return "package Distribution product metadata is missing an identifier."
        }
        if identifier != expectedIdentifier {
            return "package distribution identifier is \"\(identifier)\" but build-info declares \"\(expectedIdentifier)\"."
        }
        guard let version = product["version"], !version.isEmpty else {
            return "package Distribution product metadata is missing a version."
        }
        if version != expectedVersion {
            return "package distribution version is \"\(version)\" but build-info declares \"\(expectedVersion)\"."
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

/// Captures the product identifier and version from a distribution document.
private final class DistributionProductAttributes: NSObject, XMLParserDelegate {
    private(set) var product: [String: String]?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "product", product == nil { product = attributeDict }
    }
}
