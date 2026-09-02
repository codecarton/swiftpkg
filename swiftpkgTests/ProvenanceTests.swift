import Foundation
import Testing
@testable import SwiftPkgCore

private final class GitRunner: ProcessRunning, @unchecked Sendable {
    var commit = "abc123"
    var remote = "https://github.com/example/repo.git"

    func run(executable: String, arguments: [String]) throws -> ProcessResult {
        let out: String
        if arguments.contains("rev-parse") { out = commit }
        else if arguments.contains("remote") { out = remote }
        else { out = "" }
        return ProcessResult(status: 0, stdout: Data((out + "\n").utf8), stderr: Data())
    }
}

struct ProvenanceTests {

    @Test("sanitizedRemote strips user:pass@ userinfo but leaves clean URLs")
    func sanitizesRemote() {
        #expect(ProvenanceBuilder.sanitizedRemote("https://user:pass@github.com/x/y.git") == "https://github.com/x/y.git")
        #expect(ProvenanceBuilder.sanitizedRemote("https://token@github.com/x/y.git") == "https://github.com/x/y.git")
        #expect(ProvenanceBuilder.sanitizedRemote("https://github.com/x/y.git") == "https://github.com/x/y.git")
        #expect(ProvenanceBuilder.sanitizedRemote("git@github.com:x/y.git") == "git@github.com:x/y.git") // scp-style, no ://
    }

