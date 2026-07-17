import AppKit
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
        panel.allowedContentTypes = [.propertyList, .json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseSettingsDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Settings"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.propertyList, .json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
