import Testing
import CounterKit

// 7.6 Unit Tests — Swift Testing
// Six tests covering the Counter logic and the Workload pure function.
// 7.7 — Counter and Workload now come from the CounterKit local package, so
// these exercise the app's dependency through its public API.

@Test("increment increases count by one")
func incrementIncreasesCount() {
    var counter = Counter()
    counter.increment()
    #expect(counter.count == 1)
}

@Test("doubled returns twice the count")
func doubledIsTwiceCount() {
    var counter = Counter()
    counter.increment()
    counter.increment()
    counter.increment()
    #expect(counter.count == 3)
    #expect(counter.doubled == 6)
}

@Test("history records every increment in order")
func historyRecordsEachIncrement() {
    var counter = Counter()
    counter.increment()
    counter.increment()
    #expect(counter.history == [1, 2])
}

@Test("reset returns the counter to its initial state")
func resetClearsCounter() {
    var counter = Counter()
    counter.increment()
    counter.increment()
    counter.reset()
    #expect(counter.count == 0)
    #expect(counter.history.isEmpty)
}

@Test("sqrtSum of 1...4 equals the expected total")
func sqrtSumIsCorrect() {
    // sqrt(1)+sqrt(2)+sqrt(3)+sqrt(4) ≈ 1 + 1.41421 + 1.73205 + 2 = 6.14626
    let result = Workload.sqrtSum(upTo: 4)
    #expect(abs(result - 6.14626) < 0.0001)
}

@Test("sqrtSum of 0 is zero")
func sqrtSumOfZeroIsZero() {
    #expect(Workload.sqrtSum(upTo: 0) == 0)
}
