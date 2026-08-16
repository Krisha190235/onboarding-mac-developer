/// Pure, testable version of the CPU workload used by the 7.4 profiling
/// exercise. Lives in the package so both the app and the tests can use it.
public enum Workload {
    /// Sum of square roots from `1...n`. Pure function → easy to unit-test.
    /// Returns 0 for `n < 1`.
    public static func sqrtSum(upTo n: Int) -> Double {
        var total = 0.0
        if n >= 1 {
            for i in 1...n {
                total += Double(i).squareRoot()
            }
        }
        return total
    }
}
