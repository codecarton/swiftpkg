import SwiftUI

struct SwiftpkgrCommands: Commands {
    let model: ProjectEditorModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…", systemImage: "plus", action: model.createNewProject)
                .keyboardShortcut("n")
            Button("Open Project…", systemImage: "folder", action: model.chooseProjectToOpen)
                .keyboardShortcut("o")
            Button("Import Package…", systemImage: "shippingbox.and.arrow.backward", action: model.choosePackageToImport)
        }

        CommandGroup(after: .saveItem) {
            Button("Save Project", systemImage: "square.and.arrow.down", action: model.save)
                .keyboardShortcut("s")
                .disabled(!model.isProjectOpen || model.isRunning)
            Divider()
            Button("Import Settings…", systemImage: "square.and.arrow.down.on.square", action: model.importSettings)
                .disabled(!model.isProjectOpen || model.isRunning)
            Button("Export Settings…", systemImage: "square.and.arrow.up.on.square", action: model.requestSettingsExport)
                .disabled(!model.isProjectOpen || model.isRunning)
        }

        CommandMenu("Package") {
            Button("Build", systemImage: "hammer", action: model.build)
                .keyboardShortcut("b")
                .disabled(!model.canBuild)
            Button("Synchronize from Bom.txt", systemImage: "arrow.triangle.2.circlepath", action: model.synchronizeBOM)
                .disabled(!model.isProjectOpen || model.isRunning)
            Divider()
            Button("Reveal Project", systemImage: "folder", action: model.revealProject)
                .disabled(!model.isProjectOpen)
            Button("Reveal Built Package", systemImage: "shippingbox", action: model.revealBuiltPackage)
                .disabled(model.builtPackageURL == nil)
        }
    }
}
