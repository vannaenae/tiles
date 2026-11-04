/// Pure operations on an ordered list of window identifiers. Index 0 is the
/// master / first tile. Generic so tests can use plain integers.
public enum TilingOrder {
    /// Reconciles `order` with the windows currently present: drops windows that
    /// went away and inserts new ones according to `placement`.
    public static func sync<ID: Hashable>(
        _ order: [ID],
        present: [ID],
        placement: NewWindowPlacement,
        focused: ID?
    ) -> [ID] {
        let presentSet = Set(present)
        var result = order.filter { presentSet.contains($0) }
        var known = Set(result)
        for id in present where !known.contains(id) {
            switch placement {
            case .end:
                result.append(id)
            case .master:
                result.insert(id, at: 0)
            case .afterFocused:
                if let f = focused, f != id, let i = result.firstIndex(of: f) {
                    result.insert(id, at: i + 1)
                } else {
                    result.append(id)
                }
            }
            known.insert(id)
        }
        return result
    }

    public static func swap<ID: Equatable>(_ order: [ID], _ a: ID, _ b: ID) -> [ID] {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b), i != j else { return order }
        var result = order
        result.swapAt(i, j)
        return result
    }

    /// Moves `id` to the master position. If it already is master, swaps it with
    /// the next window so the shortcut toggles between the top two.
    public static func promote<ID: Equatable>(_ order: [ID], _ id: ID) -> [ID] {
        guard let i = order.firstIndex(of: id) else { return order }
        var result = order
        if i == 0 {
            if result.count > 1 { result.swapAt(0, 1) }
            return result
        }
        result.remove(at: i)
        result.insert(id, at: 0)
        return result
    }

    public static func remove<ID: Equatable>(_ order: [ID], _ id: ID) -> [ID] {
        order.filter { $0 != id }
    }

    /// Next or previous id, wrapping around.
    public static func cycle<ID: Equatable>(_ order: [ID], from id: ID?, forward: Bool) -> ID? {
        guard !order.isEmpty else { return nil }
        guard let id, let i = order.firstIndex(of: id) else { return order.first }
        let n = order.count
        return order[(i + (forward ? 1 : n - 1)) % n]
    }
}
