import Foundation
import Testing
@testable import SwiftPkgCore
@testable import swiftpkg

struct ExitCodeTests {

    @Test("each error class maps to its documented exit code")
    func errorExitCodes() {
        #expect(SwiftPkgError.message("x").exitCode == 1)
        #expect(SwiftPkgError.projectExists("x").exitCode == 2)
        #expect(SwiftPkgError.invalidConfiguration("x").exitCode == 3)
        #expect(SwiftPkgError.importFailed("x").exitCode == 4)
        #expect(SwiftPkgError.processFailed(tool: "t", message: "m").exitCode == 5)
        #expect(SwiftPkgError.signingFailed(tool: "t", message: "m").exitCode == 6)
        #expect(SwiftPkgError.notarizationFailed("x").exitCode == 7)
    }

    @Test("unknown errors default to exit 1")
    func unknownErrorDefault() {
        struct Other: Error {}
        #expect(exitCode(for: Other()) == 1)
        #expect(exitCode(for: SwiftPkgError.notarizationFailed("x")) == 7)
    }

    // End-to-end through the CLI entry point.
    @Test("create on an existing directory exits 2")
    func createExistingExitsTwo() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("Existing", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let code = await SwiftPkg.run(arguments: ["--create", project.path])
        #expect(code == 2)
    }

