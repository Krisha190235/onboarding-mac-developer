#!/usr/bin/env swift
//
//  NetworkManager.swift - 9.6 Build a Networking Layer
//
//  Everything from 9.1-9.5 assembled into one reusable layer: a generic
//  Endpoint that knows what type it returns, a NetworkManager that sends any
//  of them, retry and idempotency from 9.4, error mapping from 9.5, and an
//  injectable client so the whole thing can be tested without a network.
//
//  Run it:
//      swift API/NetworkManager.swift
//
//  Demos 1-2 hit api.github.com. Demos 3-5 use a stub client and run offline.
//
//  Requires Swift 5.7 or later for top-level `await`.
//

import Foundation

// MARK: - Shared configuration
//
// Static properties on a caseless enum rather than global `let`s: they're lazy,
// order-independent, and the enum can't be instantiated by accident.

enum API {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - Errors (condensed from 9.5)

enum NetworkError: LocalizedError {
    case invalidURL(String)
    case offline
    case timedOut
    case cancelled
    case http(status: Int, body: String)
    case malformedResponse(DecodingError)
    case unknown(Error)

    /// Safe to show a user. No status codes, no coding paths.
    var userMessage: String {
        switch self {
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .timedOut:
            return "The server took too long to respond."
        case .cancelled:
            return ""                                  // deliberately shown to nobody
        case .http(let status, _) where status == 401 || status == 403:
            return "Your session has expired. Please sign in again."
        case .http(let status, _) where (500...599).contains(status):
            return "The server is having trouble. Try again in a moment."
        case .http, .invalidURL, .malformedResponse, .unknown:
            return "Something went wrong."
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):        return "couldn't build a URL from '\(path)'"
        case .offline:                     return "URLError.notConnectedToInternet"
        case .timedOut:                    return "URLError.timedOut"
        case .cancelled:                   return "cancelled"
        case .http(let status, let body):  return "HTTP \(status): \(body.prefix(120))"
        case .malformedResponse(let e):    return "decoding: \(describe(e))"
        case .unknown(let e):              return "unexpected: \(e)"
        }
    }

    /// The layer retries on this and nothing else.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut:
            return true
        case .http(let status, _):
            return (500...599).contains(status) || status == 408 || status == 429
        case .cancelled, .invalidURL, .malformedResponse, .unknown:
            return false
        }
    }
}

func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
        let parts = context.codingPath.map { key -> String in
            if let index = key.intValue { return "[\(index)]" }
            return key.stringValue
        }
        return parts.isEmpty ? "<root>" : parts.joined(separator: ".")
    }

    switch error {
    case .keyNotFound(let key, let context):
        return "missing key '\(key.stringValue)' at \(path(context))"
    case .typeMismatch(let type, let context):
        return "expected \(type) at \(path(context))"
    case .valueNotFound(let type, let context):
        return "null where \(type) was required at \(path(context))"
    case .dataCorrupted(let context):
        return "corrupt data at \(path(context)) - \(context.debugDescription)"
    @unknown default:
        return "unknown decoding failure"
    }
}

func mapToNetworkError(_ error: Error) -> NetworkError {
    switch error {
    case let error as NetworkError:  return error
    case let error as DecodingError: return .malformedResponse(error)
    case let error as URLError:
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost: return .offline
        case .timedOut:                                       return .timedOut
        case .cancelled:                                      return .cancelled
        default:                                              return .unknown(error)
        }
    case is CancellationError: return .cancelled
    default:                   return .unknown(error)
    }
}

// MARK: - HTTPMethod

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// GET and PUT can be repeated safely by definition; POST and PATCH need an
    /// idempotency key before a retry is safe (9.4).
    var isIdempotent: Bool {
        self == .get || self == .put || self == .delete
    }
}

// MARK: - Endpoint
//
// The generic parameter is the whole design. An `Endpoint<Repo>` carries the
// knowledge that this call returns a Repo, so `send` infers the return type and
// the call site never passes a `.self` or casts anything:
//
//     let repo: Repo = try await network.send(.repo("apple/swift"))
//
// `decode` is a stored closure rather than a `Response.Type` constraint, which
// means an endpoint can return something that isn't Decodable at all - Void for
// a 204, or a Data passthrough for an image - without a second send() overload.

struct Endpoint<Response> {
    var method: HTTPMethod = .get
    var path: String
    var query: [String: String] = [:]
    var headers: [String: String] = [:]
    var body: Data?
    var decode: (Data) throws -> Response
}

extension Endpoint where Response: Decodable {
    static func get(_ path: String, query: [String: String] = [:]) -> Endpoint {
        Endpoint(method: .get, path: path, query: query, body: nil) { data in
            try API.decoder.decode(Response.self, from: data)
        }
    }

