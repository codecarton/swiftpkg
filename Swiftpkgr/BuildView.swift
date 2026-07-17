import SwiftUI

struct BuildView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Form {
            Section("Build Options") {
                Toggle("Export Bom.txt after build", isOn: $model.exportsBOM)
                Toggle("Skip signing", isOn: $model.skipsSigning)
                Toggle("Skip notarization", isOn: $model.skipsNotarization)
                Toggle("Skip stapling", isOn: $model.skipsStapling)
            }
            Section("Actions") {
                Button("Build Package", systemImage: "hammer", action: model.build)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canBuild)
                Button("Synchronize from Bom.txt", systemImage: "arrow.triangle.2.circlepath", action: model.synchronizeBOM)
                    .disabled(model.isRunning)
                Button("Cancel Operation", systemImage: "xmark.circle", role: .cancel, action: model.cancelOperation)
                    .disabled(!model.isRunning || model.isCancelling)
                Button("Reveal Built Package", systemImage: "shippingbox", action: model.revealBuiltPackage)
                    .disabled(model.builtPackageURL == nil)
            }
            Section("Activity") {
                if model.isRunning {
                    ProgressView(model.statusMessage)
                } else {
                    LabeledContent("Status", value: model.statusMessage)
                }
                if model.activityLog.isEmpty {
                    Text("Build and project activity will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.activityLog.indices, id: \.self) { index in
                        Text(model.activityLog[index])
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Build")
    }
}
