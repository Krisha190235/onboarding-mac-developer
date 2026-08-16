# 9.5 Networking Error Handling

**Deliverable:** Timeout and decoding error examples.

The file: [`API/NetworkingErrors.swift`](NetworkingErrors.swift). Five sections —
two kinds of timeout, an unreachable host, a cancellation, and all four
`DecodingError` cases.

```bash
swift API/NetworkingErrors.swift
```

Sections 1–4 hit `httpbin.org`; section 5 is entirely local, so the decoding
examples still run with the wifi off.

| # | Failure | How it's produced |
| --- | --- | --- |
| 1 | Request timeout | `timeoutInterval = 2` against `httpbin.org/delay/5` |
| 2 | Resource timeout | `timeoutIntervalForResource = 3` against `httpbin.org/drip` (6s trickle) |
| 3 | Transport failure | `not-a-real-host.invalid` — RFC 2606, can never resolve |
| 4 | Cancellation | `Task` cancelled 400 ms into a 5s request |
| 5 | Decoding | Five malformed payloads decoded into one `Session` type |

## Two timeouts, and only one of them is the one you meant

```swift
request.timeoutInterval = 2                      // gap between packets
config.timeoutIntervalForResource = 3            // total wall clock
```

`timeoutInterval` on a `URLRequest` is **not** a deadline for the call. It's the
maximum gap between packets, and it **resets every time data arrives** — which is
why a server that trickles bytes for a minute never trips it. The actual budget
for the whole request lives on `URLSessionConfiguration.timeoutIntervalForResource`.

Section 2 makes the distinction visible: `timeoutIntervalForRequest` is set to 10
seconds and never fires, because `/drip` keeps sending. The 3-second resource
timeout is what ends it.

Both surface as `URLError.timedOut`, so the error can't tell you which one fired.
You have to know which one you set.

## `URLError.cancelled` is not an error

An async `URLSession` call that gets cancelled throws **`URLError.cancelled`**,
not `CancellationError`. A `catch` that only checks for `CancellationError` will
treat it as a real failure and put a banner on screen for something the user did
deliberately — navigating away, or typing the next character in a search box that
cancels the previous request on every keystroke.

That's why `.cancelled` maps to an empty `userMessage` in the sample: it's a case
that must be *recognised* precisely so that nothing is shown.

## One error type at the edge

`URLError`, `DecodingError` and "HTTP 503" arrive from three different places and
none of them are fit to show a user. The sample collapses them into one enum with
three questions answered:

```swift
var userMessage: String   // safe for the screen - no status codes, no coding paths
var errorDescription: String?  // for the log - all the detail
var isRetryable: Bool     // should a Retry button even appear
```

The retry flag is the one that changes behaviour. Timeouts, offline and 5xx are
worth repeating; **a 4xx and a decoding failure are not** — the same request
produces the same bytes and the same crash into the decoder, so a Retry button
there just makes the user press it three times before giving up. The exceptions
worth allowing are **408** (server-side timeout) and **429** (rate limited), which
are 4xx but *are* time-dependent.

## The four decoding errors

`localizedDescription` on a `DecodingError` is famously useless — "The data
couldn't be read because it is missing." The information you need is in the
associated `Context`, specifically `codingPath` and `debugDescription`, and it's
only reachable by switching on the case. That's what `describe(_:)` does, and the
sample prints both so the gap is obvious.

| Case | What the payload did | What it usually means |
| --- | --- | --- |
| `keyNotFound` | Dropped `minutes` | Field renamed server-side, or the model is ahead of the API. Make it optional only if it's genuinely optional |
| `typeMismatch` | `"minutes": "50"` | A number quoted as a string — common with PHP/Rails backends, and with IDs large enough that someone made them strings deliberately |
| `valueNotFound` | `"title": null` | Key present, value null, property non-optional. `String?` accepts *both* this and a missing key |
| `dataCorrupted` | `"startedAt": "9 July 2026"` | The `dateDecodingStrategy` doesn't match what the server sends. `.iso8601` also rejects fractional seconds |
| `dataCorrupted` | `<html>502 Bad Gateway</html>` | Not JSON at all — an error page or a captive portal arriving with a 200 |

The last row is the argument for checking the status code *before* handing
anything to the decoder: a hotel wifi login page returns 200 with HTML, and if the
decoder sees it first you spend the afternoon debugging your model instead of your
network.

## Testing failures you can't wait for

Error handling that has never run isn't error handling. Ways to make it run:

- **Network Link Conditioner** (Additional Tools for Xcode) — 100% loss, or the
  "Very Bad Network" profile for realistic timeouts.
- **Switch wifi off mid-request** — the crudest and still the most useful, because
  it produces `networkConnectionLost` rather than `notConnectedToInternet`, which
  is a distinction most code gets wrong.
- **`httpbin.org/status/503`, `/delay/N`, `/drip`** — deterministic failures on
  demand, no fixtures to maintain.
- **Local JSON fixtures** for the decoding path, as in section 5. Fast, offline,
  and they belong in a unit test.

## Security notes

- Inside a sandboxed app, a missing `com.apple.security.network.client` (8.4)
  makes every request fail with `URLError.notConnectedToInternet` — which sends
  you hunting for a network problem that doesn't exist.
- **Never put a raw error in front of a user.** Coding paths, hostnames, status
  codes and response bodies go in the log; the screen gets a sentence.
- The body of a failed response can contain tokens or personal data, so it's for
  local logging, not crash reports or analytics.

## What I learned

The two failures in the title are opposites. A timeout is transient, ambiguous and
worth retrying; a decoding error is deterministic, precise and never worth
retrying — the bytes will be just as wrong the second time. Treating them the same
way produces both of the classic bugs: a Retry button that can't possibly work,
and a silent failure where the useful diagnostic was thrown away.

The part that surprised me was how much detail Foundation hides behind
`localizedDescription`. Everything needed to fix a decoding bug — which key, which
type, how deep in the payload — is sitting in the `Context`, and it only appears
if you switch on the case rather than printing the error.

## Sources

- [Handling transport errors](https://developer.apple.com/documentation/foundation/url-loading-system) — Apple
- [`URLError.Code`](https://developer.apple.com/documentation/foundation/urlerror/code) — Apple
- [`DecodingError`](https://developer.apple.com/documentation/swift/decodingerror) — Apple
- [`timeoutIntervalForResource`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforresource) — Apple
- [RFC 2606 — reserved top-level domains](https://datatracker.ietf.org/doc/html/rfc2606) — IETF
