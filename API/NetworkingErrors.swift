#!/usr/bin/env swift
//
//  NetworkingErrors.swift - 9.5 Networking Error Handling
//
//  The two failures every networking layer has to survive: the request that
//  never comes back, and the response that comes back in the wrong shape.
//  Timeouts (request vs resource), transport failures, cancellation, and all
//  four DecodingError cases - then one place that turns any of them into a
//  message a user can act on.
//
//  Run it:
//      swift API/NetworkingErrors.swift
//
//  Sections 1-4 hit the network (httpbin.org), section 5 is entirely local, so
//  the decoding examples still run with the wifi off.
//
//  Requires Swift 5.7 or later for top-level `await`.
//

import Foundation

// MARK: - One error type for the whole layer
//
// URLError, DecodingError and "HTTP 503" arrive from three different places and
// none of them are safe to show a user. Mapping them into a single enum at the
// edge of the networking layer means the UI asks one question - what do I tell
// the user, and is there any point in a Retry button - instead of pattern
// matching on Foundation's errors in a view.

enum NetworkError: LocalizedError {
    case offline
    case timedOut
    case cancelled
    case cannotReachServer(String)
    case http(status: Int, body: String)
    case malformedResponse(DecodingError)
    case unknown(Error)

    /// Safe to put in front of a user. No status codes, no coding paths.
    var userMessage: String {
        switch self {
        case .offline:
            return "You appear to be offline. Check your connection and try again."
        case .timedOut:
            return "The server took too long to respond."
        case .cancelled:
            return ""                       // never shown - see below
        case .cannotReachServer:
            return "Couldn't reach the server."
        case .http(let status, _) where status == 401 || status == 403:
            return "Your session has expired. Please sign in again."
        case .http(let status, _) where (500...599).contains(status):
            return "The server is having trouble. Try again in a moment."
        case .http:
            return "The app sent something the server didn't accept."
        case .malformedResponse:
            return "The server sent something unexpected."
        case .unknown:
            return "Something went wrong."
        }
    }

    /// For the log, not the screen. This is where the detail belongs.
    var errorDescription: String? {
        switch self {
        case .offline:                     return "URLError.notConnectedToInternet"
        case .timedOut:                    return "URLError.timedOut"
        case .cancelled:                   return "cancelled by us"
        case .cannotReachServer(let host): return "cannot reach \(host)"
        case .http(let status, let body):  return "HTTP \(status): \(body.prefix(120))"
        case .malformedResponse(let e):    return "decoding: \(describe(e))"
        case .unknown(let e):              return "unexpected: \(e)"
        }
    }

    /// A Retry button should only appear when retrying could plausibly help.
    /// Offering it on a 400 or a decoding failure just makes the user press it
    /// three times before giving up.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .cannotReachServer:
            return true
        case .http(let status, _):
            return (500...599).contains(status) || status == 408 || status == 429
        case .cancelled, .malformedResponse, .unknown:
            return false
        }
    }
}

/// Everything thrown inside the networking layer funnels through here.
func mapToNetworkError(_ error: Error) -> NetworkError {
    switch error {
    case let error as NetworkError:
        return error

    case let error as DecodingError:
        return .malformedResponse(error)

    case let error as URLError:
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timedOut
        // An async URLSession call that gets cancelled throws URLError.cancelled,
        // *not* CancellationError - so a `catch` that only looks for
        // CancellationError will show the user an error for something they did
        // on purpose (navigating away, typing the next character in a search).
        case .cancelled:
            return .cancelled
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .cannotReachServer(error.failingURL?.host ?? "server")
        default:
            return .unknown(error)
        }

    case is CancellationError:
        return .cancelled

    default:
        return .unknown(error)
    }
}

/// Turns a DecodingError into something you can act on. The default
/// `localizedDescription` for these is famously useless ("The data couldn't be
/// read because it is missing") - the useful parts are the coding path and the
/// debug description, and they're only reachable via the associated Context.
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
        return "expected \(type) at \(path(context)) - \(context.debugDescription)"
    case .valueNotFound(let type, let context):
        return "null where \(type) was required at \(path(context))"
    case .dataCorrupted(let context):
        return "corrupt data at \(path(context)) - \(context.debugDescription)"
    @unknown default:
        return "unknown decoding failure: \(error)"
    }
}

func report(_ label: String, _ error: Error) {
    let mapped = mapToNetworkError(error)
    print("   \(label)")
    print("      log:   \(mapped.errorDescription ?? "-")")
    if !mapped.userMessage.isEmpty {
        print("      user:  \(mapped.userMessage)")
    }
    print("      retry: \(mapped.isRetryable ? "yes" : "no")\n")
}

// MARK: - 1. Request timeout
//
// `timeoutInterval` on a URLRequest is NOT a deadline for the whole call. It's
// the maximum gap between packets - it resets every time data arrives. A slow
// download that keeps trickling will never trip it.

func requestTimeout() async throws {
    var request = URLRequest(url: URL(string: "https://httpbin.org/delay/5")!)
    request.timeoutInterval = 2          // server sleeps 5s before its first byte

    _ = try await URLSession.shared.data(for: request)
}

// MARK: - 2. Resource timeout
//
// The actual wall-clock cap on a whole request lives on the *configuration*:
// timeoutIntervalForResource. /drip sends a byte at a time for 6 seconds, so
// the per-request timeout never fires - only the resource timeout stops it.
//
// Both surface as URLError.timedOut, which is why you can't tell them apart
// from the error alone and have to know which one you set.

