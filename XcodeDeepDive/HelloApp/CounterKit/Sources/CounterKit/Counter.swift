/// A tiny value type holding the counter logic, kept out of the View so it can
/// be unit-tested without any UI — and out of the app target entirely so it can
/// be reused by other projects.
public struct Counter: Equatable, Sendable {
    /// The current count. Only `increment()` and `reset()` can change it.
    public private(set) var count: Int
    /// Every value `count` has taken since the last reset, in order.
    public private(set) var history: [Int]

    /// Creates a counter starting at zero.
    public init() {
        self.count = 0
        self.history = []
    }

    /// `count * 2` — a simple computed value used in tests.
    public var doubled: Int { count * 2 }

    /// Increments the count and records the new value in `history`.
    public mutating func increment() {
        let next = count + 1
        history.append(next)
        count = next
    }

    /// Resets the counter back to its initial state.
    public mutating func reset() {
        count = 0
        history.removeAll()
    }
}
