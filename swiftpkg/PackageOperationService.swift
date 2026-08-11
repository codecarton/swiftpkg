import Foundation

/// Serializes long-running project operations away from a frontend's main actor.
public actor PackageOperationService {
    private let fileManager: FileManager
    private let runner: any ProcessRunning

    public init(fileManager: FileManager = .default, runner: any ProcessRunning = SystemProcessRunner()) {
        self.fileManager = fileManager
        self.runner = runner
    }

    public nonisolated func cancelCurrentOperation() {
        (runner as? any ProcessControlling)?.cancel()
    }

    public func createProject(
        at project: URL,
        format: BuildInfoFormat,
        force: Bool = false,
        configuration: PackageConfiguration? = nil,
        reporter: (@Sendable (ConsoleEvent) -> Void)? = nil
    ) throws {
        try ProjectCreator(fileManager: fileManager, console: console(reporter: reporter))
            .createProject(at: project, format: format, force: force, configuration: configuration)
    }

    public func importPackage(
        at package: URL,
        to project: URL,
        format: BuildInfoFormat,
        reporter: (@Sendable (ConsoleEvent) -> Void)? = nil
    ) throws {
        try PackageImporter(fileManager: fileManager, runner: runner, console: console(reporter: reporter))
            .importPackage(at: package, to: project, format: format)
    }

    public func buildPackage(
        in project: URL,
        options: PackageBuildOptions,
        reporter: (@Sendable (ConsoleEvent) -> Void)? = nil
    ) async throws {
        try await PackageBuildCoordinator(fileManager: fileManager, runner: runner, console: console(reporter: reporter))
            .buildPackage(in: project, configuration: options)
    }

    public func synchronizeMetadata(
        in project: URL,
        requestedFormat: BuildInfoFormat?,
        reporter: (@Sendable (ConsoleEvent) -> Void)? = nil
    ) throws {
        try BOMMetadataService(fileManager: fileManager, runner: runner, console: console(reporter: reporter))
            .synchronizeMetadataFromBOM(in: project, requestedFormat: requestedFormat)
    }

    private func console(reporter: (@Sendable (ConsoleEvent) -> Void)?) -> Console {
        Console(quiet: false, toolName: "Swiftpkgr", eventHandler: reporter)
    }
}
