import Foundation

enum ProjectSection: String, CaseIterable, Identifiable {
    case general
    case behavior
    case contents
    case distribution
    case signing
    case notarization
    case build

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .behavior: "Package Behavior"
        case .contents: "Project Contents"
        case .distribution: "Distribution"
        case .signing: "Signing"
        case .notarization: "Notarization"
        case .build: "Build"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "shippingbox"
        case .behavior: "switch.2"
        case .contents: "folder"
        case .distribution: "square.stack.3d.up"
        case .signing: "signature"
        case .notarization: "checkmark.seal"
        case .build: "hammer"
        }
    }
}