    @Test("provenance captures git metadata and a stable input digest")
    func buildsProvenance() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try write("hello", to: payload.appendingPathComponent("file.txt"))
        try write(#"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, to: project.appendingPathComponent("build-info.json"))
        let output = project.appendingPathComponent("build/App-1.0.pkg")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("PKGDATA", to: output)

        let runner = GitRunner()
        runner.remote = "https://user:secret@github.com/example/repo.git"
        let builder = ProvenanceBuilder(runner: runner, fileManager: .default)
        let config = try BuildInfoStore.load(from: project, requestedFormat: nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let provenance = try builder.build(configuration: config, output: output, project: project, now: now)

        #expect(provenance.tool == "swiftpkg")
        #expect(provenance.gitCommit == "abc123")
        #expect(provenance.gitRemote == "https://github.com/example/repo.git") // credentials stripped
        #expect(provenance.identifier == "com.example.app")
        #expect(provenance.sha256.count == 64)
        #expect(provenance.sha256 == (try sha256Hex(ofFileAt: output)))
        #expect(provenance.inputDigest.count == 64)

        // Input digest is deterministic for identical inputs.
        let again = try builder.build(configuration: config, output: output, project: project, now: now)
        #expect(again.inputDigest == provenance.inputDigest)

        // JSON uses snake_case keys and round-trips.
        let json = try provenance.jsonString()
        #expect(json.contains("\"input_digest\""))
        #expect(json.contains("\"git_commit\""))
        let decoded = try JSONDecoder().decode(Provenance.self, from: Data(json.utf8))
        #expect(decoded == provenance)
    }

    @Test("input digest changes when an input file changes")
    func digestChangesWithInputs() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try write(#"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, to: project.appendingPathComponent("build-info.json"))
        let output = project.appendingPathComponent("build/App-1.0.pkg")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("PKG", to: output)
        let builder = ProvenanceBuilder(runner: GitRunner(), fileManager: .default)
        let config = try BuildInfoStore.load(from: project, requestedFormat: nil)

        try write("v1", to: payload.appendingPathComponent("file.txt"))
        let first = try builder.build(configuration: config, output: output, project: project).inputDigest
        try write("v2", to: payload.appendingPathComponent("file.txt"))
        let second = try builder.build(configuration: config, output: output, project: project).inputDigest
        #expect(first != second)
    }

    @Test("input digest follows effective substituted scripts without recording their values")
    func digestChangesWithEffectiveScripts() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        let effectiveScripts = temp.url.appendingPathComponent("effective-scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: effectiveScripts, withIntermediateDirectories: true)
        try write("#!/bin/sh\necho ${TOKEN}\n", to: scripts.appendingPathComponent("postinstall"))
        try write("#!/bin/sh\necho first-secret\n", to: effectiveScripts.appendingPathComponent("postinstall"))
        try write(#"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, to: project.appendingPathComponent("build-info.json"))
        let output = project.appendingPathComponent("build/App-1.0.pkg")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("PKG", to: output)

        let builder = ProvenanceBuilder(runner: GitRunner(), fileManager: .default)
        let config = try BuildInfoStore.load(from: project, requestedFormat: nil)
        let first = try builder.build(configuration: config, output: output, project: project, effectiveScripts: effectiveScripts).inputDigest

        try write("#!/bin/sh\necho second-secret\n", to: effectiveScripts.appendingPathComponent("postinstall"))
        let second = try builder.build(configuration: config, output: output, project: project, effectiveScripts: effectiveScripts)
        let json = try second.jsonString()

        #expect(first != second.inputDigest)
        #expect(!json.contains("second-secret"))
        #expect(!json.contains("first-secret"))
    }

    @Test("project, explicit, and inherited substitutions share a digest contract")
    func substitutionSourcesShareDigestContract() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        let explicitEnvironment = temp.url.appendingPathComponent("selected.env")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try write("#!/bin/sh\necho ${SWIFTPKG_ENDPOINT}\n", to: scripts.appendingPathComponent("postinstall"))
        try write(#"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, to: project.appendingPathComponent("build-info.json"))
        try write("SWIFTPKG_ENDPOINT=https://example.test\nSWIFTPKG_UNUSED=one\n", to: project.appendingPathComponent(".env"))
        try write("SWIFTPKG_ENDPOINT=https://example.test\nSWIFTPKG_UNUSED=two\n", to: explicitEnvironment)

        let output = project.appendingPathComponent("build/App-1.0.pkg")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("PKG", to: output)
        let builder = ProvenanceBuilder(runner: GitRunner(), fileManager: .default)
        let config = try BuildInfoStore.load(from: project, requestedFormat: nil)
        let sourceVariables: [[String: String]] = [
            EnvLoader.merge(fileVariables: try EnvLoader.load(from: project.appendingPathComponent(".env").path), inheritsEnvironment: false),
            EnvLoader.merge(fileVariables: try EnvLoader.load(from: explicitEnvironment.path), inheritsEnvironment: false),
            EnvLoader.merge(
                fileVariables: [:],
                inheritsEnvironment: true,
                environment: ["SWIFTPKG_ENDPOINT": "https://example.test", "SWIFTPKG_UNUSED": "three"]
            ),
        ]

        var digests: [String] = []
        for (index, variables) in sourceVariables.enumerated() {
            let staging = temp.url.appendingPathComponent("staging-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let processed = try #require(try ScriptEnvironment.process(scriptsDir: scripts, into: staging, with: variables))
            let provenance = try builder.build(configuration: config, output: output, project: project, effectiveScripts: processed.directory)
            digests.append(provenance.inputDigest)
            let json = try provenance.jsonString()
            #expect(!json.contains("https://example.test"))
        }

        #expect(Set(digests).count == 1)

        let changedStaging = temp.url.appendingPathComponent("staging-changed", isDirectory: true)
        try FileManager.default.createDirectory(at: changedStaging, withIntermediateDirectories: true)
        let changedVariables = ["SWIFTPKG_ENDPOINT": "https://changed.test", "SWIFTPKG_UNUSED": "still-unused"]
        let changed = try #require(try ScriptEnvironment.process(scriptsDir: scripts, into: changedStaging, with: changedVariables))
        let changedDigest = try builder.build(configuration: config, output: output, project: project, effectiveScripts: changed.directory).inputDigest
        #expect(changedDigest != digests[0])
    }

    @Test("package provenance hashes the scripts that pkgbuild actually receives")
    func coordinatorUsesEffectiveScripts() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try write("#!/bin/sh\necho ${SWIFTPKG_ENDPOINT}\n", to: scripts.appendingPathComponent("postinstall"))
        try write(#"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, to: project.appendingPathComponent("build-info.json"))
        let environment = project.appendingPathComponent(".env")
        try write("SWIFTPKG_ENDPOINT=first-secret\n", to: environment)

        let runner = RecordingRunner()
        runner.onRun = { executable, arguments in
            guard executable.hasSuffix("pkgbuild"), let output = arguments.last else { return }
            try write("fake package", to: URL(fileURLWithPath: output))
        }
        let coordinator = PackageBuildCoordinator(fileManager: .default, runner: runner, console: makeConsole())
        let options = PackageBuildOptions(skipsSigning: true, writesProvenance: true)
        try await coordinator.buildPackage(in: project, configuration: options)
        let sidecar = project.appendingPathComponent("build/App-1.0.pkg.provenance.json")
        let first = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: sidecar))

        try write("SWIFTPKG_ENDPOINT=second-secret\n", to: environment)
        try await coordinator.buildPackage(in: project, configuration: options)
        let second = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: sidecar))
        let json = try String(contentsOf: sidecar, encoding: .utf8)

