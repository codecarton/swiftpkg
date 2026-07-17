import SwiftUI

struct DistributionSettingsView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Form {
            Section {
                Toggle("Build a distribution package", isOn: $model.draft.usesDistributionStyle)
            } footer: {
                Text("Distribution packages are assembled with productbuild after the component package is created.")
            }
            Section("Metadata") {
                TextField("Installer title", text: $model.draft.title)
                    .disabled(!model.draft.usesDistributionStyle)
                TextField("Product identifier", text: $model.draft.productIdentifier)
                    .disabled(!model.draft.usesDistributionStyle)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Distribution")
    }
}
