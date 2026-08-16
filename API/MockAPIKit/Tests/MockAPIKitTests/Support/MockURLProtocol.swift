//
//  MockURLProtocol.swift
//
//  Level 2 of three. Instead of replacing URLSession, this intercepts inside it:
//  a URLProtocol subclass registered on a session configuration gets handed
//  every request before it reaches the network.
//
//  Worth having as well as MockHTTPClient because it exercises the real thing —
//  header handling, the query string as URLSession actually serialises it,
//  cache policy, redirects. If URLSession is going to mangle something, this
//  catches it and a protocol stub can't.
//
//  The cost is visible below: a class-based, pre-concurrency API with global
//  mutable state, which means `nonisolated(unsafe)` and a serialised suite.
//

import Foundation

final class MockURLProtocol: URLProtocol {
    /// Global by necessity — URLProtocol subclasses are instantiated by
    /// URLSession, so there's nowhere to inject anything. `nonisolated(unsafe)`
    /// is the honest annotation: the compiler can't prove this is safe, and it
    /// only is because the suite using it is marked `.serialized`.
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func respond(status: Int = 200, json: String) {
        handler = { request in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            return (response, Data(json.utf8))
        }
    }

    static func reset() { handler = nil }

    /// A session configured with this protocol and nothing else — no cache, no
    /// cookies, no chance of a stray real request.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            // Forgetting this is the classic mistake: the request never
            // finishes and the test hangs until the timeout rather than failing.
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Somewhere for a handler closure to record what it saw. A reference type, so
/// the closure captures the box rather than a mutable local — which keeps the
/// capture legal under Swift 6 without sprinkling `nonisolated(unsafe)` on
/// local variables.
final class RequestRecorder: @unchecked Sendable {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) { requests.append(request) }

    var last: URLRequest? { requests.last }
}
