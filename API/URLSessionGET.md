# 9.1 URLSession GET Request

**Deliverable:** Swift file printing fetched JSON.

The file: [`API/FetchRepoJSON.swift`](FetchRepoJSON.swift). It GETs a repository
from the GitHub API, decodes it into a Swift type, prints the decoded fields and
then the raw JSON.

```bash
swift API/FetchRepoJSON.swift                 # this repo
swift API/FetchRepoJSON.swift apple/swift     # any public repo
```

No token needed — the endpoint is public, rate-limited to 60 requests an hour per
IP when unauthenticated.

## The request

```swift
var request = URLRequest(url: url)
request.httpMethod = "GET"
request.timeoutInterval = 15
request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
request.setValue("onboarding-mac-developer/1.0", forHTTPHeaderField: "User-Agent")

let (data, response) = try await URLSession.shared.data(for: request)
```

`URLSession.shared.data(for:)` is the modern async/await form. The older
completion-handler API still exists and is what you'll see in most tutorials:

```swift
URLSession.shared.dataTask(with: request) { data, response, error in
    // three optionals, and you must call resume()
}.resume()
```

Three optionals means eight possible combinations, most of them impossible — the
async version replaces that with a tuple and a thrown error, which is why it's
worth converting old code.

Two headers matter here: **GitHub rejects requests with no `User-Agent`**, and it
versions the API through `Accept` / `X-GitHub-Api-Version` rather than the URL.

## Status codes are not errors

`URLSession` only throws for *transport* failures — no network, DNS failure,
timeout, TLS problem. A 404 or a 403 is a perfectly successful round trip, so the
status code has to be checked by hand:

```swift
guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }

switch http.statusCode {
case 200:      break
case 403, 429: throw FetchError.rateLimited(
                   remaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining"))
case 404:      throw FetchError.notFound(repo)
default:       throw FetchError.badStatus(http.statusCode)
}
```

The script distinguishes them because they need different responses: rate limited
means wait, 404 means the name is wrong or the repo is private, and a decoding
failure means the API changed shape. Collapsing all three into "request failed"
throws away everything useful.

## Decoding

```swift
struct Repository: Decodable {
    let fullName: String
    let description: String?   // null in the JSON
    let htmlURL: String
    let pushedAt: Date
    let license: License?      // the whole object can be null
    …
}
```

Points the sample makes deliberately:

- **Model only the slice you need.** `JSONDecoder` ignores unknown keys, so there's
  no reason to mirror a large payload.
- **Optionals are the contract.** `description` and `license` are genuinely
  nullable; making them non-optional turns a normal response into a crash-adjacent
  decoding error.
- **Explicit `CodingKeys` beat `.convertFromSnakeCase` here.** The automatic
  strategy would map `html_url` to `htmlUrl` and `spdx_id` to `spdxId` — not what
  anyone would name those by hand. The strategy is fine when the whole API is
  consistently snake_case and you don't mind its idea of capitalisation.
- **Dates need a strategy.** `.iso8601` handles GitHub's `2026-08-16T09:12:33Z`.
  Without it, `Date` decoding fails or silently reads a number.

Catching `DecodingError` separately is worth it: it means the payload changed, not
that the network broke, and its description names the exact key path.

## What this needs inside a real app

The script runs unsandboxed, but the same code in `HelloApp` would need:

| Requirement | Why |
| --- | --- |
| `com.apple.security.network.client` entitlement | The sandbox blocks outgoing connections by default (8.4) |
| HTTPS | App Transport Security refuses plain HTTP; exceptions must be declared in `Info.plist` and justified at review |
| No secrets in the binary | An API token compiled into an app is readable by anyone who downloads it |

There's no TCC prompt for network access — the user is never asked. That's a
useful contrast with milestone 8: the sandbox decides this one entirely at build
time.

## Beyond the basics

- **`URLSession.shared` vs a configured session.** A custom
  `URLSessionConfiguration` gets you per-session timeouts, caching policy, and
  default headers rather than repeating them per request.
- **Cancellation is free with async/await.** Cancelling the enclosing `Task`
  cancels the request, which matters for a view that disappears mid-fetch.
- **Retry deliberately.** Retrying a 500 with backoff is reasonable; retrying a
  404 never is.
- **Testing.** Injecting a `URLProtocol` subclass into the session configuration
  lets tests return canned responses with no network at all — the standard way to
  unit-test this kind of code.

## What I learned

The interesting part of a GET isn't the GET. `URLSession` gets the bytes in three
lines; everything else in the file is about being precise about failure — transport
error versus HTTP status versus decoding mismatch — because those three need
different handling and the API deliberately doesn't merge them. The other lesson
is how much the decoder tells you if you let it: `DecodingError` names the exact
key that didn't match, which beats printing the whole payload and squinting.

## Sources

- [Fetching website data into memory](https://developer.apple.com/documentation/foundation/fetching-website-data-into-memory) — Apple
- [`URLSession`](https://developer.apple.com/documentation/foundation/urlsession) — Apple
- [GitHub REST API — repositories](https://docs.github.com/en/rest/repos/repos)
