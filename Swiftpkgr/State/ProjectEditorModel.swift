import Foundation
import Observation
import SwiftPkgCore

@MainActor
@Observable
final class ProjectEditorModel {
    var projectURL: URL?
    var buildInfoDocument: BuildInfoDocument?
    var draft = PackageSettingsDraft.defaults(for: URL(fileURLWithPath: "/tmp/PackageProject"))
    var selectedSection: ProjectSection? = .general
    var newProjectFormat: BuildInfoFormat = .plist
    var exportsBOM = false
    var skipsSigning = false
    var skipsNotarization = false
    var skipsStapling = false
    var isRunning = false
    var isCancelling = false
    var statusMessage = "No project open"
    var activityLog: [String] = []
    var alert: AppAlert?
    var showsSensitiveExportWarning = false
    var showsDiscardConfirmation = false

    @ObservationIgnored private let operations = PackageOperationService()
    @ObservationIgnored private let panels = ProjectPanelService()
    @ObservationIgnored private var savedDraft: PackageSettingsDraft?
    @ObservationIgnored private var pendingProjectAction: PendingProjectAction?
    @ObservationIgnored private var operationTask: Task<Void, Never>?

    var isProjectOpen: Bool { projectURL != nil }
    var hasUnsavedChanges: Bool { savedDraft.map { $0 != draft } ?? false }
    var projectName: String { projectURL?.lastPathComponent ?? "Swiftpkgr" }
    var canBuild: Bool { isProjectOpen && !isRunning }
    var showsBuildConfirmation = false

    var payloadURL: URL? {
        guard let projectURL else { return nil }
        let url = projectURL.appending(path: "payload", directoryHint: .isDirectory)
        return FileManager.default.directoryExists(at: url) ? url : nil
    }

    var scriptsURL: URL? {
        guard let projectURL else { return nil }
        let url = projectURL.appending(path: "scripts", directoryHint: .isDirectory)
        return FileManager.default.directoryExists(at: url) ? url : nil
    }

    var builtPackageURL: URL? {
        guard let projectURL else { return nil }
        let resolvedName = draft.name.replacing("${version}", with: draft.version)
        let url = projectURL.appending(path: "build", directoryHint: .isDirectory).appending(path: resolvedName)
        return FileManager.default.itemExists(at: url) ? url : nil
    }

    func createNewProject() {
        requestProjectAction(.create)
    }

    func convertExistingFolder() {
        requestProjectAction(.convert)
    }

    func chooseProjectToOpen() {
        requestProjectAction(.open)
    }

    func choosePackageToImport() {
        requestProjectAction(.importPackage)
    }

    func discardChangesAndContinue() {
        guard let pendingProjectAction else { return }
        self.pendingProjectAction = nil
        perform(pendingProjectAction)
    }

    func cancelPendingProjectAction() {
        pendingProjectAction = nil
    }

    private func chooseNewProjectDestination() {
        guard let destination = panels.chooseNewProjectDirectory(title: "Create Swiftpkgr Project") else { return }
        createProject(at: destination, force: false)
    }

    private func chooseFolderToConvert() {
        guard let destination = panels.chooseProjectDirectory(title: "Convert Existing Folder") else { return }
        createProject(at: destination, force: true)
    }

    private func chooseProjectDirectory() {
        guard let project = panels.chooseProjectDirectory(title: "Open Swiftpkg Project") else { return }
        openProject(at: project)
    }

    private func choosePackageAndDestination() {
        guard let package = panels.choosePackage(),
              let destination = panels.chooseNewProjectDirectory(title: "Choose Imported Project Location") else { return }
        let reporter = makeReporter()
        runOperation("Importing \(package.lastPathComponent)…") { [operations, newProjectFormat] in
            try await operations.importPackage(at: package, to: destination, format: newProjectFormat, reporter: reporter)
            return destination
        }
    }

    func openProject(at project: URL) {
        do {
            let document = try BuildInfoStore.discover(in: project)
            let configuration = try BuildInfoStore.loadTemplate(from: document.url, defaultsFor: project)
            projectURL = project
            buildInfoDocument = document
            draft = PackageSettingsDraft(configuration: configuration)
            savedDraft = draft
            selectedSection = .general
            statusMessage = "Ready"
            activityLog.append("Opened \(project.path)")
        } catch {
            present(error, title: "Could Not Open Project")
        }
    }

    func save() {
        do {
            try saveDraft()
            statusMessage = "Saved"
            activityLog.append("Saved \(projectName)")
        } catch {
            present(error, title: "Could Not Save Project")
        }
    }

    func importSettings() {
        guard let url = panels.chooseSettingsFile(), let projectURL else { return }
        do {
            let configuration = try BuildInfoStore.loadTemplate(from: url, defaultsFor: projectURL)
            draft = PackageSettingsDraft(configuration: configuration)
            statusMessage = "Imported settings"
            activityLog.append("Imported settings from \(url.path)")
        } catch {
            present(error, title: "Could Not Import Settings")
        }
    }

    func requestSettingsExport() {
        if draft.notarizationMode == .appleID, !draft.notarizationPassword.isEmpty {
            showsSensitiveExportWarning = true
        } else {
            exportSettings()
        }
    }

