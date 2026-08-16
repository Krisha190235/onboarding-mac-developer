# 9.6 Build a Networking Layer

**Deliverable:** `NetworkManager` generic class.

The file: [`API/NetworkManager.swift`](NetworkManager.swift). Everything from
9.1–9.5 assembled into one reusable layer.

```bash
swift API/NetworkManager.swift
```

Demos 1–2 hit `api.github.com`; demos 3–5 use a stub client and run offline.

## The shape

```swift
struct Endpoint<Response> {
    var method: HTTPMethod = .get
    var path: String
    var query: [String: String] = [:]
    var headers: [String: String] = [:]
    var body: Data?
    var decode: (Data) throws -> Response
}

final class NetworkManager {
    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response
}
```

One public method. Adding a call to the app means adding an `Endpoint`, not
touching the manager:

```swift
extension Endpoint where Response == Repo {
    static func repo(_ fullName: String) -> Endpoint { .get("repos/\(fullName)") }
}

let repo: Repo = try await network.send(.repo("apple/swift-argument-parser"))
```

## Why `Endpoint` carries the type

The generic parameter is the design. An `Endpoint<Repo>` *is* the knowledge that
this call returns a `Repo`, so `send` infers its return type and the call site
passes no `.self` and casts nothing.

`decode` is a **stored closure** rather than a `Response: Decodable` constraint on
the struct itself. That's the part worth arguing about, and the reason is
`Endpoint<Void>`:

```swift
extension Endpoint where Response == Void {
    static func delete(_ path: String) -> Endpoint {
        Endpoint(method: .delete, path: path, body: nil) { _ in () }
    }
}
```

A **204 No Content** has an empty body, which every JSON decoder rejects. With a
`Decodable` constraint you need a second `send` overload and a status-code check
buried inside the manager; with a closure it's a type-level fact and the manager
never learns that 204 exists. Same trick covers a `Data` passthrough for an image
or a CSV.

The convenience constructors still keep the common path short — `.get` and
`.post` are constrained to `Response: Decodable` and fill the closure in for you.

## The seam that makes it testable

```swift
protocol HTTPClient {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient { ... }
```

`NetworkManager` talks to `HTTPClient`, never to `URLSession` directly. That one
indirection is the difference between tests that need the internet, a fixture
server and a working 503 on demand, and tests that are a closure:

```swift
let client = StubClient { request in
    (Data(#"{"message":"Not Found"}"#.utf8), httpResponse(404, for: request))
}
```

Demos 3–5 are exactly that: a flaky server that fails twice then succeeds, a 404,
and a 200 carrying the wrong types. None of them touch the network, all of them
run in milliseconds, and none can fail because GitHub rate-limited the CI box.

`backoffScale` exists for the same reason. Real backoff is 1s then 2s; a test
suite that actually sleeps for three seconds per retry case stops getting run, so
the delay is injectable and the demo passes `0.1`.

## What the manager does per call

| Step | Detail |
| --- | --- |
| Build once | The request is constructed **before** the retry loop, so the idempotency key and auth header are identical on every attempt |
| Query | Sorted before encoding, so URLs are stable for cache keys and test assertions |
| Idempotency | `Idempotency-Key` added automatically for non-idempotent methods (9.4) |
| Auth | Resolved per request via an injected closure, so a refreshed token needs nothing rebuilt |
| Validate | `200...299` succeed; everything else becomes `NetworkError.http` with the body kept |
| Decode | `DecodingError` is wrapped in `.malformedResponse`, never surfaced raw |
| Retry | Only when `isRetryable` — exponential backoff with jitter |

The ordering detail that matters: **endpoint headers are applied after the
defaults**, so an endpoint can override `Accept`, and the auth header last, so
nothing can accidentally overwrite it.

## Retry, and what never gets retried

`NetworkError.isRetryable` (from 9.5) is the only thing the loop consults:

- **Retried** — offline, timed out, 5xx, 408, 429
- **Never** — any other 4xx, decoding failures, cancellation

Demos 4 and 5 exist to show the "never" half working. A 404 and a type mismatch
both fail on the first attempt and go straight to the user with a message, because
repeating either produces the same bytes and the same failure.

## Logging

```swift
log("\(endpoint.method.rawValue) \(endpoint.path) -> \(http.statusCode) (\(ms)ms, attempt \(attempt), \(data.count)B)")
```

Method, path, status, duration, size. **Never the headers.** One
`print(request.allHTTPHeaderFields)` puts a bearer token in a crash report and
there's no getting it back. The logger is injected too, so the app can route it to
`OSLog` and the tests can capture it.

## What's deliberately not in here

- **Response caching** — `URLCache` already does HTTP caching properly, including
  ETags. Re-implementing it badly is a classic own goal.
- **In-flight request deduplication** — useful, but it needs an actor and a
  keying scheme, and it belongs one layer up where "the same request" is
  actually definable.
- **A reachability check before requesting** — the request failing *is* the
  connectivity test, and asking first adds a race where the answer is stale by
  the time you use it.

## Security notes

- Inside a sandboxed app this needs `com.apple.security.network.client` (8.4).
- The token provider is a closure so the Keychain lookup stays outside the
  networking layer — `NetworkManager` never learns where the token comes from,
  which also means a test never needs a Keychain.
- Response bodies are kept in the error for logging, so they're for local logs
  only, not analytics: a 4xx body can contain personal data.

## What I learned

The generic parameter does more work than it looks like. Once `Endpoint` knows its
own response type, the manager stops needing to know anything about any specific
call, and the file stops growing when the app does — new calls are new endpoints,
declared next to the feature that uses them.

The other lesson was the `HTTPClient` protocol. It's four lines and it changes what
kind of tests are possible: every failure from 9.5 that I could only demonstrate by
finding a cooperative endpoint becomes a two-line stub. Building error handling
first and the layer second made that obvious — I already knew exactly which
failures needed a seam to test.

## Sources

- [URL Loading System](https://developer.apple.com/documentation/foundation/url-loading-system) — Apple
- [`URLSession.data(for:)`](https://developer.apple.com/documentation/foundation/urlsession/data(for:delegate:)) — Apple
- [Generics](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/generics/) — The Swift Programming Language
- [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) — Apple
