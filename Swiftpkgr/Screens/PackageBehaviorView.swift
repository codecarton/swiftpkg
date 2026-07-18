import SwiftPkgCore
import SwiftUI

struct PackageBehaviorView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Form {
            Section("Payload") {
                Picker("Ownership", selection: $model.draft.ownership) {
                    ForEach(PackageOwnership.allCases) { ownership in
                        Text(ownership.displayName).tag(ownership)
                    }
                }
                Picker("Compression", selection: $model.draft.compression) {
                    Text("System Default").tag(PackageCompression?.none)
                    ForEach(PackageCompression.allCases) { compression in
                        Text(compression.displayName).tag(Optional(compression))
                    }
                }
                TextField("Minimum macOS version", text: $model.draft.minimumOSVersion)
                Toggle("Use large payload format", isOn: $model.draft.usesLargePayload)
                Toggle("Preserve extended attributes", isOn: $model.draft.preservesExtendedAttributes)
                Toggle("Suppress bundle relocation", isOn: $model.draft.suppressesBundleRelocation)
            }
            Section("Installer") {
                Picker("Post-install action", selection: $model.draft.postInstallAction) {
                    ForEach(PostInstallAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Package Behavior")
    }
}

#Preview {
    PackageBehaviorView(model: ProjectEditorModel())
}
