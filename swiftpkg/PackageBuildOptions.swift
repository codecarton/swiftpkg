import Foundation

/// Frontend-neutral choices that affect one package build.
public struct PackageBuildOptions: Sendable {
    public let requestedFormat: BuildInfoFormat?
    public let exportsBOM: Bool
    public let isQuiet: Bool
    public let skipsSigning: Bool
    public let skipsNotarization: Bool
    public let skipsStapling: Bool
    /// Overrides the build-info version (resolved before `${version}` substitution).
    public let versionOverride: String?
    /// Writes the package here instead of the project's `build/` directory.
    public let outputDirectory: URL?

    public init(
        requestedFormat: BuildInfoFormat? = nil,
        exportsBOM: Bool = false,
        isQuiet: Bool = false,
        skipsSigning: Bool = false,
        skipsNotarization: Bool = false,
        skipsStapling: Bool = false,
        versionOverride: String? = nil,
        outputDirectory: URL? = nil
    ) {
        self.requestedFormat = requestedFormat
        self.exportsBOM = exportsBOM
        self.isQuiet = isQuiet
        self.skipsSigning = skipsSigning
        self.skipsNotarization = skipsNotarization
        self.skipsStapling = skipsStapling
        self.versionOverride = versionOverride
        self.outputDirectory = outputDirectory
    }
}