        #expect(first.inputDigest != second.inputDigest)
        #expect(!json.contains("first-secret"))
        #expect(!json.contains("second-secret"))
        #expect(runner.calls.contains { $0.executable.hasSuffix("pkgbuild") && $0.arguments.contains { $0.hasSuffix("/env-scripts") } })
    }

    @Test("unused environment values do not change the effective script digest")
    func unusedEnvironmentDoesNotChangeDigest() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try write("#!/bin/sh\necho unchanged\n", to: scripts.appendingPathComponent("postinstall"))
        try write(#"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, to: project.appendingPathComponent("build-info.json"))

        let runner = RecordingRunner()
        runner.onRun = { executable, arguments in
            guard executable.hasSuffix("pkgbuild"), let output = arguments.last else { return }
            try write("fake package", to: URL(fileURLWithPath: output))
        }
        let coordinator = PackageBuildCoordinator(fileManager: .default, runner: runner, console: makeConsole())
        let options = PackageBuildOptions(skipsSigning: true, writesProvenance: true)
        try await coordinator.buildPackage(in: project, configuration: options)
        let sidecar = project.appendingPathComponent("build/App-1.0.pkg.provenance.json")
        let withoutEnvironment = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: sidecar))

        try write("SWIFTPKG_UNUSED=does-not-apply\n", to: project.appendingPathComponent(".env"))
        try await coordinator.buildPackage(in: project, configuration: options)
        let withUnusedEnvironment = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: sidecar))
        let pkgbuildCalls = runner.calls.filter { $0.executable.hasSuffix("pkgbuild") }

        #expect(withUnusedEnvironment.inputDigest == withoutEnvironment.inputDigest)
        #expect(pkgbuildCalls.count == 2)
        #expect(pkgbuildCalls.allSatisfy { !$0.arguments.contains { $0.contains("env-scripts") } })
    }

    private func makeDigestFixture() throws -> (TemporaryDirectory, URL, URL, ProvenanceBuilder, PackageConfiguration) {
        let temp = try TemporaryDirectory()
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try write(#"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, to: project.appendingPathComponent("build-info.json"))
        let output = project.appendingPathComponent("build/App-1.0.pkg")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write("PKG", to: output)
        let builder = ProvenanceBuilder(runner: GitRunner(), fileManager: .default)
        let config = try BuildInfoStore.load(from: project, requestedFormat: nil)
        return (temp, project, payload, builder, config)
    }

    @Test("input digest changes when a file's executable bit is toggled")
    func digestChangesWithPermissions() throws {
        let (temp, project, payload, builder, config) = try makeDigestFixture()
        defer { temp.remove() }
        let script = payload.appendingPathComponent("run.sh")
        try write("#!/bin/sh\n", to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: script.path)
        let before = try builder.build(configuration: config, output: output(for: project), project: project).inputDigest
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let after = try builder.build(configuration: config, output: output(for: project), project: project).inputDigest
        #expect(before != after)
    }

    @Test("input digest changes when a symlink's target changes")
    func digestChangesWithSymlinkTarget() throws {
        let (temp, project, payload, builder, config) = try makeDigestFixture()
        defer { temp.remove() }
        let link = payload.appendingPathComponent("Current")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "A")
        let before = try builder.build(configuration: config, output: output(for: project), project: project).inputDigest
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "B")
        let after = try builder.build(configuration: config, output: output(for: project), project: project).inputDigest
        #expect(before != after)
    }

    private func output(for project: URL) -> URL { project.appendingPathComponent("build/App-1.0.pkg") }
}
