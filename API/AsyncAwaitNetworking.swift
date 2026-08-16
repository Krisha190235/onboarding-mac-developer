#!/usr/bin/env swift
//
//  AsyncAwaitNetworking.swift - 9.3 Async/Await Networking
//
//  The same job written twice: once with completion handlers, once with
//  async/await. Then the tools that make the conversion possible -
//  withCheckedThrowingContinuation for legacy callbacks, async let and task
//  groups for work that doesn't need to be sequential.
//
//  Run it:
//      swift API/AsyncAwaitNetworking.swift
//      swift API/AsyncAwaitNetworking.swift apple/swift-argument-parser
//
//  Requires Swift 5.7 or later for top-level `await`.
//

import Foundation

let repoName = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "apple/swift-argument-parser"

// MARK: - Shared bits

struct Repo: Decodable {
    let fullName: String
    let stargazersCount: Int

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case stargazersCount = "stargazers_count"
    }
}

struct Contributor: Decodable {
    let login: String
    let contributions: Int
}

enum NetError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP status \(code)"
        }
    }
}

func request(_ path: String) -> URLRequest {
    var request = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("onboarding-mac-developer/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15
    return request
}

func elapsed(since start: Date) -> String {
    String(format: "%.2fs", Date().timeIntervalSince(start))
}

// MARK: - 1. The old way: completion handlers
//
// Two dependent calls - fetch the repo, then its languages. Note what the
// shape costs: a nested closure, `[weak self]`-style capture care in a real
// type, an error path repeated at every level, and a result that can only
// leave through the callback.

func fetchRepoWithCompletion(_ repo: String,
                             completion: @escaping (Result<(Repo, [String: Int]), Error>) -> Void) {
    URLSession.shared.dataTask(with: request("repos/\(repo)")) { data, response, error in
        if let error { completion(.failure(error)); return }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            completion(.failure(NetError.http(code)))
            return
        }
        guard let data else { completion(.failure(URLError(.zeroByteResource))); return }

        do {
            let decoded = try JSONDecoder().decode(Repo.self, from: data)

            // Second call, nested inside the first because it depends on it.
            URLSession.shared.dataTask(with: request("repos/\(repo)/languages")) { data2, response2, error2 in
                if let error2 { completion(.failure(error2)); return }

                guard let http2 = response2 as? HTTPURLResponse, http2.statusCode == 200 else {
                    let code = (response2 as? HTTPURLResponse)?.statusCode ?? -1
                    completion(.failure(NetError.http(code)))
                    return
                }
                guard let data2 else { completion(.failure(URLError(.zeroByteResource))); return }

                do {
                    let languages = try JSONDecoder().decode([String: Int].self, from: data2)
                    completion(.success((decoded, languages)))
                } catch {
                    completion(.failure(error))
                }
            }.resume()   // forgetting this is the classic silent hang
        } catch {
            completion(.failure(error))
        }
    }.resume()
}

// MARK: - 2. The same thing with async/await
//
// Same two calls, same error handling, no nesting. Errors propagate with
// `throws` instead of being hand-carried through every branch.

func fetchJSON<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    let (data, response) = try await URLSession.shared.data(for: request(path))
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw NetError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return try JSONDecoder().decode(T.self, from: data)
}

func fetchRepoAsync(_ repo: String) async throws -> (Repo, [String: Int]) {
    let details = try await fetchJSON(Repo.self, from: "repos/\(repo)")
    let languages = try await fetchJSON([String: Int].self, from: "repos/\(repo)/languages")
    return (details, languages)
}

// MARK: - 3. Bridging a callback API that you can't change
//
// This is the conversion tool: wrap the old function once, and every caller
// gets to be async. Resume the continuation exactly once on every path -
// twice is a crash, never is a permanent hang.

func fetchRepoBridged(_ repo: String) async throws -> (Repo, [String: Int]) {
    try await withCheckedThrowingContinuation { continuation in
        fetchRepoWithCompletion(repo) { result in
            continuation.resume(with: result)
        }
    }
}

// MARK: - Run them

print("Repo: \(repoName)\n")

// --- Completion-handler version. A script has to block to wait for it,
// which is itself a small demonstration of the problem.
let semaphore = DispatchSemaphore(value: 0)
let callbackStart = Date()

fetchRepoWithCompletion(repoName) { result in
    switch result {
    case .success(let (repo, languages)):
        print("1. completion handlers: \(repo.fullName), \(repo.stargazersCount) stars, "
              + "\(languages.count) languages [\(elapsed(since: callbackStart))]")
    case .failure(let error):
        print("1. completion handlers failed: \(error.localizedDescription)")
    }
    semaphore.signal()
}
semaphore.wait()

// --- async/await version
do {
    let start = Date()
    let (repo, languages) = try await fetchRepoAsync(repoName)
    print("2. async/await:         \(repo.fullName), \(repo.stargazersCount) stars, "
          + "\(languages.count) languages [\(elapsed(since: start))]")
} catch {
    print("2. async/await failed: \(error.localizedDescription)")
}

// --- the bridged version, proving the wrapper behaves like the native one
do {
    let start = Date()
    let (repo, _) = try await fetchRepoBridged(repoName)
    print("3. bridged callback:    \(repo.fullName) [\(elapsed(since: start))]")
} catch {
    print("3. bridged callback failed: \(error.localizedDescription)")
}

// MARK: - 4. Independent work should not be sequential
//
// `async let` starts both immediately and only suspends where the values are
// used, so the total is roughly the slower of the two rather than the sum.

do {
    let start = Date()
    async let details = fetchJSON(Repo.self, from: "repos/\(repoName)")
    async let contributors = fetchJSON([Contributor].self, from: "repos/\(repoName)/contributors")

    let (repo, people) = try await (details, contributors)
    print("4. async let (parallel): \(repo.fullName), \(people.count) contributors "
          + "[\(elapsed(since: start))]")
} catch {
    print("4. async let failed: \(error.localizedDescription)")
}

// MARK: - 5. A task group, when the number of calls isn't known up front

do {
    let start = Date()
    let repos = ["apple/swift-argument-parser", "apple/swift-collections", "apple/swift-algorithms"]

    let results = try await withThrowingTaskGroup(of: (String, Int).self) { group in
        for name in repos {
            group.addTask {
                let repo = try await fetchJSON(Repo.self, from: "repos/\(name)")
                return (repo.fullName, repo.stargazersCount)
            }
        }

        var collected: [(String, Int)] = []
        for try await pair in group { collected.append(pair) }
        return collected.sorted { $0.1 > $1.1 }
    }

    print("5. task group (\(results.count) repos) [\(elapsed(since: start))]:")
    for (name, stars) in results { print("     \(stars) stars  \(name)") }
} catch {
    print("5. task group failed: \(error.localizedDescription)")
}

// MARK: - 6. Cancellation
//
// Cancelling the Task cancels the URLSession work inside it - no flags to
// check by hand, no `isCancelled` plumbed through five layers.

let cancellable = Task {
    do {
        _ = try await fetchJSON(Repo.self, from: "repos/\(repoName)")
        print("6. cancellation: finished before it was cancelled")
    } catch is CancellationError {
        print("6. cancellation: task cancelled cleanly")
    } catch let error as URLError where error.code == .cancelled {
        print("6. cancellation: URLSession reported the cancellation")
    } catch {
        print("6. cancellation: \(error.localizedDescription)")
    }
}
cancellable.cancel()
_ = await cancellable.result

// In UI code the other win is that there's no DispatchQueue.main.async at the
// end of every callback: mark the function or type @MainActor and the compiler
// enforces where the update runs.
