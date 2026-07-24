import Foundation
import Testing
@testable import SwiftPkgCore

struct LinterTests {

    private func makeProject(buildInfo: String, addPayload: Bool = true) throws -> (TemporaryDirectory, URL) {
        let temp = try TemporaryDirectory()
        let project = temp.url.appendingPathComponent("P", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        if addPayload {
            let payload = project.appendingPathComponent("payload", isDirectory: true)
            try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false)
            try write("x", to: payload.appendingPathComponent("file.txt"))
        }
        try write(buildInfo, to: project.appendingPathComponent("build-info.json"))
        return (temp, project)
    }

    @Test("a well-formed project produces no findings")
    func cleanProject() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#)
        defer { temp.remove() }
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.isEmpty)
    }

    @Test("errors on empty version and a traversal name")
    func errorsOnBadVersionAndName() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"../evil.pkg","identifier":"com.example.app","version":""}"#)
        defer { temp.remove() }
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        let errors = findings.filter { $0.severity == .error }
        #expect(errors.contains { $0.message.contains("version is empty") })
        #expect(errors.contains { $0.message.contains("single path component") })
    }

    @Test("warns on non-reverse-DNS identifier (a non-.pkg name is auto-normalized, not flagged)")
    func warnsOnStyleIssues() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App","identifier":"noreverse","version":"1.0"}"#)
        defer { temp.remove() }
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.allSatisfy { $0.severity == .warning })
        #expect(findings.contains { $0.message.contains("reverse-DNS") })
        #expect(!findings.contains { $0.message.contains(".pkg") })
    }

    @Test("flags malformed dotted identifiers as non-reverse-DNS", arguments: [
        "noreverse", ".example", "com..example", "com.example.",
    ])
    func warnsOnMalformedIdentifier(_ identifier: String) throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App-1.0.pkg","identifier":"\#(identifier)","version":"1.0"}"#)
        defer { temp.remove() }
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.contains { $0.message.contains("reverse-DNS") })
    }

    @Test("accepts a well-formed reverse-DNS identifier")
    func acceptsReverseDNS() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#)
        defer { temp.remove() }
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(!findings.contains { $0.message.contains("reverse-DNS") })
    }

    @Test("errors when an install script is a directory")
    func errorsOnScriptDirectory() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#)
        defer { temp.remove() }
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        let postinstall = scripts.appendingPathComponent("postinstall", isDirectory: true)
        try FileManager.default.createDirectory(at: postinstall, withIntermediateDirectories: true)
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.contains { $0.severity == .error && $0.message.contains("is a directory") })
    }

    @Test("a scripts-only project (no payload) lints cleanly")
    func scriptsOnlyProjectIsClean() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, addPayload: false)
        defer { temp.remove() }
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        let postinstall = scripts.appendingPathComponent("postinstall")
        try write("#!/bin/sh\necho hi\n", to: postinstall)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: postinstall.path)
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.isEmpty)
    }

    @Test("warns when notarization is configured without signing")
    func warnsNotarizationWithoutSigning() throws {
        let buildInfo = #"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0","notarization_info":{"keychain_profile":"p"}}"#
        let (temp, project) = try makeProject(buildInfo: buildInfo)
        defer { temp.remove() }
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.contains { $0.message.contains("notarization is configured but signing") })
    }

    @Test("errors when there is neither payload nor scripts")
    func errorsOnEmptyProject() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#, addPayload: false)
        defer { temp.remove() }
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.contains { $0.severity == .error && $0.message.contains("neither a payload") })
    }

    @Test("warns on a non-executable script without a shebang")
    func warnsOnBadScript() throws {
        let (temp, project) = try makeProject(buildInfo: #"{"name":"App-1.0.pkg","identifier":"com.example.app","version":"1.0"}"#)
        defer { temp.remove() }
        let scripts = project.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        let postinstall = scripts.appendingPathComponent("postinstall")
        try write("echo hi\n", to: postinstall) // no shebang
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: postinstall.path)
        let findings = try Linter().lint(project: project, requestedFormat: nil)
        #expect(findings.contains { $0.message.contains("shebang") })
        #expect(findings.contains { $0.message.contains("not executable") })
    }
}
