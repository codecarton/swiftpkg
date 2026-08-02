import Foundation

/// Frontend-neutral choices that affect one package build.
public struct PackageBuildOptions: Sendable {
    public let requestedFormat: BuildInfoFormat?
    public let exportsBOM: Bool
    public let isQuiet: Bool
    public let skipsSigning: Bool
    public let skipsNotarization: Bool
    public let skipsStapling: Bool
    /// Path to a `.env` file of build-time variables; nil auto-detects the
    /// project's `.env`.
    public let envFile: String?
    /// Fail the build if a script references a `${VAR}` with no matching variable.
    public let strictEnvironment: Bool
    /// Merge `SWIFTPKG_*` variables from the calling process environment.
    public let inheritsEnvironment: Bool
    /// Write a `<pkg>.provenance.json` sidecar recording tool version, build
    /// time, git commit/remote, an input digest, and the package hash.
    public let writesProvenance: Bool
    /// After building, assert the package matches what build-info declared
    /// (signature present when signing was requested, Gatekeeper-accepted when
    /// notarized). Fails the build on mismatch.
    public let verifies: Bool
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
        envFile: String? = nil,
        strictEnvironment: Bool = false,
        inheritsEnvironment: Bool = true,
        writesProvenance: Bool = false,
        verifies: Bool = false,
        versionOverride: String? = nil,
        outputDirectory: URL? = nil
    ) {
        self.requestedFormat = requestedFormat
        self.exportsBOM = exportsBOM
        self.isQuiet = isQuiet
        self.skipsSigning = skipsSigning
        self.skipsNotarization = skipsNotarization
        self.skipsStapling = skipsStapling
        self.envFile = envFile
        self.strictEnvironment = strictEnvironment
        self.inheritsEnvironment = inheritsEnvironment
        self.writesProvenance = writesProvenance
        self.verifies = verifies
        self.versionOverride = versionOverride
        self.outputDirectory = outputDirectory
    }
}