    func exportSettings() {
        do {
            let configuration = try draft.validatedConfiguration()
            guard let url = panels.chooseSettingsDestination(defaultName: "build-info.plist") else { return }
            guard let format = BuildInfoFormat(rawValue: url.pathExtension.lowercased()) else {
                throw MunkiPkgError.invalidConfiguration("Export settings as a .plist, .json, .yaml, or .yml file.")
            }
            try BuildInfoStore.write(configuration, toFile: url, format: format)
            statusMessage = "Exported settings"
            activityLog.append("Exported settings to \(url.path)")
        } catch {
            present(error, title: "Could Not Export Settings")
        }
    }

    func requestBuild() {
        guard canBuild else { return }
        if requiresBuildConfirmation() {
            showsBuildConfirmation = true
        } else {
            executeConfirmedBuild()
        }
    }

    func executeConfirmedBuild() {
        guard let projectURL, let format = buildInfoDocument?.format else { return }
        do {
            try saveDraft()
        } catch {
            present(error, title: "Could Not Build Package")
            return
        }
        let options = PackageBuildOptions(
            requestedFormat: format,
            exportsBOM: exportsBOM,
            isQuiet: false,
            skipsSigning: skipsSigning,
            skipsNotarization: skipsNotarization,
            skipsStapling: skipsStapling
        )
        let reporter = makeReporter()
        runOperation("Building package…") { [operations] in
            try await operations.buildPackage(in: projectURL, options: options, reporter: reporter)
            return projectURL
        }
    }

    private func requiresBuildConfirmation() -> Bool {
        return draft.signingEnabled || draft.notarizationMode != .none
    }

    func synchronizeBOM() {
        guard let projectURL else { return }
        let format = buildInfoDocument?.format
        let reporter = makeReporter()
        runOperation("Synchronizing Bom.txt…") { [operations] in
            try await operations.synchronizeMetadata(in: projectURL, requestedFormat: format, reporter: reporter)
            return projectURL
        }
    }

    func cancelOperation() {
        guard isRunning else { return }
        isCancelling = true
        statusMessage = "Cancelling…"
        activityLog.append("Cancelling operation…")
        operations.cancelCurrentOperation()
        operationTask?.cancel()
    }

    func revealProject() {
        guard let projectURL else { return }
        panels.reveal(projectURL)
    }

    func revealPayload() {
        guard let payloadURL else { return }
        panels.reveal(payloadURL)
    }

    func revealScripts() {
        guard let scriptsURL else { return }
        panels.reveal(scriptsURL)
    }

    func revealBuiltPackage() {
        guard let builtPackageURL else { return }
        panels.reveal(builtPackageURL)
    }

    private func createProject(at destination: URL, force: Bool) {
        let configuration: PackageConfiguration
        do {
            configuration = try PackageSettingsDraft.defaults(for: destination).validatedConfiguration()
        } catch {
            present(error, title: "Could Not Create Project")
            return
        }
        let reporter = makeReporter()
        runOperation("Creating \(destination.lastPathComponent)…") { [operations, newProjectFormat] in
            try await operations.createProject(
                at: destination,
                format: newProjectFormat,
                force: force,
                configuration: configuration,
                reporter: reporter
            )
            return destination
        }
    }

    private func requestProjectAction(_ action: PendingProjectAction) {
        guard !isRunning else { return }
        if hasUnsavedChanges {
            pendingProjectAction = action
            showsDiscardConfirmation = true
        } else {
            perform(action)
        }
    }

    private func perform(_ action: PendingProjectAction) {
        switch action {
        case .create: chooseNewProjectDestination()
        case .open: chooseProjectDirectory()
        case .importPackage: choosePackageAndDestination()
        case .convert: chooseFolderToConvert()
        }
    }

    private func saveDraft() throws {
        guard let projectURL, let document = buildInfoDocument else {
            throw MunkiPkgError.message("No project is open.")
        }
        let configuration = try draft.validatedConfiguration()
        try BuildInfoStore.write(configuration, to: projectURL, format: document.format)
        savedDraft = draft
    }

    private func runOperation(
        _ message: String,
        operation: @escaping @Sendable () async throws -> URL
    ) {
        guard !isRunning else { return }
        isRunning = true
        isCancelling = false
        statusMessage = message
        activityLog.append(message)
        operationTask = Task {
            do {
                let project = try await operation()
                isRunning = false
                isCancelling = false
                operationTask = nil
                openProject(at: project)
                statusMessage = "Completed"
                activityLog.append("Completed")
            } catch {
                isRunning = false
                operationTask = nil
                if isCancelling || Task.isCancelled {
                    isCancelling = false
                    statusMessage = "Cancelled"
                    activityLog.append("Operation cancelled")
                } else {
                    present(error, title: "Operation Failed")
                }
            }
        }
    }

    private func present(_ error: any Error, title: String) {
        statusMessage = "Failed"
        activityLog.append("Error: \(error.localizedDescription)")
        alert = AppAlert(title: title, message: error.localizedDescription)
    }

    private func makeReporter() -> @Sendable (ConsoleEvent) -> Void {
        { [weak self] event in
            Task { @MainActor [weak self] in
                self?.record(event)
            }
        }
    }

    private func record(_ event: ConsoleEvent) {
        let prefix = switch event {
        case .status: ""
        case .warning: "Warning: "
        case .error: "Error: "
        }
        statusMessage = event.message
        activityLog.append(prefix + event.message)
    }
}