    @Test("building a nonexistent project exits 1")
    func buildMissingProjectExitsOne() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let code = await SwiftPkg.run(arguments: [temp.url.appendingPathComponent("Missing").path])
        #expect(code == 1)
    }

    @Test("invalid build-info exits 3")
    func invalidBuildInfoExitsThree() async throws {
        let project = try makeProject(buildInfo: #"{"ownership":"invalid"}"#)
        defer { project.remove() }

        let code = await SwiftPkg.run(arguments: [project.url.path], runner: RecordingRunner())

        #expect(code == 3)
    }

    @Test("unsupported bundle import exits 4")
    func unsupportedBundleImportExitsFour() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let package = temp.url.appendingPathComponent("Input.pkg", isDirectory: true)
        let contents = package.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try write("", to: contents.appendingPathComponent("Unsupported.dist"))
        let project = temp.url.appendingPathComponent("Imported", isDirectory: true)

        let code = await SwiftPkg.run(arguments: ["--import", package.path, project.path], runner: RecordingRunner())

        #expect(code == 4)
    }

    @Test("package build failure with signing skipped exits 5")
    func skippedSigningBuildFailureExitsFive() async throws {
        let project = try makeProject(buildInfo: signedBuildInfo)
        defer { project.remove() }
        let runner = makeBuildRunner(failingExecutable: ToolPaths.pkgbuild)

        let code = await SwiftPkg.run(arguments: ["--skip-signing", project.url.path], runner: runner)

        #expect(code == 5)
    }

    @Test("signed package build failure exits 5")
    func signedPackageBuildFailureExitsFive() async throws {
        let project = try makeProject(buildInfo: signedBuildInfo)
        defer { project.remove() }
        let runner = makeBuildRunner(failingExecutable: ToolPaths.pkgbuild)

        let code = await SwiftPkg.run(arguments: [project.url.path], runner: runner)

        #expect(code == 5)
    }

    @Test("component-package signing failure exits 6")
    func componentSigningFailureExitsSix() async throws {
        let project = try makeProject(buildInfo: signedBuildInfo)
        defer { project.remove() }
        let runner = makeBuildRunner(failingExecutable: ToolPaths.productsign)

        let code = await SwiftPkg.run(arguments: [project.url.path], runner: runner)

        #expect(code == 6)
    }

    @Test("distribution-package signing failure exits 6")
    func distributionSigningFailureExitsSix() async throws {
        let project = try makeProject(buildInfo: distributionBuildInfo)
        defer { project.remove() }
        let runner = makeBuildRunner(failingExecutable: ToolPaths.productsign)

        let code = await SwiftPkg.run(arguments: [project.url.path], runner: runner)

        #expect(code == 6)
    }

    @Test("notarization failure exits 7")
    func notarizationFailureExitsSeven() async throws {
        let project = try makeProject(buildInfo: notarizedBuildInfo)
        defer { project.remove() }
        let runner = makeBuildRunner(failingExecutable: ToolPaths.xcrun)

        let code = await SwiftPkg.run(arguments: [project.url.path], runner: runner)

        #expect(code == 7)
    }

    @Test("stapling failure exits 7")
    func staplingFailureExitsSeven() async throws {
        let project = try makeProject(buildInfo: stapledBuildInfo)
        defer { project.remove() }
        let runner = makeBuildRunner(failingExecutable: ToolPaths.xcrun)
        let submitted = try PropertyListSerialization.data(
            fromPropertyList: ["id": "submission-id"],
            format: .xml,
            options: 0
        )
        let accepted = try PropertyListSerialization.data(
            fromPropertyList: ["status": "Accepted"],
            format: .xml,
            options: 0
        )
        runner.resultProvider = { executable, arguments in
            guard executable == ToolPaths.xcrun else {
                return ProcessResult(status: 0, stdout: Data(), stderr: Data())
            }
            if arguments.starts(with: ["stapler", "staple"]) {
                return self.failedProcessResult
            }
            return ProcessResult(
                status: 0,
                stdout: arguments.contains("submit") ? submitted : accepted,
                stderr: Data()
            )
        }

        let code = await SwiftPkg.run(arguments: [project.url.path], runner: runner)

        #expect(code == 7)
    }

    @Test("conflicting format flags exit 64")
    func usageErrorExit() async {
        let code = await SwiftPkg.run(arguments: ["--json", "--yaml", "/tmp/whatever"])
        #expect(code == usageErrorExitCode)
    }

    private var signedBuildInfo: String {
        #"{"name":"Test.pkg","identifier":"com.example.test","version":"1.0","signing_info":{"identity":"Missing Identity"}}"#
    }

    private var distributionBuildInfo: String {
        #"{"name":"Test.pkg","identifier":"com.example.test","version":"1.0","distribution_style":true,"signing_info":{"identity":"Missing Identity"}}"#
    }

    private var notarizedBuildInfo: String {
        #"{"name":"Test.pkg","identifier":"com.example.test","version":"1.0","signing_info":{"identity":"Missing Identity"},"notarization_info":{"keychain_profile":"missing"}}"#
    }

    private var stapledBuildInfo: String {
        #"{"name":"Test.pkg","identifier":"com.example.test","version":"1.0","signing_info":{"identity":"Missing Identity"},"notarization_info":{"keychain_profile":"missing","staple_timeout":1}}"#
    }

    private var failedProcessResult: ProcessResult {
        ProcessResult(status: 1, stdout: Data(), stderr: Data("failure".utf8))
    }

    private func makeBuildRunner(failingExecutable: String) -> RecordingRunner {
        let runner = RecordingRunner()
        runner.onRun = { executable, arguments in
            if executable == ToolPaths.pkgbuild,
               executable != failingExecutable,
               let output = arguments.last {
                try write("component", to: URL(fileURLWithPath: output))
            }
            if executable == ToolPaths.productbuild,
               executable != failingExecutable,
               let output = arguments.last {
                try write("distribution", to: URL(fileURLWithPath: output))
            }
            if executable == ToolPaths.productsign,
               executable != failingExecutable,
               let output = arguments.last {
                try write("signed", to: URL(fileURLWithPath: output))
            }
        }
        runner.resultProvider = { executable, _ in
            executable == failingExecutable ? self.failedProcessResult : ProcessResult(status: 0, stdout: Data(), stderr: Data())
        }
        return runner
    }

    private func makeProject(buildInfo: String) throws -> TemporaryDirectory {
        let project = try TemporaryDirectory()
        try write(buildInfo, to: project.url.appendingPathComponent("build-info.json"))
        return project
    }
}
