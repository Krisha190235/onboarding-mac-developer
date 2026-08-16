import SwiftUI
import CounterKit   // 7.7 — local Swift package holding Counter and Workload

// MARK: - View

struct ContentView: View {
    @State private var counter = Counter()

    // Profiling state (7.4 Instruments)
    @State private var lastResult = 0.0
    @State private var isWorking = false
    @State private var blocks: [[Int]] = []   // held memory, visible in Allocations

    // Permissions sheet (8.2)
    @State private var showingPermissions = false

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

            Divider()

            // --- 8.2 Permission Request App ---
            Button("Permissions…") {
                showingPermissions = true
            }
        }
        .padding()
        .frame(minWidth: 340, minHeight: 420)
        .sheet(isPresented: $showingPermissions) {
            VStack(spacing: 0) {
                PermissionsView()
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { showingPermissions = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
        }
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
