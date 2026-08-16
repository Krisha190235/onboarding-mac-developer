//
//  URLProtocolTests.swift
//
//  Level 2: the same API, but the mock sits *inside* URLSession rather than
//  replacing it. These are slower and clumsier than the stub-client tests, and
//  they're worth a handful of cases because they're the only ones that prove
//  URLSession itself does what I think it does with the request.
//
//  `.serialized` because MockURLProtocol.handler is global state and Swift
//  Testing runs tests in parallel by default. Without it, two tests set the
//  handler and one gets the other's response — an intermittent failure that
//  looks like a networking bug and isn't.
//

import Foundation
import Testing
@testable import MockAPIKit

@Suite("PlaceholderAPI through a real URLSession", .serialized)
struct URLProtocolTests {

    private func makeAPI() -> PlaceholderAPI {
        PlaceholderAPI(baseURL: PlaceholderAPI.jsonplaceholder,
                       client: MockURLProtocol.session(),
                       backoffScale: 0)
    }

    @Test("a stubbed response survives the whole URLSession stack")
    func responseTravelsThroughURLSession() async throws {
        MockURLProtocol.respond(status: 200, json: try Fixture.json("posts"))
        defer { MockURLProtocol.reset() }

        let posts = try await makeAPI().posts()

        #expect(posts.count == 3)
        #expect(posts[1].title == "qui est esse")
    }

    @Test("URLSession sends the headers and query the layer set")
    func requestReachesTheProtocolIntact() async throws {
        // Capture the request as URLSession actually hands it over, rather than
        // as the layer built it - the two can differ.
        let recorder = RequestRecorder()
        MockURLProtocol.handler = { request in
            recorder.record(request)
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)!
            return (response, Data("[]".utf8))
        }
        defer { MockURLProtocol.reset() }

        _ = try await makeAPI().posts(userID: 7)

        let request = try #require(recorder.last)
        #expect(request.url?.absoluteString
                == "https://jsonplaceholder.typicode.com/posts?userId=7")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("a 500 from inside the session still maps to a retryable error")
    func serverErrorMapsCorrectly() async throws {
        MockURLProtocol.respond(status: 500, json: #"{"error":"boom"}"#)
        defer { MockURLProtocol.reset() }

        do {
            _ = try await makeAPI().post(id: 1)
            Issue.record("expected a 500 to throw")
        } catch let error as APIError {
            guard case .http(let status, let body) = error else {
                Issue.record("expected .http, got \(error)")
                return
            }
            #expect(status == 500)
            #expect(body.contains("boom"))     // the body survives - it's the diagnostic
            #expect(error.isRetryable)
        }
    }
}
