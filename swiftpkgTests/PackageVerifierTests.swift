import Foundation
import Testing
@testable import SwiftPkgCore

struct PackageVerifierTests {
    private func makePackage() throws -> (TemporaryDirectory, URL) {
        let temp = try TemporaryDirectory()
        return (temp, temp.url.appendingPathComponent("App-1.0.pkg"))
    }

    @Test("an unsigned, un-notarized build only introspects metadata")
    func metadataOnlyWhenNothingDeclared() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = RecordingRunner()
        try PackageVerifier(runner: runner, console: makeConsole())
            .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: false)
        #expect(runner.calls.allSatisfy { $0.arguments.contains("--expand") })
        #expect(!runner.calls.contains { $0.arguments.contains("--check-signature") })
        #expect(!runner.calls.contains { $0.executable == ToolPaths.spctl })
    }

    @Test("a signed build checks the signature and passes when valid")
    func signedPasses() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = RecordingRunner()
        try PackageVerifier(runner: runner, console: makeConsole())
            .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: true, notarized: false)
        #expect(runner.calls.contains { $0.executable == ToolPaths.pkgutil && $0.arguments.contains("--check-signature") })
    }

    @Test("a signed build fails when the signature check fails")
    func signedFails() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = RecordingRunner()
        runner.result = ProcessResult(status: 1, stdout: Data(), stderr: Data("bad".utf8))
        #expect(throws: MunkiPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: true, notarized: false)
        }
    }

    @Test("a notarized build runs a Gatekeeper assessment")
    func notarizedRunsSpctl() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = RecordingRunner()
        runner.result = ProcessResult(status: 1, stdout: Data(), stderr: Data("bad".utf8))
        #expect(throws: MunkiPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: true)
        }
        #expect(runner.calls.contains { $0.executable == ToolPaths.spctl && $0.arguments.contains("install") })
    }

    private let packageInfo = #"<?xml version="1.0" encoding="utf-8"?><pkg-info identifier="com.example.app" version="1.0" install-location="/"/>"#

    @Test("matching identifier and version produce no mismatch")
    func metadataMatches() {
        #expect(PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: packageInfo) == nil)
    }

    @Test("a mismatched identifier is reported")
    func identifierMismatch() {
        let message = PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.other", expectedVersion: "1.0", packageInfoXML: packageInfo)
        #expect(message?.contains("identifier") == true)
    }

    @Test("a mismatched version is reported")
    func versionMismatch() {
        let message = PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "2.0", packageInfoXML: packageInfo)
        #expect(message?.contains("version") == true)
    }

    @Test("unparseable PackageInfo is treated as no mismatch (best-effort)")
    func malformedPackageInfoSkips() {
        #expect(PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: "not xml") == nil)
    }
}
