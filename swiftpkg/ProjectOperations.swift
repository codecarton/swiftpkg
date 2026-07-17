import Darwin
import Foundation

/// Creates the conventional directory and configuration layout for a package project.
struct ProjectCreator {
    let fileManager: FileManager
    let console: Console

    func createProject(at project: URL, format: BuildInfoFormat, force: Bool) throws {
        if fileManager.itemExists(at: project), !force {
            throw MunkiPkgError.message("\(project.path) already exists! Use --force to convert it to a project directory.")
        }
        if !fileManager.itemExists(at: project) {
            try fileManager.createDirectory(at: project, withIntermediateDirectories: false)
        }
        for directoryName in ["payload", "scripts", "build"] {
            let directory = project.appendingPathComponent(directoryName, isDirectory: true)
            guard !fileManager.itemExists(at: directory) else { throw MunkiPkgError.message("\(directory.path) already exists") }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try BuildInfoStore.write(.defaults(for: project), to: project, format: format)
        try ProjectSupport(fileManager: fileManager).writeGitignore(in: project)
        console.display("Created new package project at \(project.path)")
    }
}

/// Exports and applies tracked BOM metadata for a package project.
struct BOMMetadataService {
    let fileManager: FileManager
    let runner: any ProcessRunning
    let console: Console

    func exportMetadata(from bom: URL, to project: URL) throws {
        let result = try runner.run(executable: ToolPaths.lsbom, arguments: [bom.path])
        guard result.status == 0 else {
            throw MunkiPkgError.processFailed(tool: "lsbom", message: result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try result.stdout.write(to: project.appendingPathComponent("Bom.txt"), options: .atomic)
    }

    func hasNonRecommendedOwnership(in project: URL) -> Bool {
        let url = project.appendingPathComponent("Bom.txt")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return contents.split(whereSeparator: \.isNewline).contains { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            return fields.count >= 3 && fields[2] != "0/0"
        }
    }

    func synchronizeMetadataFromBOM(in project: URL, requestedFormat: BuildInfoFormat?) throws {
        let bom = project.appendingPathComponent("Bom.txt")
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        guard fileManager.itemExists(at: bom) else { throw MunkiPkgError.message("Can't sync with bom info: no Bom.txt found in project directory.") }
        let packageConfiguration = (try? BuildInfoStore.load(from: project, requestedFormat: requestedFormat)) ?? .defaults(for: project)
        let isRoot = geteuid() == 0
        if packageConfiguration.ownership != .recommended, !isRoot {
            console.warning("build-info ownership: \(packageConfiguration.ownership.rawValue) might require using sudo to properly sync owner and group for payload files.")
        }
        let text = try String(contentsOf: bom, encoding: .utf8)
        var changes = 0
        for (lineNumber, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            guard !rawLine.isEmpty else { continue }
            let metadata = try BOMEntry(parsing: rawLine, lineNumber: lineNumber + 1)
            let target = payload.appendingPathComponent(metadata.relativePath)
            if target.lastPathComponent.hasPrefix("._") {
                console.warning("file \(metadata.relativePath) contains extended attributes or a resource fork for \(target.lastPathComponent.dropFirst(2)). git and pkgbuild may not properly preserve extended attributes.")
                continue
            }
            var fileStatus = stat()
            let exists = target.path.withCString { lstat($0, &fileStatus) == 0 }
            if exists {
                let currentMode = fileStatus.st_mode & mode_t(0o7777)
                if currentMode != metadata.mode {
                    console.display("Changing mode of \(target.path) to \(String(metadata.mode, radix: 8))")
                    guard target.path.withCString({ lchmod($0, metadata.mode) }) == 0 else { throw posixError("Could not change mode", path: target.path) }
                    changes += 1
                }
            } else if metadata.isDirectory {
                console.display("Creating \(target.path) with mode \(String(metadata.mode, radix: 8))")
                try fileManager.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: NSNumber(value: metadata.mode)])
                changes += 1
                continue
            } else {
                throw MunkiPkgError.message("File \(target.path) is missing in payload")
            }
            if isRoot, fileStatus.st_uid != metadata.owner || fileStatus.st_gid != metadata.group {
                console.display("Changing user/group of \(target.path) to \(metadata.owner)/\(metadata.group)")
                guard target.path.withCString({ lchown($0, metadata.owner, metadata.group) }) == 0 else { throw posixError("Could not change owner/group", path: target.path) }
                changes += 1
            }
        }
        console.display(changes == 0 ? "Sync successful: no changes needed." : "Sync successful.")
    }
}

/// Provides shared project-layout artifacts.
struct ProjectSupport {
    let fileManager: FileManager

    func writeGitignore(in project: URL) throws {
        let contents = """
        # .DS_Store files!
        .DS_Store

        # our build directory
        build/

        """
        try Data(contents.utf8).write(to: project.appendingPathComponent(".gitignore"), options: .atomic)
    }
}

private struct BOMEntry {
    let relativePath: String
    let mode: mode_t
    let owner: uid_t
    let group: gid_t
    let isDirectory: Bool

    init(parsing line: String, lineNumber: Int) throws {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 3 else { throw MunkiPkgError.message("Malformed Bom.txt row \(lineNumber): expected path, mode, and owner/group") }
        var path = fields[0]
        if path.hasPrefix("./") { path.removeFirst(2) }
        let ownerGroup = fields[2].split(separator: "/", omittingEmptySubsequences: false)
        guard ownerGroup.count == 2, let owner = uid_t(ownerGroup[0]), let group = gid_t(ownerGroup[1]), let mode = mode_t(String(fields[1].suffix(4)), radix: 8) else {
            throw MunkiPkgError.message("Malformed Bom.txt metadata on row \(lineNumber)")
        }
        relativePath = path
        self.mode = mode
        self.owner = owner
        self.group = group
        isDirectory = fields[1].hasPrefix("4")
    }
}

private func posixError(_ action: String, path: String) -> MunkiPkgError {
    .message("\(action) for \(path): \(String(cString: strerror(errno)))")
}
