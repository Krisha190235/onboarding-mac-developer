//
//  MockHTTPClient.swift
//
//  Level 1 of three. Conforms to the package's own HTTPClient protocol, so it
//  replaces URLSession entirely: no network stack involved, no timing, nothing
//  to flake.
//
//  It's an actor because it records the requests it was given and Swift Testing
//  runs tests in parallel — a class with a mutable array is a data race waiting
//  to be blamed on something else. An actor's async method can satisfy an async
//  protocol requirement, which is exactly why HTTPClient.perform is async.
//

import Foundation
@testable import MockAPIKit

actor MockHTTPClient: HTTPClient {
    struct Stub: Sendable {
        var status: Int = 200
        var body: Data = Data()
        /// Thrown instead of returning, for transport failures like a timeout.
        /// `& Sendable` so the whole Stub can cross into the actor — URLError
        /// and APIError both qualify.
        var error: (any Error & Sendable)?

        static func ok(_ body: Data) -> Stub { Stub(status: 200, body: body) }
        static func ok(_ json: String) -> Stub { Stub(status: 200, body: Data(json.utf8)) }
        static func status(_ code: Int, _ json: String = "{}") -> Stub {
            Stub(status: code, body: Data(json.utf8))
        }
        static func failure(_ error: any Error & Sendable) -> Stub { Stub(error: error) }
    }

    /// Consumed in order. The last one repeats, so a test that only cares about
    /// the first response doesn't have to pad the array.
    private var stubs: [Stub]
    private(set) var receivedRequests: [URLRequest] = []

    init(_ stubs: Stub...) {
        self.stubs = stubs.isEmpty ? [Stub.ok("{}")] : stubs
    }

    var callCount: Int { receivedRequests.count }

    var lastRequest: URLRequest? { receivedRequests.last }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)

        let stub = stubs.count > 1 ? stubs.removeFirst() : stubs[0]
        if let error = stub.error { throw error }

        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: stub.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
        return (stub.body, response)
    }
}
