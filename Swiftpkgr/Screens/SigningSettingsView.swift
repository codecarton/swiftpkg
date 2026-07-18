import SwiftPkgCore
import SwiftUI

struct SigningSettingsView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Form {
            Section {
                Toggle("Sign package", isOn: $model.draft.signingEnabled)
            }
            Section("Signing Identity") {
                TextField("Identity", text: $model.draft.signingIdentity)
                TextField("Keychain path", text: $model.draft.signingKeychain)
                TextField(
                    "Additional certificate names, one per line",
                    text: $model.draft.additionalCertificateNamesText,
                    axis: .vertical
                )
                .lineLimit(3...6)
                Picker("Timestamp", selection: $model.draft.signingTimestampMode) {
                    ForEach(SigningTimestampMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
            .disabled(!model.draft.signingEnabled)
        }
        .formStyle(.grouped)
        .navigationTitle("Signing")
    }
}

#Preview {
    SigningSettingsView(model: ProjectEditorModel())
}
