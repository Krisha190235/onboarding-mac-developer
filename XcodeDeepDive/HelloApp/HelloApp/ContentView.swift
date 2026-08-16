import SwiftUI

// MARK: - Testable logic (7.6 Unit Tests)

/// A tiny value type holding the counter logic, kept separate from the View so
/// it can be unit-tested without any UI. See HelloAppTests.
struct Counter {
    private(set) var count = 0
    private(set) var history: [Int] = []

    /// count * 2 — a simple computed value used in tests.
    var doubled: Int { count * 2 }

    /// Increments the count and records the new value in history.
    mutating func increment() {
        let next = count + 1
        history.append(next)
        count = next
    }

    /// Resets the counter back to its initial state.
    mutating func reset() {
        count = 0
        history.removeAll()
    }
}

/// Pure, testable version of the CPU workload used by the profiling exercise.
enum Workload {
    /// Sum of square roots from 1...n. Pure function → easy to unit-test.
    static func sqrtSum(upTo n: Int) -> Double {
        var total = 0.0
        if n >= 1 {
            for i in 1...n {
                total += Double(i).squareRoot()
            }
        }
        return total
    }
}

// MARK: - View

struct ContentView: View {
    @State private var counter = Counter()

    // Profiling state (7.4 Instruments)
    @State private var lastResult = 0.0
    @State private var isWorking = false
    @State private var blocks: [[Int]] = []   // held memory, visible in Allocations

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "ladybug.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)

            Text("Hello, I'm Krisha's first macOS app!")
                .font(.title2)

            Text("Count: \(counter.count)  (doubled: \(counter.doubled))")
                .font(.headline)
                .monospacedDigit()

            Button("Increment") {
                counter.increment()
            }

            Divider()

            // --- 7.4 Instruments: CPU & Memory workload ---
            Text("Profiling")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(isWorking ? "Working…" : "Run CPU Work") {
                runCPUWork()
            }
            .disabled(isWorking)

            Text("Result: \(lastResult, format: .number.precision(.fractionLength(2)))")
                .font(.footnote)
                .monospacedDigit()

            HStack {
                Button("Allocate ~80 MB") { allocateMemory() }
                Button("Release Memory") { releaseMemory() }
            }
            Text("Held blocks: \(blocks.count)")
                .font(.footnote)
                .monospacedDigit()
        }
        .padding()
        .frame(minWidth: 340, minHeight: 360)
    }

    /// CPU-heavy loop — shows up as a hot frame in Time Profiler.
    private func runCPUWork() {
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let total = Workload.sqrtSum(upTo: 20_000_000)
            DispatchQueue.main.async {
                lastResult = total
                isWorking = false
            }
        }
    }

    /// Allocates ~80 MB and keeps a reference so it stays resident.
    private func allocateMemory() {
        let block = Array(repeating: 0, count: 10_000_000)
        blocks.append(block)
    }

    /// Drops the references so ARC can reclaim the memory.
    private func releaseMemory() {
        blocks.removeAll()
    }
}

#Preview {
    ContentView()
}
