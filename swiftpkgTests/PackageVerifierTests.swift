import Foundation
import Testing
@testable import SwiftPkgCore

struct PackageVerifierTests {
    private func makePackage() throws -> (TemporaryDirectory, URL) {
        let temp = try TemporaryDirectory()
        return (temp, temp.url.appendingPathComponent("App-1.0.pkg"))
    }

    private let packageInfo = #"<?xml version="1.0" encoding="utf-8"?><pkg-info identifier="com.example.app" version="1.0" install-location="/"/>"#
    private let distribution = #"<?xml version="1.0" encoding="utf-8"?><installer-gui-script><product id="com.example.app" version="1.0"/></installer-gui-script>"#

    /// Simulates `pkgutil --expand` by writing fixture metadata into the
    /// destination supplied by the verifier. Other commands keep their
    /// default successful result.
    private func runnerExpanding(_ files: [String: String]) -> RecordingRunner {
        let runner = RecordingRunner()
        runner.onRun = { executable, arguments in
            guard executable == ToolPaths.pkgutil, arguments.first == "--expand",
                  let destinationPath = arguments.last
            else { return }
            let destination = URL(fileURLWithPath: destinationPath)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for (relativePath, contents) in files {
                let file = destination.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: file)
            }
        }
        return runner
    }

    /// Expansion succeeds while the named post-build check returns a failure.
    private func runnerFailing(_ failingTool: String) -> RecordingRunner {
        let runner = runnerExpanding(["PackageInfo": packageInfo])
        runner.resultProvider = { executable, arguments in
            if arguments.contains("--expand") { return ProcessResult(status: 0, stdout: Data(), stderr: Data()) }
            let status: Int32 = executable == failingTool ? 1 : 0
            return ProcessResult(status: status, stdout: Data(), stderr: Data("bad".utf8))
        }
        return runner
    }

    @Test("an unsigned, un-notarized build only introspects metadata")
    func metadataOnlyWhenNothingDeclared() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerExpanding(["PackageInfo": packageInfo])
        try PackageVerifier(runner: runner, console: makeConsole())
            .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: false)
        #expect(runner.calls.contains { $0.executable == ToolPaths.pkgutil && $0.arguments.contains("--expand") })
        #expect(!runner.calls.contains { $0.arguments.contains("--check-signature") })
        #expect(!runner.calls.contains { $0.executable == ToolPaths.spctl })
    }

    @Test("a signed build checks the signature and passes when valid")
    func signedPasses() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerExpanding(["PackageInfo": packageInfo])
        try PackageVerifier(runner: runner, console: makeConsole())
            .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: true, notarized: false)
        #expect(runner.calls.contains { $0.executable == ToolPaths.pkgutil && $0.arguments.contains("--expand") })
        #expect(runner.calls.contains { $0.executable == ToolPaths.pkgutil && $0.arguments.contains("--check-signature") })
    }

    @Test("a signed build fails when the signature check fails")
    func signedFails() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerFailing(ToolPaths.pkgutil)
        #expect(throws: SwiftPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: true, notarized: false)
        }
    }

    @Test("verification fails when the package cannot be expanded")
    func failsWhenExpansionFails() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = RecordingRunner()
        runner.result = ProcessResult(status: 1, stdout: Data(), stderr: Data("corrupt".utf8))
        #expect(throws: SwiftPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: false)
        }
    }

    @Test("a notarized build runs a Gatekeeper assessment")
    func notarizedRunsSpctl() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerFailing(ToolPaths.spctl)
        #expect(throws: SwiftPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: true)
        }
        #expect(runner.calls.contains { $0.executable == ToolPaths.spctl && $0.arguments.contains("install") })
    }

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

    @Test("unparseable PackageInfo is reported")
    func malformedPackageInfoIsRejected() {
        let message = PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: "not xml")
        #expect(message?.contains("malformed") == true)
    }

    @Test("malformed PackageInfo fails verification")
    func malformedPackageInfoFailsVerification() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerExpanding(["PackageInfo": "not xml"])
        #expect(throws: SwiftPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: false)
        }
    }

    @Test("a parsed PackageInfo missing identifier or version is rejected")
    func incompleteMetadataRejected() {
        let noIdentifier = #"<pkg-info version="1.0"/>"#
        let noVersion = #"<pkg-info identifier="com.example.app"/>"#
        let emptyIdentifier = #"<pkg-info identifier="" version="1.0"/>"#
        let emptyVersion = #"<pkg-info identifier="com.example.app" version=""/>"#
        #expect(PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: noIdentifier)?.contains("identifier") == true)
        #expect(PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: noVersion)?.contains("version") == true)
        #expect(PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: emptyIdentifier)?.contains("identifier") == true)
        #expect(PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: emptyVersion)?.contains("version") == true)
    }

    @Test("a PackageInfo without a pkg-info element is rejected")
    func missingPackageInfoElementIsRejected() {
        let message = PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: "<package/>")
        #expect(message?.contains("pkg-info") == true)
    }

    @Test("a pkg-info element nested below another root is rejected")
    func nestedPackageInfoIsRejected() {
        let wrapped = #"<wrapper><pkg-info identifier="com.example.app" version="1.0"/></wrapper>"#
        #expect(PackageVerifier.metadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", packageInfoXML: wrapped) != nil)
    }

    @Test("missing expanded PackageInfo fails verification")
    func missingPackageInfoFailsVerification() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerExpanding([:])
        #expect(throws: SwiftPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: false)
        }
    }

    @Test("matching distribution identifier and version produce no mismatch")
    func distributionMetadataMatches() {
        #expect(PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", distributionXML: distribution) == nil)
    }

    @Test("a distribution identifier mismatch is reported")
    func distributionIdentifierMismatch() {
        let message = PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.other", expectedVersion: "1.0", distributionXML: distribution)
        #expect(message?.contains("identifier") == true)
    }

    @Test("a distribution version mismatch is reported")
    func distributionVersionMismatch() {
        let message = PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "2.0", distributionXML: distribution)
        #expect(message?.contains("version") == true)
    }

    @Test("malformed distribution metadata is rejected")
    func malformedDistributionIsRejected() {
        let message = PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", distributionXML: "not xml")
        #expect(message?.contains("malformed") == true)
    }

    @Test("a distribution without product metadata is rejected")
    func missingDistributionProductIsRejected() {
        let message = PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", distributionXML: "<installer-gui-script/>")
        #expect(message?.contains("product") == true)
    }

    @Test("a product below an unexpected distribution root is rejected")
    func nestedDistributionProductIsRejected() {
        let wrapped = #"<wrapper><installer-gui-script><product id="com.example.app" version="1.0"/></installer-gui-script></wrapper>"#
        #expect(PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", distributionXML: wrapped) != nil)
    }

    @Test("a nested product in Distribution is rejected")
    func deeplyNestedDistributionProductIsRejected() {
        let nested = #"<installer-gui-script><wrapper><product id="com.example.app" version="1.0"/></wrapper></installer-gui-script>"#
        #expect(PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", distributionXML: nested) != nil)
    }

    @Test("a distribution product with missing identifier or version is rejected")
    func incompleteDistributionMetadataIsRejected() {
        let noIdentifier = #"<installer-gui-script><product version="1.0"/></installer-gui-script>"#
        let noVersion = #"<installer-gui-script><product id="com.example.app"/></installer-gui-script>"#
        #expect(PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", distributionXML: noIdentifier)?.contains("identifier") == true)
        #expect(PackageVerifier.distributionMetadataMismatch(expectedIdentifier: "com.example.app", expectedVersion: "1.0", distributionXML: noVersion)?.contains("version") == true)
    }

    @Test("distribution packages are verified through Distribution metadata")
    func distributionVerificationUsesProductMetadata() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerExpanding(["Distribution": distribution])
        try PackageVerifier(runner: runner, console: makeConsole())
            .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: false)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].arguments.first == "--expand")
    }

    @Test("a distribution with missing metadata fails verification")
    func missingDistributionMetadataFailsVerification() throws {
        let (temp, package) = try makePackage(); defer { temp.remove() }
        let runner = runnerExpanding(["Distribution": "<installer-gui-script/>"])
        #expect(throws: SwiftPkgError.self) {
            try PackageVerifier(runner: runner, console: makeConsole())
                .verify(package: package, expectedIdentifier: "com.example.app", expectedVersion: "1.0", signed: false, notarized: false)
        }
    }
}
