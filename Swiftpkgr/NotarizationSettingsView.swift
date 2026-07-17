import SwiftPkgCore
import SwiftUI

struct NotarizationSettingsView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Form {
            Section("Authentication") {
                Picker("Method", selection: $model.draft.notarizationMode) {
                    ForEach(NotarizationAuthenticationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
            if model.draft.notarizationMode == .keychainProfile {
                Section("Keychain Profile") {
                    TextField("Profile name", text: $model.draft.notarizationKeychainProfile)
                }
            }
            if model.draft.notarizationMode == .appleID {
                Section("Apple ID") {
                    TextField("Apple ID", text: $model.draft.notarizationAppleID)
                    TextField("Team ID", text: $model.draft.notarizationTeamID)
                    SecureField("App-specific password", text: $model.draft.notarizationPassword)
                    Text("CLI-compatible exports store this password in plaintext. Prefer a keychain profile.")
                        .foregroundStyle(.secondary)
                }
            }
            if model.draft.notarizationMode != .none {
                Section("Stapling") {
                    TextField("Timeout in seconds", value: $model.draft.staplingTimeout, format: .number)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notarization")
    }
}
