/// A person's ⌃⌥F choice for one window. It beats the app rules until they press ⌃⌥F again.
/// One value per window, so "forced to float" and "forced to tile" can never both be set.
public enum FloatOverride: Equatable {
    case float
    case tile

    /// Whether a window floats, given its override (if any) and what the rules say.
    public static func floats(_ override: FloatOverride?, ruleSaysFloat: Bool) -> Bool {
        switch override {
        case .float: return true
        case .tile: return false
        case nil: return ruleSaysFloat
        }
    }

    /// The override after ⌃⌥F. A tiled window floats; a floating window tiles, and only needs
    /// an override when a rule would otherwise float it again.
    public static func toggled(isTiled: Bool, ruleSaysFloat: Bool) -> FloatOverride? {
        if isTiled { return .float }
        return ruleSaysFloat ? .tile : nil
    }
}
