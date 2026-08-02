import Foundation
import Testing
@testable import SwiftPkgCore

struct ReceiptOnlyBuildTests {

    // A project with neither payload nor scripts is valid: it builds a
    // receipt-only package. pkgbuild must be invoked with --nopayload (and no
    // --root), matching munki-pkg — otherwise the build would fail looking for
    // a payload that isn't there.
    @Test("receipt-only project builds with pkgbuild --nopayload")
    func receiptOnlyUsesNopayload() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("ReceiptOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try write(
            #"{"name":"ReceiptOnly-1.0.pkg","identifier":"com.test.receipt","version":"1.0"}"#,
            to: project.appendingPathComponent("build-info.json")
        )
        let runner = RecordingRunner()
        runner.onRun = { executable, arguments in
            guard executable.hasSuffix("pkgbuild"), let output = arguments.last else { return }
            try write("fake package", to: URL(fileURLWithPath: output))
        }
        let coordinator = PackageBuildCoordinator(fileManager: .default, runner: runner, console: makeConsole())
        try await coordinator.buildPackage(in: project, configuration: PackageBuildOptions(skipsSigning: true))

        let pkgbuild = try #require(runner.calls.first { $0.executable.hasSuffix("pkgbuild") })
        #expect(pkgbuild.arguments.contains("--nopayload"))
        #expect(!pkgbuild.arguments.contains("--root"))
    }
}