    static func post<Body: Encodable>(_ path: String, body: Body) throws -> Endpoint {
        Endpoint(method: .post,
                 path: path,
                 body: try API.encoder.encode(body)) { data in
            try API.decoder.decode(Response.self, from: data)
        }
    }
}

extension Endpoint where Response == Void {
    /// A 204 No Content has an empty body, which every JSON decoder rejects.
    /// Modelling it as `Endpoint<Void>` makes that a type-level fact instead of
    /// a special case buried in the manager.
    static func delete(_ path: String) -> Endpoint {
        Endpoint(method: .delete, path: path, body: nil) { _ in () }
    }
}

// MARK: - The seam for testing
//
// NetworkManager talks to this, not to URLSession. Swapping in a stub is the
// difference between tests that need the internet, a fixture server and a
// working 503 on demand, and tests that are a dictionary of canned responses.

protocol HTTPClient {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Returns whatever the handler says, so a test can describe a 503, a timeout
/// or a truncated body in one line.
struct StubClient: HTTPClient {
    let handler: (URLRequest) async throws -> (Data, URLResponse)

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

// MARK: - NetworkManager

final class NetworkManager {
    private let baseURL: URL
    private let client: HTTPClient
    private let maxAttempts: Int
    private let timeout: TimeInterval
    private let backoffScale: Double
    private let tokenProvider: () async -> String?
    private let log: (String) -> Void

    init(baseURL: URL,
         client: HTTPClient = URLSession.shared,
         maxAttempts: Int = 3,
         timeout: TimeInterval = 15,
         // Injectable so a retry test runs in milliseconds instead of seconds.
         // A test suite that sleeps for real backoff stops being run.
         backoffScale: Double = 1.0,
         tokenProvider: @escaping () async -> String? = { nil },
         log: @escaping (String) -> Void = { print("      [net] \($0)") }) {
        self.baseURL = baseURL
        self.client = client
        self.maxAttempts = maxAttempts
        self.timeout = timeout
        self.backoffScale = backoffScale
        self.tokenProvider = tokenProvider
        self.log = log
    }

    /// The only public method. Generic over the endpoint's Response, so adding a
    /// call to the app means adding an Endpoint, not touching this file.
    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        // Built once, outside the loop, so the idempotency key and the auth
        // header are identical on every attempt (9.4).
        let request = try await makeRequest(for: endpoint)

        var attempt = 1
        while true {
            do {
                return try await attemptOnce(request, endpoint: endpoint, attempt: attempt)
            } catch {
                let mapped = mapToNetworkError(error)

                guard mapped.isRetryable, attempt < maxAttempts else {
                    log("\(endpoint.method.rawValue) \(endpoint.path) failed: \(mapped.errorDescription ?? "-")")
                    throw mapped
                }

                // Exponential backoff with jitter, so a fleet of clients coming
                // back after an outage doesn't stampede the server in lockstep.
                let backoff = (pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.3)) * backoffScale
                log("attempt \(attempt) failed (\(mapped.errorDescription ?? "-")), retrying in \(String(format: "%.1f", backoff))s")
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                attempt += 1
            }
        }
    }

    // MARK: Building

