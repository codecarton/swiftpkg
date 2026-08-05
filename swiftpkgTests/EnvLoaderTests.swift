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

    @Test("reports the names it replaced, not the ones it was offered")
    func reportsSubstitutedNames() {
        let result = PlaceholderReplacer.replace(in: "url=${SERVER}", with: ["SERVER": "x", "UNUSED": "y"])
        #expect(result.substituted == ["SERVER"])
    }

    @Test("a script with no placeholders substitutes nothing")
    func noPlaceholdersSubstitutesNothing() {
        let result = PlaceholderReplacer.replace(in: "echo hello", with: ["SERVER": "x"])
        #expect(result.substituted.isEmpty)
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

    @Test("accounts for what was substituted, per script and across the project")
    func accountsForSubstitutions() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let scripts = temp.url.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        try write("#!/bin/sh\necho ${SERVER}\n", to: scripts.appendingPathComponent("preinstall"))
        try write("#!/bin/sh\necho ${SERVER} ${ORG}\n", to: scripts.appendingPathComponent("postinstall"))
        let tempDir = temp.url.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false)

        let processed = try #require(try ScriptEnvironment.process(
            scriptsDir: scripts,
            into: tempDir,
            with: ["SERVER": "https://ecu.example", "ORG": "ecuad", "UNUSED": "never referenced"]
        ))
        #expect(processed.substituted["preinstall"] == ["SERVER"])
        #expect(processed.substituted["postinstall"] == ["SERVER", "ORG"])
        #expect(processed.substitutedNames == ["SERVER", "ORG"]) // UNUSED is not counted
    }

    @Test("a variable no script references is not counted as applied")
    func unreferencedVariableIsNotApplied() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let scripts = temp.url.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        try write("#!/bin/sh\necho hello\n", to: scripts.appendingPathComponent("postinstall"))
        let tempDir = temp.url.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false)

        let processed = try #require(try ScriptEnvironment.process(scriptsDir: scripts, into: tempDir, with: ["SERVER": "x"]))
        #expect(processed.substituted.isEmpty)
        #expect(processed.substitutedNames.isEmpty)
    }
}

struct ShellOwnedPlaceholderTests {

    /// The shape that produced the false positive in production: a helper whose
    /// parameters are shell locals expanded with `${...}` at install time.
    private static let plistHelper = """
    #!/bin/zsh
    plist_set() {
        local key="$1" type="$2" val="$3"
        if $PB -c "Set :${key} ${val}" "$PLIST" 2>/dev/null; then
            return 0
        fi
        $PB -c "Add :${key} ${type} ${val}" "$PLIST"
    }
    plist_set ApiUrl string ${REPORTMATE_API_URL}
    """

    @Test("a helper's shell locals are not reported as unresolved placeholders")
    func shellLocalsAreNotPlaceholders() {
        let unresolved = ScriptEnvironment.reportableUnresolved(
            in: Self.plistHelper,
            with: ["REPORTMATE_API_URL": "https://ecu.example"]
        )
        #expect(unresolved.isEmpty)
    }

    @Test("a genuinely missing build variable is still reported")
    func missingBuildVariableStillWarns() {
        let unresolved = ScriptEnvironment.reportableUnresolved(in: Self.plistHelper, with: [:])
        #expect(unresolved == ["REPORTMATE_API_URL"])
    }

    @Test("recognises every form that introduces a shell name")
    func recognisesDeclarationForms() {
        let script = """
        #!/bin/bash
        plain=1
        local scoped="x"
        export -f exported=2
        declare -i counted=3
        readonly frozen=4
        typeset typed=5
        bare_local() { local declared; }
        for item in a b c; do echo "${item}"; done
        read -r answer
        """
        let owned = ScriptEnvironment.shellOwnedNames(in: script)
        for name in ["plain", "scoped", "exported", "counted", "frozen", "typed", "declared", "item", "answer"] {
            #expect(owned.contains(name), "expected \(name) to be recognised as shell-owned")
        }
    }

    @Test("environment-supplied names are not reported as unresolved placeholders")
    func environmentNamesAreNotPlaceholders() {
        let script = """
        #!/bin/sh
        echo "${HOME}" "${PATH}" "${USER}" "${TMPDIR}"
        cp "$1" "${DSTVOLUME}/opt"
        """
        #expect(ScriptEnvironment.reportableUnresolved(in: script, with: [:]).isEmpty)
    }

    @Test("an environment name does not mask a genuinely missing variable beside it")
    func environmentNamesDoNotMaskMissingOnes() {
        let script = """
        #!/bin/sh
        echo "${HOME}/${API_TOKEN}"
        """
        #expect(ScriptEnvironment.reportableUnresolved(in: script, with: [:]) == ["API_TOKEN"])
    }

    @Test("an environment name supplied as a build variable is still substituted")
    func environmentNameStillSubstitutes() {
        let result = PlaceholderReplacer.replace(in: "echo ${TMPDIR}\n", with: ["TMPDIR": "/staged"])
        #expect(result.content == "echo /staged\n")
        #expect(result.substituted == ["TMPDIR"])
    }

    @Test("suppression is per-script, not global")
    func suppressionIsPerScript() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let scripts = temp.url.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        try write("#!/bin/sh\nlocal token=1\necho ${token}\n", to: scripts.appendingPathComponent("preinstall"))
        try write("#!/bin/sh\necho ${token}\n", to: scripts.appendingPathComponent("postinstall"))

        let byScript = ScriptEnvironment.unresolvedPlaceholders(in: scripts, given: [:])
        #expect(byScript["preinstall"] == nil)
        #expect(byScript["postinstall"] == ["token"])
    }

    @Test("substitution is unaffected by the reporting filter")
    func substitutionUnchanged() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let scripts = temp.url.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: false)
        try write("#!/bin/sh\nlocal key=1\necho ${key} ${SERVER}\n", to: scripts.appendingPathComponent("postinstall"))
        let tempDir = temp.url.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false)

        let processed = try #require(try ScriptEnvironment.process(scriptsDir: scripts, into: tempDir, with: ["SERVER": "https://ecu.example"]))
        let content = try String(contentsOf: processed.directory.appendingPathComponent("postinstall"), encoding: .utf8)
        #expect(content.contains("echo ${key} https://ecu.example"))
        #expect(processed.unresolved.isEmpty)
    }
}
