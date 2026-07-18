public enum SigningTimestampMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, enabled, disabled

    public var id: String { rawValue }
}
