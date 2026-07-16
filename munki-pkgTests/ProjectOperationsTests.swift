import Foundation
import Testing
@testable import munkipkg

struct ProjectOperationsTests {
    @Test func `creates a project template`() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        let operations = ProjectOperations(
            fileManager: .default,
            runner: RecordingRunner(),
            console: makeConsole()
        )

        try operations.createProject(at: project, options: CLIOptions())

        #expect(FileManager.default.directoryExists(at: project.appendingPathComponent("payload")))
        #expect(FileManager.default.directoryExists(at: project.appendingPathComponent("scripts")))
        #expect(FileManager.default.directoryExists(at: project.appendingPathComponent("build")))
        #expect(FileManager.default.itemExists(at: project.appendingPathComponent("build-info.plist")))
        #expect(FileManager.default.itemExists(at: project.appendingPathComponent(".gitignore")))
    }

    @Test func `syncs modes and creates empty directories from BOM`() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try write("payload", to: payload.appendingPathComponent("file.txt"))
        try write("file.txt\t100644\t0/0\nempty\t40755\t0/0\n", to: project.appendingPathComponent("Bom.txt"))

        let operations = ProjectOperations(
            fileManager: .default,
            runner: RecordingRunner(),
            console: makeConsole()
        )
        try operations.syncFromBOM(project: project, options: CLIOptions())

        #expect(FileManager.default.itemExists(at: payload.appendingPathComponent("empty")))
        let attributes = try FileManager.default.attributesOfItem(atPath: payload.appendingPathComponent("file.txt").path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        #expect(permissions == 0o644)
    }

    @Test func `exports BOM output through lsbom runner`() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let project = temporary.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let runner = RecordingRunner()
        runner.result = ProcessResult(status: 0, stdout: Data("path\t100644\t0/0\n".utf8), stderr: Data())
        let operations = ProjectOperations(fileManager: .default, runner: runner, console: makeConsole())

        try operations.exportBOM(from: URL(fileURLWithPath: "/tmp/archive.bom"), project: project)

        #expect(runner.calls == [
            RecordingRunner.Call(executable: ToolPaths.lsbom, arguments: ["/tmp/archive.bom"])
        ])
        let exported = try String(contentsOf: project.appendingPathComponent("Bom.txt"), encoding: .utf8)
        #expect(exported == "path\t100644\t0/0\n")
    }
}
