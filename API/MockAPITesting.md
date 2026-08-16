# 9.7 Mock API Testing

**Deliverable:** Project using jsonplaceholder/mocky.

The project: [`API/MockAPIKit/`](MockAPIKit) — a Swift package with a client for
`jsonplaceholder.typicode.com` and three different ways of testing it.

```bash
cd API/MockAPIKit
swift test                              # mocked only - offline, deterministic
RUN_INTEGRATION_TESTS=1 swift test      # adds the live jsonplaceholder suite
```

It's a package rather than an app because the deliverable is the *tests*, and a
package gives a real test target that runs from the command line and from
Xcode's Test Navigator — same shape as `CounterKit` in 7.7. Swift Testing
(`@Test` / `#expect`), tools version 6.0.

## Layout

| Path | |
| --- | --- |
| `Sources/MockAPIKit/PlaceholderAPI.swift` | The client — the 9.6 layer trimmed down |
| `Sources/MockAPIKit/HTTPClient.swift` | The protocol everything hinges on |
| `Tests/.../PlaceholderAPITests.swift` | 13 tests against a stub client |
| `Tests/.../URLProtocolTests.swift` | 3 tests through a real `URLSession` |
| `Tests/.../IntegrationTests.swift` | 6 tests against the live API, gated |
| `Tests/.../Fixtures/*.json` | Real responses captured with `curl` |

## Three levels of mocking, and when each earns its place

**1. Stub the `HTTPClient` protocol.** No `URLSession` involved at all.

```swift
let client = MockHTTPClient(.status(503, "{}"), .status(503, "{}"), .ok(fixture))
let api = PlaceholderAPI(client: client, maxAttempts: 3, backoffScale: 0)
```

Microseconds per test, impossible to flake, and a three-attempt retry sequence is
one line. This is where nearly every test should live.

**2. `URLProtocol` subclass.** The mock sits *inside* `URLSession` instead of
replacing it, so the request goes through the real stack — header handling, query
serialisation, cache policy, redirects. Slower and clumsier, worth a handful of
cases, because it's the only level that can catch `URLSession` doing something
you didn't expect to what you built.

**3. The live API.** jsonplaceholder for the happy path; mocky.io for the shapes
jsonplaceholder can't produce. Gated behind an environment variable.

The tests deliberately assert on **both directions**: what the client *sends*
(URL, method, headers, encoded body) as well as what it does with what comes
back. Most mock-API testing only checks the second half, which is how a request
ships with a missing `Content-Type`.

## The gate on the live tests

```swift
@Suite("Live jsonplaceholder",
       .enabled(if: ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "1"))
```

Not laziness. These fail when someone else's server is down, when the CI box has
no DNS, and when a build machine sits behind a proxy — none of which are bugs in
this package. **A suite that goes red for reasons the author can't fix gets
ignored, and then it's worse than not existing.**

What they're for is the one thing mocks structurally cannot do: tell you the
fixtures still match reality. A fully mocked suite stays green forever after the
API changes shape. So the live suite ends with:

```swift
@Test("the live shape still matches the checked-in fixture")
```

which decodes both and compares — not the whole model, since content can
legitimately change, but the ids, keys and types.

## Fixtures

The JSON in `Tests/.../Fixtures/` was captured from jsonplaceholder with `curl`,
not written by hand. That matters: a fixture I invent proves the model matches my
imagination, and the real thing has the quirks — `\n` inside `body`, an email
with an uppercase local part, `postId` next to `userId`.

They load through `Bundle.module`, which exists because `Package.swift` declares
them, using `.copy("Fixtures")` rather than `.process`. `.copy` keeps the folder
intact so the lookup is predictable:

```swift
Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
```

## Two concurrency traps

Swift Testing runs tests **in parallel by default**, and the package builds in
Swift 6 language mode, so both showed up immediately.

`MockHTTPClient` is an **actor**, because it records the requests it receives and
a class with a mutable array is a data race that will eventually be blamed on
something else. An actor's `async` method can satisfy an `async` protocol
requirement — which is a reason for `HTTPClient.perform` to be async beyond the
obvious one.

`MockURLProtocol` can't be an actor: `URLSession` instantiates the subclass, so
there's nowhere to inject anything and the handler has to be global. That's
`nonisolated(unsafe)` plus `.serialized` on the suite:

```swift
@Suite("PlaceholderAPI through a real URLSession", .serialized)
```

Without it, two tests set the handler and one receives the other's response —
an intermittent failure that looks exactly like a networking bug.

## What about mocky.io

jsonplaceholder can't return a 500, a truncated body, or a 10-second response, so
it can't cover the failure half of a networking layer. mocky.io fills that gap:
paste a body, choose a status and a delay, get a permanent URL. Nothing here needs
changing to use one, because the base URL is injected:

```swift
let api = PlaceholderAPI(baseURL: URL(string: "https://run.mocky.io/v3/<id>")!)
```

Having set that up, I'd still reach for the stub client. A mocky URL is a
dependency on someone else's uptime plus a magic string nobody on the team can
regenerate once the tab is closed — in exchange for a failure `MockHTTPClient`
produces in one line. It's genuinely useful for sharing a response shape with
someone else, or for testing an app you can't recompile.

## What I learned

The injectable `HTTPClient` from 9.6 was four lines of protocol, and this is
where it pays: every failure from 9.5 that I could only demonstrate by finding a
cooperative endpoint is now a two-line stub, and the retry logic from 9.4 is
testable without waiting three seconds per case.

The thing I'd have got wrong without writing it out is the split between mocked
and live. My instinct was to pick one. The actual answer is that they test
different things — mocks test my code, integration tests test my *assumptions*
about someone else's — and the fixture-drift test is the seam between them, which
is the only reason the live suite is worth having at all.

## Sources

- [jsonplaceholder](https://jsonplaceholder.typicode.com) — the fake API
- [Swift Testing](https://developer.apple.com/documentation/testing) — Apple
- [`URLProtocol`](https://developer.apple.com/documentation/foundation/urlprotocol) — Apple
- [Bundling resources with a Swift package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package) — Apple
- [SE-0412: `nonisolated(unsafe)`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0412-strict-concurrency-for-global-variables.md) — Swift Evolution
