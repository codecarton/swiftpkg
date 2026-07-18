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

    public init(
        requestedFormat: BuildInfoFormat? = nil,
        exportsBOM: Bool = false,
        isQuiet: Bool = false,
        skipsSigning: Bool = false,
        skipsNotarization: Bool = false,
        skipsStapling: Bool = false,
        envFile: String? = nil,
        strictEnvironment: Bool = false,
        inheritsEnvironment: Bool = true
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
    }
}
