import Foundation
import Testing
@testable import SwiftPkgCore

struct EnvLoaderTests {

    private func writeEnv(_ contents: String) throws -> (TemporaryDirectory, String) {
        let temp = try TemporaryDirectory()
        let path = temp.url.appendingPathComponent(".env").path
        try write(contents, to: URL(fileURLWithPath: path))
        return (temp, path)
    }

    @Test("parses key=value, strips quotes, skips comments and blanks")
    func parsesBasics() throws {
        let (temp, path) = try writeEnv("""
        # comment
        SERVER=https://example.com

        NAME="Quoted Value"
        SINGLE='single'
        EMPTY=
        """)
        defer { temp.remove() }
        let vars = try EnvLoader.load(from: path)
        #expect(vars["SERVER"] == "https://example.com")
        #expect(vars["NAME"] == "Quoted Value")
        #expect(vars["SINGLE"] == "single")
        #expect(vars["EMPTY"] == "")
        #expect(vars.count == 4)
    }

    @Test("skips entries with invalid keys")
    func skipsInvalidKeys() throws {
        let (temp, path) = try writeEnv("9BAD=x\nGO OD=y\nOKAY=z\n")
        defer { temp.remove() }
        let vars = try EnvLoader.load(from: path)
        #expect(vars == ["OKAY": "z"])
    }

    @Test("rejects a file over the size limit")
    func rejectsOversized() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let path = temp.url.appendingPathComponent(".env").path
        try write(String(repeating: "A=B\n", count: EnvLoader.maxFileSize), to: URL(fileURLWithPath: path))
        #expect(throws: MunkiPkgError.self) { try EnvLoader.load(from: path) }
    }

    @Test("missing file yields no variables")
    func missingFile() throws {
        #expect(try EnvLoader.load(from: "/no/such/.env").isEmpty)
    }

    @Test("merge: .env wins over inherited SWIFTPKG_*, and inherit can be disabled")
    func mergePrecedence() {
        let environment = ["SWIFTPKG_A": "sys", "SWIFTPKG_B": "sysB", "OTHER": "ignored"]
        let merged = EnvLoader.merge(fileVariables: ["SWIFTPKG_A": "file", "C": "c"], inheritsEnvironment: true, environment: environment)
        #expect(merged["SWIFTPKG_A"] == "file") // file wins
        #expect(merged["SWIFTPKG_B"] == "sysB")
        #expect(merged["C"] == "c")
        #expect(merged["OTHER"] == nil) // only SWIFTPKG_* inherited

        let noInherit = EnvLoader.merge(fileVariables: ["C": "c"], inheritsEnvironment: false, environment: environment)
        #expect(noInherit == ["C": "c"])
    }
}

struct PlaceholderReplacerTests {

    @Test("substitutes known placeholders and reports unresolved ones")
    func substitutesAndReports() {
        let result = PlaceholderReplacer.replace(in: "url=${SERVER} id=${MISSING}", with: ["SERVER": "x"])
        #expect(result.content == "url=x id=${MISSING}")
        #expect(result.unresolved == ["MISSING"])
    }

    @Test("single pass: a substituted value is not re-expanded")
    func singlePass() {
        let result = PlaceholderReplacer.replace(in: "${A}", with: ["A": "${B}", "B": "leaked"])
        #expect(result.content == "${B}") // not "leaked"
    }

    @Test("values with shell metacharacters are spliced verbatim")
    func verbatimSplice() {
        let result = PlaceholderReplacer.replace(in: "run ${X}", with: ["X": "$(whoami)"])
        #expect(result.content == "run $(whoami)")
    }
}

struct ScriptEnvironmentTests {

    @Test("processes scripts into a 0700 temp dir with substituted values")
    func processesScripts() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let scripts = temp.url.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        try write("#!/bin/sh\necho ${SERVER}\n", to: scripts.appendingPathComponent("postinstall"))
        let tempDir = temp.url.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false)

        let processed = try #require(try ScriptEnvironment.process(scriptsDir: scripts, into: tempDir, with: ["SERVER": "https://ecu.example"]))
        let content = try String(contentsOf: processed.directory.appendingPathComponent("postinstall"), encoding: .utf8)
        #expect(content.contains("echo https://ecu.example"))
        #expect(!content.contains("${SERVER}"))

        let perms = (try FileManager.default.attributesOfItem(atPath: processed.directory.appendingPathComponent("postinstall").path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
        #expect(perms & 0o077 == 0) // no group/other bits
        #expect(perms & 0o100 != 0) // owner-executable
    }

    @Test("returns nil when there are no variables")
    func noVariables() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let scripts = temp.url.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        try write("#!/bin/sh\n", to: scripts.appendingPathComponent("postinstall"))
        let result = try ScriptEnvironment.process(scriptsDir: scripts, into: temp.url, with: [:])
        #expect(result == nil)
    }
}
