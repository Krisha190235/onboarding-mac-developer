//
//  IntegrationTests.swift
//
//  Level 3: the real jsonplaceholder. Skipped unless you ask for them:
//
//      RUN_INTEGRATION_TESTS=1 swift test
//
//  The gate isn't laziness. These tests fail when someone else's server is
//  down, when the CI box has no DNS, and when a build machine is behind a proxy
//  — none of which are bugs in this package. A suite that goes red for reasons
//  the author can't fix gets ignored, and then it's worse than not existing.
//
//  What they're for is the one thing mocks structurally cannot do: tell you the
//  fixtures still match reality. A mocked suite stays green forever after the
//  API changes shape.
//

import Foundation
import Testing
@testable import MockAPIKit

@Suite("Live jsonplaceholder", .enabled(if: ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1"))
struct IntegrationTests {

    private let api = PlaceholderAPI()

    @Test("a real post still decodes into the model")
    func realPostDecodes() async throws {
        let post = try await api.post(id: 1)

        #expect(post.id == 1)
        #expect(post.userId == 1)
        #expect(!post.title.isEmpty)
        #expect(!post.body.isEmpty)
    }

    @Test("the list endpoint still returns 100 posts")
    func realListDecodes() async throws {
        let posts = try await api.posts()
        #expect(posts.count == 100)
    }

    @Test("filtering by user still works server-side")
    func realQueryFilterWorks() async throws {
        let posts = try await api.posts(userID: 3)

        #expect(posts.count == 10)
        #expect(posts.allSatisfy { $0.userId == 3 })
    }

    @Test("a create returns the resource with a server-assigned id")
    func realCreateReturnsID() async throws {
        // jsonplaceholder fakes writes: it always answers 201 with id 101 and
        // persists nothing, which is exactly what makes it safe to run.
        let created = try await api.create(NewPost(userId: 1,
                                                   title: "Deep work",
                                                   body: "50 minutes"))
        #expect(created.id == 101)
        #expect(created.title == "Deep work")
    }

    @Test("a missing post really is a 404")
    func realNotFound() async throws {
        do {
            _ = try await api.post(id: 9_999_999)
            Issue.record("expected a 404")
        } catch let error as APIError {
            guard case .http(let status, _) = error else {
                Issue.record("expected .http, got \(error)")
                return
            }
            #expect(status == 404)
        }
    }

    // MARK: - The test that stops fixtures rotting

    @Test("the live shape still matches the checked-in fixture")
    func fixtureStillMatchesReality() async throws {
        let live = try await api.post(id: 1)
        let fixture = try JSONDecoder().decode(Post.self, from: Fixture.data("post"))

        // Not a full equality check - the content could legitimately change.
        // What's asserted is the shape: same keys, same types, same ids.
        #expect(live.id == fixture.id)
        #expect(live.userId == fixture.userId)
        #expect(live.title == fixture.title)
    }
}

//
//  A note on mocky.io
//  ------------------
//  jsonplaceholder can't produce a 500, a malformed body, or a slow response,
//  so it can't cover the failure half of the layer on its own. mocky.io fills
//  that gap: you paste a body, pick a status code and a delay, and it hands
//  back a permanent URL.
//
//  Nothing here needs a rewrite to use one, because the base URL is injected:
//
//      let api = PlaceholderAPI(baseURL: URL(string: "https://run.mocky.io/v3/<id>")!)
//
//  That's the argument for the stub client, though. A mocky URL is a dependency
//  on someone else's uptime and a magic string that no one on the team can
//  regenerate once the tab is closed, in exchange for a failure the tests above
//  already produce in one line.
//
