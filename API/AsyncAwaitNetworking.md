# 9.3 Async/Await Networking

**Deliverable:** converted async/await example.

The file: [`API/AsyncAwaitNetworking.swift`](AsyncAwaitNetworking.swift). It does
the same job twice — two dependent GitHub requests with completion handlers, then
the same thing with async/await — and then shows the tools that make the
conversion possible.

```bash
swift API/AsyncAwaitNetworking.swift
swift API/AsyncAwaitNetworking.swift apple/swift-collections
```

| Section | What it demonstrates |
| --- | --- |
| 1 | Completion handlers: nested closures, an error path per level, `resume()` |
| 2 | The same logic with `async`/`await` — flat, errors via `throws` |
| 3 | `withCheckedThrowingContinuation` bridging a callback API you can't change |
| 4 | `async let` running independent requests in parallel |
| 5 | `withThrowingTaskGroup` when the number of calls isn't known up front |
| 6 | Cancellation propagating into `URLSession` for free |

## Before

```swift
URLSession.shared.dataTask(with: request) { data, response, error in
    if let error { completion(.failure(error)); return }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { … }
    guard let data else { … }
    do {
        let repo = try JSONDecoder().decode(Repo.self, from: data)
        URLSession.shared.dataTask(with: request2) { data2, response2, error2 in
            // the same four checks again, one level deeper
        }.resume()
    } catch { completion(.failure(error)) }
}.resume()
```

## After

```swift
func fetchJSON<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    let (data, response) = try await URLSession.shared.data(for: request(path))
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw NetError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return try JSONDecoder().decode(T.self, from: data)
}

let repo = try await fetchJSON(Repo.self, from: "repos/\(name)")
let languages = try await fetchJSON([String: Int].self, from: "repos/\(name)/languages")
```

Same behaviour, a third of the code, and — the part that matters — the second
version is *generic*. The callback version couldn't easily be, because every
extra layer of nesting has to re-thread the completion handler.

## The mechanical conversion

| Completion-handler code | async/await equivalent |
| --- | --- |
| `completion: @escaping (Result<T, Error>) -> Void` | `async throws -> T` |
| `completion(.failure(error))` | `throw error` |
| `completion(.success(value))` | `return value` |
| Nesting call B inside call A's closure | Two sequential `await` lines |
| Two independent calls, both nested | `async let` for each, one `await` at the end |
| `DispatchQueue.main.async { }` at the end | `@MainActor` on the function or type |
| A manual `isCancelled` flag | `Task.checkCancellation()`, or just cancellation propagating |
| Forgetting `.resume()` → silent hang | Impossible; there's nothing to forget |

Checklist I'd follow on real code:

1. Change the signature to `async throws` and delete the completion parameter.
2. Replace `completion(.success(x))` with `return x`, `completion(.failure(e))`
   with `throw e`.
3. Unnest: each nested call becomes the next line.
4. At the call sites, wrap in `Task { }` if you're crossing from sync code.
5. Only then look for calls that don't depend on each other, and switch those to
   `async let` or a task group.

## Bridging what you can't rewrite

Old APIs — delegates, C callbacks, a framework you don't own — convert with a
continuation:

```swift
func fetchRepoBridged(_ repo: String) async throws -> (Repo, [String: Int]) {
    try await withCheckedThrowingContinuation { continuation in
        fetchRepoWithCompletion(repo) { result in
            continuation.resume(with: result)
        }
    }
}
```

The rule is exact: **resume the continuation once on every path.** Twice traps,
never leaves the caller suspended forever. `withChecked…` detects both at runtime
and tells you; `withUnsafe…` is the same thing without the checking, and isn't
worth the risk until something is proven hot.

## Parallelism is a separate decision

Converting to async/await doesn't make anything faster on its own — sequential
`await`s are still sequential, which is correct when the second call needs the
first one's result. The speed-up comes from saying so explicitly:

```swift
async let details = fetchJSON(Repo.self, from: "repos/\(name)")
async let contributors = fetchJSON([Contributor].self, from: "repos/\(name)/contributors")
let (repo, people) = try await (details, contributors)   // ~ the slower of the two
```

Both requests start at the `async let`; the `await` is only where the values get
used. For a variable number of calls, `withThrowingTaskGroup` does the same with
`addTask`, and the group cancels the remaining children if one throws.

## Cancellation

This is the quiet win. Cancelling a `Task` cancels the `URLSession` work inside
it, and child tasks inherit the cancellation:

```swift
let task = Task { try await fetchJSON(Repo.self, from: "repos/\(name)") }
task.cancel()   // the in-flight request is cancelled too
```

In a SwiftUI view, `.task { }` cancels automatically when the view goes away —
which is the whole class of "callback fires after the screen closed" bug removed
rather than defended against.

## What I learned

The conversion is mostly deletion. What the callback version spends lines on —
threading a completion through every branch, re-checking the same four failure
conditions per level, remembering `.resume()`, hopping back to the main queue —
is either free or impossible to get wrong with `async`/`await`. The genuinely new
thinking is afterwards: which calls actually depend on each other, and therefore
which ones should have been parallel all along.

## Sources

- [Concurrency — The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [Updating an app to use Swift concurrency](https://developer.apple.com/documentation/swift/updating-an-app-to-use-swift-concurrency) — Apple
- [`withCheckedThrowingContinuation`](https://developer.apple.com/documentation/swift/withcheckedthrowingcontinuation(function:_:)) — Apple
