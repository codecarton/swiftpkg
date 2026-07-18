import Foundation
import Testing
@testable import SwiftPkgCore

/// A runner returning a fixed status for every call, recording each call.
private final class StatusRunner: ProcessRunning, @unchecked Sendable {
    let status: Int32
    private(set) var calls: [(executable: String, arguments: [String])] = []

    init(status: Int32) { self.status = status }

    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        calls.append((executable, arguments))
        return ProcessResult(status: status, stdout: Data(), stderr: Data("bad".utf8))
    }
}

struct PackageVerifierTests {
    private let package = URL(fileURLWithPath: "/tmp/App-1.0.pkg")

    @Test("an unsigned, un-notarized build runs no verification tools")
    func noChecksWhenNothingDeclared() throws {
        let runner = StatusRunner(status: 0)
        try PackageVerifier(runner: runner, console: Console(quiet: true))
            .verify(package: package, signed: false, notarized: false)
        #expect(runner.calls.isEmpty)
    }

    @Test("a signed build checks the signature and passes when valid")
    func signedPasses() throws {
        let runner = StatusRunner(status: 0)
        try PackageVerifier(runner: runner, console: Console(quiet: true))
            .verify(package: package, signed: true, notarized: false)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].executable == ToolPaths.pkgutil)
        #expect(runner.calls[0].arguments.contains("--check-signature"))
    }

    @Test("a signed build fails when the signature check fails")
    func signedFails() {
        let runner = StatusRunner(status: 1)
        #expect(throws: MunkiPkgError.self) {
            try PackageVerifier(runner: runner, console: Console(quiet: true))
                .verify(package: package, signed: true, notarized: false)
        }
    }

    @Test("a notarized build runs a Gatekeeper assessment")
    func notarizedRunsSpctl() {
        let runner = StatusRunner(status: 1)
        #expect(throws: MunkiPkgError.self) {
            try PackageVerifier(runner: runner, console: Console(quiet: true))
                .verify(package: package, signed: false, notarized: true)
        }
        #expect(runner.calls.contains { $0.executable == ToolPaths.spctl && $0.arguments.contains("install") })
    }
}