    private func makeRequest<Response>(for endpoint: Endpoint<Response>) async throws -> URLRequest {
        // appendingPathComponent percent-encodes the segment, which is what you
        // want for a name with a space in it and what you don't want if the
        // caller has already encoded it. Endpoints take raw paths, always.
        let url = baseURL.appendingPathComponent(endpoint.path)

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(endpoint.path)
        }
        if !endpoint.query.isEmpty {
            // Sorted so the URL is stable - it makes cache keys and test
            // assertions deterministic.
            components.queryItems = endpoint.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL(endpoint.path)
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("onboarding-mac-developer/1.0", forHTTPHeaderField: "User-Agent")

        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !endpoint.method.isIdempotent {
            // Generated here, once, so all retries of this call carry the same
            // key and a server that supports it can collapse the duplicates.
            request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        }

        // Endpoint headers last, so an endpoint can override a default.
        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        // Auth is resolved per request, not per manager: the token can be
        // refreshed between calls and nothing needs rebuilding.
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: One attempt

    private func attemptOnce<Response>(_ request: URLRequest,
                                       endpoint: Endpoint<Response>,
                                       attempt: Int) async throws -> Response {
        let start = Date()
        let (data, response) = try await client.perform(request)
        let elapsed = Date().timeIntervalSince(start)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        // Log the method, path, status and duration - never the headers. One
        // print of `request.allHTTPHeaderFields` puts a bearer token in a crash
        // report and there's no getting it back.
        log("\(endpoint.method.rawValue) \(endpoint.path) -> \(http.statusCode) "
            + "(\(String(format: "%.0f", elapsed * 1000))ms, attempt \(attempt), \(data.count)B)")

        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.http(status: http.statusCode,
                                    body: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try endpoint.decode(data)
        } catch let error as DecodingError {
            throw NetworkError.malformedResponse(error)
        }
    }
}

// MARK: - Models and endpoints for the demo
//
// In an app these extensions live next to the feature that uses them, and this
// is the payoff: adding a call is one static property, not a new method on the
// manager.

struct Repo: Decodable {
    let fullName: String
    let stargazersCount: Int
    let description: String?
}

struct Contributor: Decodable {
    let login: String
    let contributions: Int
}

extension Endpoint where Response == Repo {
    static func repo(_ fullName: String) -> Endpoint {
        .get("repos/\(fullName)")
    }
}

extension Endpoint where Response == [Contributor] {
    static func contributors(_ fullName: String, limit: Int = 3) -> Endpoint {
        .get("repos/\(fullName)/contributors", query: ["per_page": "\(limit)"])
    }
}

// MARK: - Stub helpers for the offline demos

/// Async-safe attempt counter, so the retry demo is deterministic.
actor AttemptCounter {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

func httpResponse(_ status: Int, for request: URLRequest) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid")!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil)!
}

let stubBase = URL(string: "https://example.invalid")!

// MARK: - Run them

let github = NetworkManager(baseURL: URL(string: "https://api.github.com")!)

func report(_ error: Error) {
    let mapped = mapToNetworkError(error)
    print("   log:      \(mapped.errorDescription ?? "-")")
    print("   user:     \(mapped.userMessage)")
    print("   retried:  \(mapped.isRetryable ? "yes" : "no")\n")
}

print("1. GET a repo - Endpoint<Repo>, no casting at the call site")
do {
    let repo: Repo = try await github.send(.repo("apple/swift-argument-parser"))
    print("   \(repo.fullName): \(repo.stargazersCount) stars")
    print("   \(repo.description ?? "no description")\n")
} catch {
    report(error)
}

print("2. Same send(), different Response type - Endpoint<[Contributor]>")
do {
    let contributors: [Contributor] = try await github.send(.contributors("apple/swift-argument-parser"))
    for person in contributors {
        print("   \(person.login) - \(person.contributions) commits")
    }
    print("")
} catch {
    report(error)
}

print("3. Retry - stub returns 503, 503, then 200 (no network)")
let flaky = AttemptCounter()
let flakyClient = StubClient { request in
    let attempt = await flaky.next()
    if attempt < 3 {
        return (Data(#"{"error":"overloaded"}"#.utf8), httpResponse(503, for: request))
    }
    let json = #"{"login":"krisha","contributions":42}"#
    return (Data(json.utf8), httpResponse(200, for: request))
}
do {
    // backoffScale shrinks the 1s and 2s waits to 100ms and 200ms.
    let manager = NetworkManager(baseURL: stubBase,
                                 client: flakyClient,
                                 maxAttempts: 3,
                                 backoffScale: 0.1)
    let person: Contributor = try await manager.send(.get("contributors/krisha"))
    print("   recovered: \(person.login), \(person.contributions) commits\n")
} catch {
    report(error)
}

print("4. A 404 is not retried - one attempt, then a message for the user")
let notFoundClient = StubClient { request in
    (Data(#"{"message":"Not Found"}"#.utf8), httpResponse(404, for: request))
}
do {
    let manager = NetworkManager(baseURL: stubBase, client: notFoundClient)
    let _: Repo = try await manager.send(.repo("nobody/nothing"))
    print("   unexpectedly succeeded\n")
} catch {
    report(error)
}

print("5. A 200 with the wrong shape - decoding failure, also not retried")
let wrongShapeClient = StubClient { request in
    // Valid JSON, valid status, wrong types: contributions as a string.
    (Data(#"{"login":"krisha","contributions":"42"}"#.utf8), httpResponse(200, for: request))
}
do {
    let manager = NetworkManager(baseURL: stubBase, client: wrongShapeClient)
    let _: Contributor = try await manager.send(.get("contributors/krisha"))
    print("   unexpectedly succeeded\n")
} catch {
    report(error)
}

// Notes that don't fit in code:
//  - Inside a sandboxed app this needs com.apple.security.network.client (8.4).
//  - The token provider is a closure so the Keychain lookup stays out of the
//    networking layer; NetworkManager never learns where the token comes from.
//  - What's deliberately not here: response caching (URLCache already does it),
//    in-flight request deduplication, and a reachability check - the request
//    failing is a better connectivity test than asking first.
