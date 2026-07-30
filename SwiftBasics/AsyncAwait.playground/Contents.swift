import Foundation

// ===== An async function — simulates work that takes time =====
func fetchData() async -> String {
    print("Fetching data...")
    // Simulate a 2-second delay (like a network request)
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    return "Data received!"
}

// ===== Another async function that calls it =====
func loadUserProfile() async {
    print("Loading profile...")
    let result = await fetchData()   // waits here without freezing
    print(result)
    print("Profile loaded!")
}

// ===== Run the async work from a Task =====
Task {
    await loadUserProfile()
}

print("This line runs immediately, while fetchData is still waiting")
