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
