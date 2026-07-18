/// Frontend-neutral choices that affect one package build.
public struct PackageBuildOptions: Sendable {
    public let requestedFormat: BuildInfoFormat?
    public let exportsBOM: Bool
    public let isQuiet: Bool
    public let skipsSigning: Bool
    public let skipsNotarization: Bool
    public let skipsStapling: Bool
    /// Write a `<pkg>.provenance.json` sidecar recording tool version, build
    /// time, git commit/remote, an input digest, and the package hash.
    public let writesProvenance: Bool

    public init(
        requestedFormat: BuildInfoFormat? = nil,
        exportsBOM: Bool = false,
        isQuiet: Bool = false,
        skipsSigning: Bool = false,
        skipsNotarization: Bool = false,
        skipsStapling: Bool = false,
        writesProvenance: Bool = false
    ) {
        self.requestedFormat = requestedFormat
        self.exportsBOM = exportsBOM
        self.isQuiet = isQuiet
        self.skipsSigning = skipsSigning
        self.skipsNotarization = skipsNotarization
        self.skipsStapling = skipsStapling
        self.writesProvenance = writesProvenance
    }
}
