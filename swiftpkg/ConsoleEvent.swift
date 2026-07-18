public enum ConsoleEvent: Sendable {
    case status(String)
    case warning(String)
    case error(String)

    public var message: String {
        switch self {
        case .status(let message), .warning(let message), .error(let message): message
        }
    }
}
