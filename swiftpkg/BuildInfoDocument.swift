import Foundation

public struct BuildInfoDocument: Sendable {
    public let url: URL
    public let format: BuildInfoFormat

    public init(url: URL, format: BuildInfoFormat) {
        self.url = url
        self.format = format
    }
}
