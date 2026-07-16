import Testing
@testable import munkipkg

struct CLITests {
    @Test func `parses supported options`() {
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

    @Test(arguments: [["--json", "--yaml"], ["one", "two"]])
    func `rejects invalid argument combinations`(_ arguments: [String]) {
        guard case .failure = CLIParser.parse(arguments) else {
            Issue.record("Expected parser failure for \(arguments)")
            return
        }
    }

    @Test func `accepts import equals syntax`() {
        guard case .options(let options) = CLIParser.parse(["--import=existing.pkg", "Project"]) else {
            Issue.record("Expected options result")
            return
        }
        #expect(options.importPackage == "existing.pkg")
    }

    @Test func `reports missing import argument`() {
        guard case .failure(let message) = CLIParser.parse(["--import"]) else {
            Issue.record("Expected parser failure")
            return
        }
        #expect(message == "--import option requires an argument")
    }
}
