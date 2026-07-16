import Foundation
import Yams

enum BuildInfoFormat: String, CaseIterable {
    case plist, json, yaml, yml
}

struct BuildInfo {
    private(set) var values: [String: Any]

    init(values: [String: Any]) { self.values = values }

    static func defaults(for project: URL) -> BuildInfo {
        let base = project.lastPathComponent.replacingOccurrences(of: " ", with: "")
        return BuildInfo(values: [
            "ownership": "recommended",
            "suppress_bundle_relocation": true,
            "postinstall_action": "none",
            "preserve_xattr": false,
            "name": "\(base)-${version}.pkg",
            "identifier": "com.github.munki.pkg.\(base)",
            "install_location": "/",
            "version": "1.0",
            "distribution_style": false
        ])
    }

    mutating func mergeSupported(_ incoming: [String: Any]) {
        for key in Self.supportedKeys where incoming[key] != nil { values[key] = incoming[key] }
    }

    mutating func set(_ value: Any?, for key: String) { values[key] = value }
    func any(_ key: String) -> Any? { values[key] }
    func string(_ key: String) -> String? { scalarString(values[key]) }
    func bool(_ key: String, default fallback: Bool = false) -> Bool { values[key] as? Bool ?? fallback }
    func dictionary(_ key: String) -> [String: Any]? { values[key] as? [String: Any] }

    mutating func substituteVersion() {
        let version = string("version") ?? "1.0"
        for key in ["name", "title"] {
            if let value = string(key), value.contains("${version}") {
                values[key] = value.replacingOccurrences(of: "${version}", with: version)
            }
        }
    }

    func validated(source: String) throws -> BuildInfo {
        let allowed: [String: [AnyHashable]] = [
            "compression": ["legacy", "latest"],
            "ownership": ["recommended", "preserve", "preserve-other"],
            "postinstall_action": ["none", "logout", "restart"],
            "suppress_bundle_relocation": [true, false],
            "distribution_style": [true, false],
            "preserve_xattr": [true, false]
        ]
        for (key, legal) in allowed {
            if let value = values[key] as? AnyHashable, !legal.contains(value) {
                throw MunkiPkgError.message("\(source) key '\(key)' has illegal value: \(value). Legal values are: \(legal)")
            }
        }
        for key in ["name", "identifier", "version", "ownership", "postinstall_action"] where string(key) == nil {
            throw MunkiPkgError.message("\(source) is missing required key '\(key)' or it has an invalid type")
        }
        return self
    }

    static let supportedKeys = [
        "compression", "name", "identifier", "version", "ownership",
        "install_location", "min-os-version", "large-payload",
        "postinstall_action", "preserve_xattr", "suppress_bundle_relocation",
        "distribution_style", "signing_info", "notarization_info", "title",
        "product id"
    ]
}

enum BuildInfoIO {
    static func load(project: URL, options: CLIOptions, fileManager: FileManager = .default) throws -> BuildInfo {
        let base = project.appendingPathComponent("build-info")
        let selected: BuildInfoFormat
        if options.yaml { selected = .yaml }
        else if options.json { selected = .json }
        else {
            let found = BuildInfoFormat.allCases.filter {
                fileManager.itemExists(at: base.appendingPathExtension($0.rawValue))
            }
            guard found.count <= 1 else { throw MunkiPkgError.message("Multiple build-info files found!") }
            guard let only = found.first else { throw MunkiPkgError.message("No build-info file found!") }
            selected = only
        }
        let url = base.appendingPathExtension(selected.rawValue)
        guard fileManager.itemExists(at: url) else { throw MunkiPkgError.message("No build-info file found!") }
        let data = try Data(contentsOf: url)
        let object: Any
        do {
            switch selected {
            case .plist: object = try PropertyListSerialization.propertyList(from: data, format: nil)
            case .json: object = try JSONSerialization.jsonObject(with: data)
            case .yaml, .yml: object = try Yams.load(yaml: String(decoding: data, as: UTF8.self)) as Any
            }
        } catch {
            throw MunkiPkgError.message("\(url.path) is not a valid \(selected.rawValue) file: \(error.localizedDescription)")
        }
        guard let dictionary = object as? [String: Any] else {
            throw MunkiPkgError.message("\(url.path) must contain a dictionary")
        }
        var info = BuildInfo.defaults(for: project)
        info.mergeSupported(dictionary)
        try info = info.validated(source: url.path)
        info.substituteVersion()
        return info
    }

    static func write(_ info: BuildInfo, project: URL, options: CLIOptions) throws {
        let format: BuildInfoFormat = options.json ? .json : options.yaml ? .yaml : .plist
        let url = project.appendingPathComponent("build-info").appendingPathExtension(format.rawValue)
        let data: Data
        switch format {
        case .plist:
            data = try PropertyListSerialization.data(fromPropertyList: info.values, format: .xml, options: 0)
        case .json:
            data = try JSONSerialization.data(withJSONObject: info.values, options: [.prettyPrinted, .sortedKeys])
        case .yaml, .yml:
            data = Data(try Yams.dump(object: info.values, sortKeys: true).utf8)
        }
        try data.write(to: url, options: .atomic)
    }
}