func resourceTimeout() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10    // gap between packets - never hit
    config.timeoutIntervalForResource = 3    // total budget - this is what fires
    let session = URLSession(configuration: config)
    defer { session.finishTasksAndInvalidate() }

    let url = URL(string: "https://httpbin.org/drip?duration=6&numbytes=6")!
    _ = try await session.data(from: url)
}

// MARK: - 3. Unreachable host
//
// .invalid is reserved by RFC 2606 and can never resolve, so this fails the same
// way everywhere without depending on anyone's DNS.
//
// waitsForConnectivity is the setting worth knowing here: with it on, a request
// made while offline waits for the network to come back instead of failing
// immediately. Good for a sync that can happen whenever; wrong for anything a
// user is staring at, because they get a spinner instead of an error.

func unreachableHost() async throws {
    var request = URLRequest(url: URL(string: "https://not-a-real-host.invalid/data")!)
    request.timeoutInterval = 5

    _ = try await URLSession.shared.data(for: request)
}

// MARK: - 4. Cancellation is not a failure
//
// Search-as-you-type cancels the previous request on every keystroke. If that
// path shows an error banner, the app flashes red while the user types.

func cancellation() async throws {
    let task = Task {
        try await URLSession.shared.data(from: URL(string: "https://httpbin.org/delay/5")!)
    }

    try await Task.sleep(nanoseconds: 400_000_000)
    task.cancel()

    _ = try await task.value
}

// MARK: - 5. Decoding errors (no network needed)
//
// Four cases, four different bugs. Foundation gives all of them the same
// unhelpful localizedDescription, and all of them are fatal - retrying a decode
// on the same bytes fails identically.

struct Session: Decodable {
    let id: Int
    let title: String
    let minutes: Int
    let startedAt: Date
}

let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

let brokenPayloads: [(String, String)] = [
    // keyNotFound - the API renamed or dropped a field, or the model is ahead
    // of the server. Fix: make it optional if it's genuinely optional, don't
    // paper over it with a default.
    ("keyNotFound",
     #"{"id": 1, "title": "Deep work", "startedAt": "2026-07-09T09:00:00Z"}"#),

    // typeMismatch - the classic: a number quoted as a string. Very common with
    // PHP and Rails backends, and with IDs big enough that someone made them
    // strings on purpose.
    ("typeMismatch",
     #"{"id": 1, "title": "Deep work", "minutes": "50", "startedAt": "2026-07-09T09:00:00Z"}"#),

    // valueNotFound - the key is there but null. A non-optional property can't
    // hold it. Note `String?` would accept both this and a missing key.
    ("valueNotFound",
     #"{"id": 1, "title": null, "minutes": 50, "startedAt": "2026-07-09T09:00:00Z"}"#),

    // dataCorrupted (1) - valid JSON, unparseable date. Nearly every date bug is
    // a decoding strategy that doesn't match what the server actually sends,
    // and .iso8601 rejects fractional seconds too.
    ("dataCorrupted - date",
     #"{"id": 1, "title": "Deep work", "minutes": 50, "startedAt": "9 July 2026"}"#),

    // dataCorrupted (2) - not JSON at all. Usually an HTML error page or a
    // captive-portal login screen arriving with a 200, which is exactly why
    // status codes get checked before anything is handed to the decoder.
    ("dataCorrupted - not JSON",
     "<html><body>502 Bad Gateway</body></html>"),
]

// MARK: - Run them

print("1. Request timeout (timeoutInterval = 2s, server delays 5s)")
do {
    try await requestTimeout()
    print("   unexpectedly succeeded\n")
} catch {
    report("timed out as expected", error)
}

print("2. Resource timeout (timeoutIntervalForResource = 3s, 6s trickle)")
do {
    try await resourceTimeout()
    print("   unexpectedly succeeded\n")
} catch {
    report("resource budget exhausted", error)
}

print("3. Host that cannot resolve")
do {
    try await unreachableHost()
    print("   unexpectedly succeeded\n")
} catch {
    report("transport failure", error)
}

print("4. Cancelled mid-flight")
do {
    try await cancellation()
    print("   unexpectedly succeeded\n")
} catch {
    report("cancelled - note the empty user message", error)
}

print("5. Decoding failures (local data, no network)")
for (label, json) in brokenPayloads {
    do {
        let session = try decoder.decode(Session.self, from: Data(json.utf8))
        print("   \(label): unexpectedly decoded \(session.title)\n")
    } catch let error as DecodingError {
        print("   \(label)")
        print("      localizedDescription: \(error.localizedDescription)")
        print("      what actually broke:  \(describe(error))\n")
    } catch {
        report(label, error)
    }
}

// Notes that don't fit in code:
//  - Inside a sandboxed app this needs com.apple.security.network.client (8.4).
//    Without it every request fails with URLError.notConnectedToInternet, which
//    sends you hunting for a network problem that doesn't exist.
//  - Never put a raw error into the UI. Coding paths and status codes belong in
//    the log; the user gets a sentence and, only when it would help, a Retry.
//  - Test the failure paths with Network Link Conditioner or by switching wifi
//    off mid-request. Error handling that has never run is not error handling.
