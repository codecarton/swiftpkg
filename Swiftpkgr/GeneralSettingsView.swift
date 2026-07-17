import SwiftPkgCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Form {
            Section("Package Identity") {
                TextField("Package name", text: $model.draft.name)
                TextField("Identifier", text: $model.draft.identifier)
                TextField("Version", text: $model.draft.version)
                TextField("Install location", text: $model.draft.installLocation)
            }
            Section("Build Info") {
                LabeledContent("Project", value: model.projectURL?.path ?? "")
                LabeledContent("Format", value: model.buildInfoDocument?.format.displayName ?? "Unknown")
                Text("Use `${version}` in package name or title to substitute the version during builds.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
