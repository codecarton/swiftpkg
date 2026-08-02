import Testing
@testable import SwiftPkgCore
@testable import swiftpkg

struct CLITests {
    @Test("release version is semantic")
    func releaseVersionIsSemantic() {
        #expect(swiftpkgVersion.split(separator: ".").count == 3)
        #expect(swiftpkgVersion.split(separator: ".").allSatisfy { Int($0) != nil })
    }

    @Test("parses upstream-compatible options")
    func parsesSupportedOptions() {
        let result = CLIParser.parse([
            "--create", "--json", "--quiet", "-f", "--import", "input.pkg", "Project"
        ])

        guard case .options(let options) = result else {
            Issue.record("Expected options result")
            return
        }
        #expect(options.create)
        #expect(options.json)
        #expect(options.quiet)
        #expect(options.force)
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

    @Test("accepts --skip-import as an ignored no-op and still builds")
    func acceptsSkipImport() throws {
        guard case .options(let options) = CLIParser.parse(["--skip-import", "Project"]) else {
            Issue.record("Expected options result")
            return
        }
        #expect(options.skipImport)
        // The flag must not divert away from a normal build.
        guard case .build = try #require(try CLICommand.resolve(from: options)) else {
            Issue.record("Expected a build command")
            return
        }
    }

    @Test("reports missing import argument")
    func reportsMissingImportArgument() {
        guard case .failure(let message) = CLIParser.parse(["--import"]) else {
            Issue.record("Expected parser failure")
            return
        }
        #expect(message == "--import option requires an argument")
    }

    @Test("preserves no-argument behavior")
    func acceptsNoArguments() {
        guard case .options(let options) = CLIParser.parse([]) else {
            Issue.record("Expected options result")
            return
        }
        #expect(options.projectDirectory == nil)
    }

    @Test("recognizes help and version options")
    func recognizesHelpAndVersionOptions() {
        guard case .help = CLIParser.parse(["--help"]) else {
            Issue.record("Expected help result")
            return
        }
        guard case .version = CLIParser.parse(["--version"]) else {
            Issue.record("Expected version result")
            return
        }
    }

    @Test("resolves each operation into one command")
    func resolvesOperationsIntoCommands() throws {
        let create = try CLICommand.resolve(from: try parsedOptions(["--create", "Project"]))
        guard case let .create(project, format, force) = create else { Issue.record("Expected create command"); return }
        #expect(project.path.hasSuffix("Project"))
        #expect(format == .plist)
        #expect(!force)

        let `import` = try CLICommand.resolve(from: try parsedOptions(["--import", "input.pkg", "Project"]))
        guard case let .import(package, _, format) = `import` else { Issue.record("Expected import command"); return }
        #expect(package.path.hasSuffix("input.pkg"))
        #expect(format == .plist)

        let synchronize = try CLICommand.resolve(from: try parsedOptions(["--sync", "Project"]))
        guard case .synchronize = synchronize else { Issue.record("Expected synchronize command"); return }

        let build = try CLICommand.resolve(from: try parsedOptions(["Project"]))
        guard case .build = build else { Issue.record("Expected build command"); return }
    }

    private func parsedOptions(_ arguments: [String]) throws -> CLIOptions {
        guard case let .options(options) = CLIParser.parse(arguments) else { throw MunkiPkgError.message("Expected CLI options") }
        return options
    }
}
