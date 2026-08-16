import Testing
@testable import CounterKit

// Package-level tests. These run with `swift test` from the CounterKit folder,
// or from Xcode's Test Navigator — separate from HelloAppTests, which tests the
// same package through the app.

@Test("a new counter starts empty")
func newCounterIsEmpty() {
    let counter = Counter()
    #expect(counter.count == 0)
    #expect(counter.doubled == 0)
    #expect(counter.history.isEmpty)
}

@Test("history length always matches the count")
func historyLengthMatchesCount() {
    var counter = Counter()
    for _ in 1...5 { counter.increment() }
    #expect(counter.count == 5)
    #expect(counter.history.count == counter.count)
    #expect(counter.history == [1, 2, 3, 4, 5])
}

@Test("a counter can be reused after reset")
func counterIsReusableAfterReset() {
    var counter = Counter()
    counter.increment()
    counter.reset()
    counter.increment()
    #expect(counter.count == 1)
    #expect(counter.history == [1])
    #expect(counter == Counter().incremented())
}

@Test("sqrtSum grows with n and ignores negatives")
func sqrtSumIsMonotonic() {
    #expect(Workload.sqrtSum(upTo: -5) == 0)
    #expect(Workload.sqrtSum(upTo: 0) == 0)
    #expect(Workload.sqrtSum(upTo: 10) > Workload.sqrtSum(upTo: 9))
}

// Small test helper — keeps the equality check above readable.
private extension Counter {
    func incremented() -> Counter {
        var copy = self
        copy.increment()
        return copy
    }
}
