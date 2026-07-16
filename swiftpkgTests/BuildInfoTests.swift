import Foundation
import Testing
@testable import swiftpkg

struct BuildInfoTests {
    @Test("defaults remove spaces and provide upstream values")
    func defaultsRemoveSpacesAndProvideUpstreamValues() throws {
        let project = URL(fileURLWithPath: "/tmp/My Project")
        let info = BuildInfo.defaults(for: project)

        #expect(info.string("name") == "MyProject-${version}.pkg")
        #expect(info.string("identifier") == "com.github.munki.pkg.MyProject")
        #expect(info.string("version") == "1.0")
        #expect(info.string("ownership") == "recommended")
        #expect(info.bool("distribution_style") == false)
    }

    @Test("loads supported formats and substitutes version", arguments: [BuildInfoFormat.json, .plist, .yaml])
    func loadsSupportedFormatsAndSubstitutesVersion(_ format: BuildInfoFormat) throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let values: [String: Any] = [
            "name": "Project-${version}.pkg",
            "version": "2.5",
            "title": "Project ${version}",
            "identifier": "com.example.project",
            "ownership": "recommended",
            "postinstall_action": "none"
        ]
        let info = BuildInfo(values: values)
        let options = CLIOptions(json: format == .json, yaml: format == .yaml)
        try BuildInfoIO.write(info, project: project, options: options)

        let loaded = try BuildInfoIO.load(project: project, options: options)
        #expect(loaded.string("name") == "Project-2.5.pkg")
        #expect(loaded.string("title") == "Project 2.5")
        #expect(loaded.string("identifier") == "com.example.project")
    }

    @Test("rejects multiple build info files")
    func rejectsMultipleBuildInfoFiles() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let info = BuildInfo.defaults(for: project)
        try BuildInfoIO.write(info, project: project, options: CLIOptions())
        try BuildInfoIO.write(info, project: project, options: CLIOptions(json: true))

        #expect(throws: (any Error).self) {
            try BuildInfoIO.load(project: project, options: CLIOptions())
        }
    }

    @Test("rejects illegal build info values")
    func rejectsIllegalBuildInfoValues() throws {
        let info = BuildInfo(values: [
            "name": "Project.pkg",
            "version": "1.0",
            "identifier": "com.example.project",
            "ownership": "invalid",
            "postinstall_action": "none"
        ])

        #expect(throws: (any Error).self) {
            try info.validated(source: "test")
        }
    }
}
