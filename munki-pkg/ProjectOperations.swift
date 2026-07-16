import Darwin
import Foundation

struct ProjectOperations {
    let fileManager: FileManager
    let runner: any ProcessRunning
    let console: Console

    private let gitignore = """
    # .DS_Store files!
    .DS_Store

    # our build directory
    build/

    """

    func createProject(at project: URL, options: CLIOptions) throws {
        if fileManager.itemExists(at: project), !options.force {
            throw MunkiPkgError.message("\(project.path) already exists! Use --force to convert it to a project directory.")
        }
        if !fileManager.itemExists(at: project) {
            try fileManager.createDirectory(at: project, withIntermediateDirectories: false)
        }
        for name in ["payload", "scripts", "build"] {
            let directory = project.appendingPathComponent(name, isDirectory: true)
            if fileManager.itemExists(at: directory) {
                throw MunkiPkgError.message("\(directory.path) already exists")
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try BuildInfoIO.write(.defaults(for: project), project: project, options: options)
        try writeGitignore(project: project)
        console.display("Created new package project at \(project.path)")
    }

    func writeGitignore(project: URL) throws {
        try Data(gitignore.utf8).write(to: project.appendingPathComponent(".gitignore"), options: .atomic)
    }

    func exportBOM(from bom: URL, project: URL) throws {
        let result = try runner.run(ToolPaths.lsbom, [bom.path])
        guard result.status == 0 else {
            throw MunkiPkgError.message(result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try result.stdout.write(to: project.appendingPathComponent("Bom.txt"), options: .atomic)
    }

    func hasNonRecommendedOwnership(project: URL) -> Bool {
        let url = project.appendingPathComponent("Bom.txt")
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return contents.split(whereSeparator: \.isNewline).contains { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            return fields.count >= 3 && fields[2] != "0/0"
        }
    }

    func syncFromBOM(project: URL, options: CLIOptions) throws {
        let bom = project.appendingPathComponent("Bom.txt")
        let payload = project.appendingPathComponent("payload", isDirectory: true)
        guard fileManager.itemExists(at: bom) else {
            throw MunkiPkgError.message("Can't sync with bom info: no Bom.txt found in project directory.")
        }
        var buildInfo = (try? BuildInfoIO.load(project: project, options: options)) ?? .defaults(for: project)
        buildInfo.substituteVersion()
        let isRoot = geteuid() == 0
        if buildInfo.string("ownership") != "recommended", !isRoot {
            console.warning("build-info ownership: \(buildInfo.string("ownership") ?? "unknown") might require using sudo to properly sync owner and group for payload files.")
        }
        let text = try String(contentsOf: bom, encoding: .utf8)
        var changes = 0
        for (lineNumber, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            guard !rawLine.isEmpty else { continue }
            let fields = rawLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else {
                throw MunkiPkgError.message("Malformed Bom.txt row \(lineNumber + 1): expected path, mode, and owner/group")
            }
            var relative = fields[0]
            if relative.hasPrefix("./") { relative.removeFirst(2) }
            let fullMode = fields[1]
            let ownerGroup = fields[2].split(separator: "/", omittingEmptySubsequences: false)
            guard ownerGroup.count == 2,
                  let owner = uid_t(ownerGroup[0]), let group = gid_t(ownerGroup[1]),
                  let desiredMode = mode_t(String(fullMode.suffix(4)), radix: 8) else {
                throw MunkiPkgError.message("Malformed Bom.txt metadata on row \(lineNumber + 1)")
            }
            let target = payload.appendingPathComponent(relative)
            if target.lastPathComponent.hasPrefix("._") {
                let other = String(target.lastPathComponent.dropFirst(2))
                console.warning("file \(relative) contains extended attributes or a resource fork for \(other). git and pkgbuild may not properly preserve extended attributes.")
                continue
            }
            var info = stat()
            let exists = target.path.withCString { lstat($0, &info) == 0 }
            if exists {
                let currentMode = info.st_mode & mode_t(0o7777)
                if currentMode != desiredMode {
                    console.display("Changing mode of \(target.path) to \(String(desiredMode, radix: 8))")
                    guard target.path.withCString({ lchmod($0, desiredMode) }) == 0 else {
                        throw posixError("Could not change mode", path: target.path)
                    }
                    changes += 1
                }
            } else if fullMode.hasPrefix("4") {
                console.display("Creating \(target.path) with mode \(String(desiredMode, radix: 8))")
                try fileManager.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: NSNumber(value: desiredMode)])
                changes += 1
                continue
            } else {
                throw MunkiPkgError.message("File \(target.path) is missing in payload")
            }
            if isRoot, info.st_uid != owner || info.st_gid != group {
                console.display("Changing user/group of \(target.path) to \(owner)/\(group)")
                guard target.path.withCString({ lchown($0, owner, group) }) == 0 else {
                    throw posixError("Could not change owner/group", path: target.path)
                }
                changes += 1
            }
        }
        console.display(changes == 0 ? "Sync successful: no changes needed." : "Sync successful.")
    }

    private func posixError(_ action: String, path: String) -> MunkiPkgError {
        .message("\(action) for \(path): \(String(cString: strerror(errno)))")
    }
}
