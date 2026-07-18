import SwiftPkgCore

extension PackageCompression {
    var displayName: String {
        switch self {
        case .legacy: "Legacy"
        case .latest: "Latest"
        }
    }
}
