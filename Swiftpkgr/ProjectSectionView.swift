import SwiftUI

struct ProjectSectionView: View {
    @Bindable var model: ProjectEditorModel

    var body: some View {
        switch model.selectedSection ?? .general {
        case .general:
            GeneralSettingsView(model: model)
        case .behavior:
            PackageBehaviorView(model: model)
        case .contents:
            ProjectContentsView(model: model)
        case .distribution:
            DistributionSettingsView(model: model)
        case .signing:
            SigningSettingsView(model: model)
        case .notarization:
            NotarizationSettingsView(model: model)
        case .build:
            BuildView(model: model)
        }
    }
}
