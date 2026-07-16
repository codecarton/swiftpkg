import Testing
@testable import swiftpkg

struct CLITests {
    @Test("release version is semantic")
    func releaseVersionIsSemantic() {
        #expect(swiftpkgVersion.split(separator: ".").count == 3)
        #expect(swiftpkgVersion.split(separator: ".").allSatisfy { Int($0) != nil })
    }

    @Test("parses supported options")
    func parsesSupportedOptions() {
        let result = CLIParser.parse([
            "--create", "--json", "--quiet", "--import", "input.pkg", "Project"
        ])

        guard case .options(let options) = result else {
            Issue.record("Expected options result")
            return
        }
        #expect(options.create)
        #expect(options.json)
        #expect(options.quiet)
        #expect(options.importPackage == "input.pkg")
        #expect(options.projectDirectory == "Project")
    }

    @Test("rejects invalid argument combinations", arguments: [["--json", "--yaml"], ["one", "two"]])
    func rejectsInvalidArgumentCombinations(_ arguments: [String]) {
        guard case .failure = CLIParser.parse(arguments) else {
            Issue.record("Expected parser failure for \(arguments)")
            return
        }
    }

    @Test("accepts import equals syntax")
    func acceptsImportEqualsSyntax() {
        guard case .options(let options) = CLIParser.parse(["--import=existing.pkg", "Project"]) else {
            Issue.record("Expected options result")
            return
        }
        #expect(options.importPackage == "existing.pkg")
    }

    @Test("reports missing import argument")
    func reportsMissingImportArgument() {
        guard case .failure(let message) = CLIParser.parse(["--import"]) else {
            Issue.record("Expected parser failure")
            return
        }
        #expect(message == "--import option requires an argument")
    }
}
