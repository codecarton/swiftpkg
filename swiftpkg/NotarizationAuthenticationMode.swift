public enum NotarizationAuthenticationMode: String, CaseIterable, Identifiable, Sendable {
    case none, keychainProfile, appleID

    public var id: String { rawValue }
}
