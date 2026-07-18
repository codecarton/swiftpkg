import SwiftPkgCore
import SwiftUI

struct SwiftpkgrCommands: Commands {
    let model: ProjectEditorModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…", systemImage: "plus", action: model.createNewProject)
                .keyboardShortcut("n")
                .disabled(model.isRunning)
            Button("Open Project…", systemImage: "folder", action: model.chooseProjectToOpen)
                .keyboardShortcut("o")
                .disabled(model.isRunning)
            Button("Import Package…", systemImage: "shippingbox.and.arrow.backward", action: model.choosePackageToImport)
                .disabled(model.isRunning)
        }

        CommandGroup(after: .saveItem) {
            Button("Save Project", systemImage: "square.and.arrow.down", action: model.save)
                .keyboardShortcut("s")
                .disabled(!model.isProjectOpen || model.isRunning)
            Divider()
            Button("Import Settings…", systemImage: "square.and.arrow.down.on.square", action: model.importSettings)
                .disabled(!model.isProjectOpen || model.isRunning)
            Menu("Export Settings…", systemImage: "square.and.arrow.up.on.square") {
                ForEach(BuildInfoFormat.allCases) { format in
                    Button(format.displayName) {
                        model.requestSettingsExport(as: format)
                    }
                }
            }
                .disabled(!model.isProjectOpen || model.isRunning)
        }

        CommandMenu("Package") {
            Button("Build", systemImage: "hammer", action: model.requestBuild)
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
