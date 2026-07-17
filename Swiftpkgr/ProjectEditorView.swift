import SwiftUI

struct ProjectEditorView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Group {
            if model.isProjectOpen {
                NavigationSplitView {
                    List(ProjectSection.allCases, selection: $model.selectedSection) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                    .navigationTitle(model.projectName)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                } detail: {
                    ProjectSectionView(model: model)
                }
            } else {
                WelcomeView(model: model)
            }
        }
        .navigationTitle(model.hasUnsavedChanges ? "\(model.projectName) — Edited" : model.projectName)
        .toolbar {
            ToolbarItemGroup {
                Button("Import Settings", systemImage: "square.and.arrow.down", action: model.importSettings)
                    .disabled(!model.isProjectOpen || model.isRunning)
                Button("Export Settings", systemImage: "square.and.arrow.up", action: model.requestSettingsExport)
                    .disabled(!model.isProjectOpen || model.isRunning)
                    .confirmationDialog(
                        "Export Password in Plaintext?",
                        isPresented: $model.showsSensitiveExportWarning,
                        titleVisibility: .visible
                    ) {
                        Button("Export Anyway", action: model.exportSettings)
                    } message: {
                        Text("CLI-compatible Apple ID settings store the notarization password in plaintext. A keychain profile is safer.")
                    }
                Button("Save", systemImage: "square.and.arrow.down.on.square", action: model.save)
                    .disabled(!model.isProjectOpen || model.isRunning || !model.hasUnsavedChanges)
                Button("Build", systemImage: "hammer", action: model.build)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canBuild)
                if model.isRunning {
                    Button("Cancel", systemImage: "xmark.circle", action: model.cancelOperation)
                        .disabled(model.isCancelling)
                }
            }
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .confirmationDialog(
            "Discard Unsaved Changes?",
            isPresented: $model.showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive, action: model.discardChangesAndContinue)
            Button("Cancel", role: .cancel, action: model.cancelPendingProjectAction)
        } message: {
            Text("Opening or creating another project will discard edits that have not been saved.")
        }
    }
}

#Preview {
    ProjectEditorView(model: ProjectEditorModel())
}
