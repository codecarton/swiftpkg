import SwiftUI

@main
struct SwiftpkgrApp: App {
    @State private var model = ProjectEditorModel()

    var body: some Scene {
        WindowGroup {
            ProjectEditorView(model: model)
        }
        .defaultSize(width: 960, height: 680)
        .commands {
            SwiftpkgrCommands(model: model)
        }

        Settings {
            ContentUnavailableView(
                "No Preferences",
                systemImage: "gearshape",
                description: Text("Swiftpkgr keeps package settings inside each project.")
            )
            .frame(minWidth: 420, minHeight: 220)
        }
    }
}
