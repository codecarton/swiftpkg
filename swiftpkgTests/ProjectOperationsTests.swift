import Foundation
import Testing
@testable import swiftpkg

struct ProjectOperationsTests {
    @Test("creates a project template")
    func createsProjectTemplate() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        let creator = ProjectCreator(
            fileManager: .default,
            console: makeConsole()
        )

        try creator.createProject(at: project, format: .plist, force: false)

        #expect(FileManager.default.directoryExists(at: project.appendingPathComponent("payload")))
        #expect(FileManager.default.directoryExists(at: project.appendingPathComponent("scripts")))
        #expect(FileManager.default.directoryExists(at: project.appendingPathComponent("build")))
        #expect(FileManager.default.itemExists(at: project.appendingPathComponent("build-info.plist")))
        #expect(FileManager.default.itemExists(at: project.appendingPathComponent(".gitignore")))
    }

    @Test("syncs modes and creates empty directories from BOM")
    func syncsModesAndCreatesEmptyDirectoriesFromBOM() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try write("payload", to: payload.appendingPathComponent("file.txt"))
        try write("file.txt\t100644\t0/0\nempty\t40755\t0/0\n", to: project.appendingPathComponent("Bom.txt"))

        let bomMetadata = BOMMetadataService(
            fileManager: .default,
            runner: RecordingRunner(),
            console: makeConsole()
        )
        try bomMetadata.synchronizeMetadataFromBOM(in: project, requestedFormat: nil)

        #expect(FileManager.default.itemExists(at: payload.appendingPathComponent("empty")))
        let attributes = try FileManager.default.attributesOfItem(atPath: payload.appendingPathComponent("file.txt").path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o644)
    }

    @Test("exports BOM output through lsbom runner")
    func exportsBOMOutputThroughLsbomRunner() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let runner = RecordingRunner()
        runner.result = ProcessResult(status: 0, stdout: Data("path\t100644\t0/0\n".utf8), stderr: Data())
        let bomMetadata = BOMMetadataService(fileManager: .default, runner: runner, console: makeConsole())

        try bomMetadata.exportMetadata(from: URL(fileURLWithPath: "/tmp/archive.bom"), to: project)

        #expect(runner.calls == [
            RecordingRunner.Call(executable: ToolPaths.lsbom, arguments: ["/tmp/archive.bom"])
        ])
        let exported = try String(contentsOf: project.appendingPathComponent("Bom.txt"), encoding: .utf8)
        #expect(exported == "path\t100644\t0/0\n")
    }
}
