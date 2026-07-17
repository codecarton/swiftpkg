import SwiftPkgCore

extension BuildInfoFormat {
    var displayName: String {
        switch self {
        case .plist: "Property List"
        case .json: "JSON"
        case .yaml: "YAML"
        case .yml: "YAML (.yml)"
        }
    }
}
