import AppKit
import SwiftPkgCore
import UniformTypeIdentifiers

@MainActor
struct ProjectPanelService {
    func chooseProjectDirectory(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseNewProjectDirectory(title: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "PackageProject"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func choosePackage() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Installer Package"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        if let packageType = UTType(filenameExtension: "pkg") {
            panel.allowedContentTypes = [packageType]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseSettingsFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Settings"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let yamlType = UTType(filenameExtension: "yaml"), let ymlType = UTType(filenameExtension: "yml") {
            panel.allowedContentTypes = [.propertyList, .json, yamlType, ymlType]
        } else {
            panel.allowedContentTypes = [.propertyList, .json]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseSettingsDestination(format: BuildInfoFormat) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "build-info.\(format.rawValue)"
        panel.isExtensionHidden = false
        if let contentType = settingsContentType(for: format) {
            panel.allowedContentTypes = [contentType]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func settingsContentType(for format: BuildInfoFormat) -> UTType? {
        switch format {
        case .plist: .propertyList
        case .json: .json
        case .yaml, .yml: UTType(filenameExtension: format.rawValue)
        }
    }
}
