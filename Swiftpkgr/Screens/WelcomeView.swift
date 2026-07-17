import SwiftPkgCore
import SwiftUI

struct WelcomeView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack {
                Text("Swiftpkgr")
                    .font(.largeTitle)
                    .bold()
                Text("Create Apple installer packages with the same projects as swiftpkg.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Picker("Build-info format", selection: $model.newProjectFormat) {
                ForEach(BuildInfoFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .frame(maxWidth: 320)
            VStack {
                Button("New Project…", systemImage: "plus", action: model.createNewProject)
                    .buttonStyle(.borderedProminent)
                Button("Open Project…", systemImage: "folder", action: model.chooseProjectToOpen)
                Button("Import Package…", systemImage: "shippingbox.and.arrow.backward", action: model.choosePackageToImport)
                Button("Convert Existing Folder…", systemImage: "folder.badge.gearshape", action: model.convertExistingFolder)
            }
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WelcomeView(model: ProjectEditorModel())
}
