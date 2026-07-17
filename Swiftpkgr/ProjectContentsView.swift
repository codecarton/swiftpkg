import SwiftUI

struct ProjectContentsView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        Form {
            Section("Payload") {
                if let payloadURL = model.payloadURL {
                    LabeledContent("Location", value: payloadURL.path)
                    Button("Reveal Payload", systemImage: "folder", action: model.revealPayload)
                } else {
                    ContentUnavailableView(
                        "Payload-Free Package",
                        systemImage: "shippingbox",
                        description: Text("This project has no payload directory.")
                    )
                }
            }
            Section("Scripts") {
                if let scriptsURL = model.scriptsURL {
                    LabeledContent("Location", value: scriptsURL.path)
                    Button("Reveal Scripts", systemImage: "folder", action: model.revealScripts)
                } else {
                    ContentUnavailableView(
                        "No Scripts Directory",
                        systemImage: "terminal",
                        description: Text("Add preinstall or postinstall scripts in the project scripts directory.")
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Project Contents")
    }
}
