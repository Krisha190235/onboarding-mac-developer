# 9.4 POST Request

**Deliverable:** Swift file sending a POST request.

The file: [`API/PostRequest.swift`](PostRequest.swift). Four sections, all against
public test endpoints so nothing real is created.

```bash
swift API/PostRequest.swift
```

| # | Section | Endpoint |
| --- | --- | --- |
| 1 | JSON body, decode the created resource | `jsonplaceholder.typicode.com/posts` |
| 2 | `application/x-www-form-urlencoded` body | `httpbin.org/post` |
| 3 | `multipart/form-data` upload, built by hand | `httpbin.org/post` |
| 4 | Retry with backoff and an idempotency key | `jsonplaceholder.typicode.com/posts` |

## What changes from a GET

```swift
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

let body = try JSONEncoder().encode(NewSession(title: "Deep work", minutes: 50, userId: 7))
let (data, response) = try await URLSession.shared.upload(for: request, from: body)
```

Three things, and each has a trap behind it:

- **`Content-Type` describes what you're sending**, `Accept` describes what you
  want back. Sending a JSON body without the header is the usual explanation for
  an inexplicable 400 or 415.
- **`upload(for:from:)` rather than setting `httpBody`.** Both work for a normal
  session, but `httpBody` is silently ignored by background sessions, so the
  upload variant is the habit worth having.
- **Success isn't only 200.** A create is usually **201 Created** with a
  `Location` header; some APIs answer **202 Accepted** or **204 No Content**.
  Checking `== 200` rejects perfectly good responses.

## Reading failures properly

```swift
case 400...499:
    throw APIError.client(status: http.statusCode,
                          body: String(data: data, encoding: .utf8) ?? "")
default:
    throw APIError.server(status: http.statusCode)
```

The split isn't cosmetic — it decides whether retrying is sane. A 4xx means the
request is wrong and will fail identically next time; a 5xx or a dropped
connection might succeed on a second attempt. And the **body of a 4xx normally
says exactly what's wrong**, so discarding it in favour of "request failed" throws
away the best diagnostic in the exchange.

## Retrying a write is not like retrying a read

A GET can be repeated freely. A POST can't: the first attempt may have succeeded
with only the *response* getting lost, so a blind retry creates the resource
twice. The sample handles this in two ways:

1. **Retry only what's worth retrying** — transport failures and 5xx. Never a 4xx,
   never a decoding error.
2. **Send an `Idempotency-Key`**, generated once and reused across every attempt,
   so a server that supports it recognises the duplicate and returns the original
   result instead of creating a second record.

Backoff is exponential with a little jitter (`2^n + random`), so a fleet of
clients recovering from an outage doesn't stampede the server in lockstep.

## Body encodings

| Content type | When | Gotcha |
| --- | --- | --- |
| `application/json` | Almost every modern API | Nothing much — `Encodable` does the work |
| `application/x-www-form-urlencoded` | Old web forms, many OAuth token endpoints | `.urlQueryAllowed` is **too permissive**: it leaves `+`, `&` and `=` unescaped, which corrupts the pairs. Use an explicit allowed set |
| `multipart/form-data` | File uploads | CRLF (`\r\n`) line endings, a boundary that appears in the header *and* between parts, and the closing boundary needs trailing `--` |

The multipart section builds the body by hand rather than reaching for a library,
because it's about 20 lines and seeing the format once makes every "my upload
returns 400" bug obvious afterwards.

## Security notes

- Inside a sandboxed app this needs `com.apple.security.network.client` (8.4) —
  there's no TCC prompt for it.
- **Never log a request that carries an `Authorization` header.** Log the URL and
  the status, not the headers, or a token ends up in a crash report.
- Tokens belong in the Keychain, not in source, not in `Info.plist`, and not in a
  committed `.env`.

## What I learned

A POST is a GET plus a body, and then a completely different set of questions.
Reading is idempotent and forgiving; writing forces decisions about what counts as
success, which failures are worth repeating, and what happens when the network
disappears in the gap between the server committing and the client hearing about
it. The idempotency key is the neat part — it moves that problem somewhere it can
actually be solved, by giving the server enough information to recognise the
retry.

## Sources

- [Uploading data to a website](https://developer.apple.com/documentation/foundation/uploading-data-to-a-website) — Apple
- [`URLSession.upload(for:from:)`](https://developer.apple.com/documentation/foundation/urlsession/upload(for:from:)) — Apple
- [RFC 7807 / HTTP status semantics](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status) — MDN
